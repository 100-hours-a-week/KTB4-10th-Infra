# KGB V2 ECS 인프라 설계

## 1. 설계 목적

KGB V2의 Spring Boot Backend를 AWS ECS on EC2 환경에서 운영한다.

주요 목표는 다음과 같다.

- Backend Task 2개를 서로 다른 EC2 인스턴스에서 실행한다.
- 가능한 한 서로 다른 가용 영역(AZ)에 Backend Task를 분산한다.
- Rolling Deployment 중 최소 2개의 정상 Backend Task를 유지한다.
- 배포 시 필요한 EC2 용량을 일시적으로 확장한다.
- 트래픽 기반 Auto Scaling은 부하 테스트 이후 도입 여부와 기준을 결정한다.

## 2. 아키텍처

```text
CloudFront
    │
    ▼
Application Load Balancer
    │ HTTPS 443
    ▼
ECS Cluster
    │
    └── ECS Service (Backend)
            │
            ├── EC2-A (ap-northeast-2a)
            │     ├── Spring Boot Task
            │     └── Monitoring Task
            │
            └── EC2-B (ap-northeast-2c)
                  ├── Spring Boot Task
                  └── Monitoring Task
```

- ECS Cluster는 Backend 컨테이너의 실행 환경을 제공한다.
- ECS Service는 원하는 Backend Task 수를 유지한다.
- Auto Scaling Group(ASG)은 ECS용 EC2 인스턴스를 관리한다.
- Capacity Provider는 ECS와 ASG를 연결한다.
- ALB는 정상 상태의 Backend Task로 요청을 전달한다.

## 3. ECS 실행 방식

| 항목                     | 설정               |
|------------------------|------------------|
| ECS Launch Type        | EC2              |
| EC2 인스턴스               | t3.small         |
| ECS Service Scheduling | REPLICA          |
| Backend Desired Count  | 2                |
| Network Mode           | awsvpc           |
| Backend Container Port | 8080             |
| ALB Target Group Type  | ip               |
| Placement Constraint   | distinctInstance |
| Placement Strategy     | spread (AZ 기준)   |

### 3.1 Task 배치 정책

`distinctInstance`를 사용하여 동일 ECS Service의 Backend Task가 서로 다른 EC2 인스턴스에 배치되도록 한다.

AZ 기준 `spread` 전략을 사용하여 Backend Task가 서로 다른 AZ에 분산되도록 유도한다.

단, 다음 사항에 유의한다.

- `distinctInstance`는 EC2 인스턴스 단위의 분리를 보장한다.
- AZ 기준 `spread`는 분산을 유도하는 전략이며, AZ별 Task 1개를 절대적으로 보장하지 않는다.
- 따라서 배포 완료 후 실제 Task의 AZ 분포를 검증해야 한다.

## 4. EC2 용량 관리

### 4.1 Auto Scaling Group

| 항목               | 설정                              |
|------------------|---------------------------------|
| Instance Type    | t3.small                        |
| AMI              | ECS Optimized Amazon Linux 2023 |
| Min Size         | 2                               |
| Desired Capacity | 2                               |
| Max Size         | 3                               |
| Subnet           | Private App Subnet 2a, 2c       |

초기 운영 시 EC2 인스턴스 2대를 유지한다.

ASG는 EC2 인스턴스 장애 발생 시 Desired Capacity를 복구하도록 구성한다.

단, EC2 인스턴스 수가 복구되었다고 해서 Backend 서비스의 정상 상태가 즉시 복구되는 것은 아니다.

### 4.2 ECS Capacity Provider

ECS Capacity Provider를 ASG와 연결한다.

초기에는 배포 파이프라인에서 EC2 증설을 직접 제어하는 방식을 검토한다.

이에 따라 초기 구성에서는 Capacity Provider Managed Scaling을 비활성화하는 방향으로 설계한다.

```hcl
managed_scaling {
  status = "DISABLED"
}
```

이 설정에서는 ECS가 Task 수요에 따라 EC2 인스턴스 수를 자동으로 증가시키지 않는다.

배포 시 EC2 증설과 축소는 별도의 배포 파이프라인에서 관리해야 한다.

## 5. ECS 무중단 배포 전략

### 5.1 배포 설정

| 항목                         | 설정                 |
|----------------------------|--------------------|
| Deployment Type            | Rolling Deployment |
| Minimum Healthy Percent    | 100                |
| Maximum Percent            | 200                |
| Deployment Circuit Breaker | Enabled            |
| Automatic Rollback         | Enabled            |

Backend Service의 Desired Count가 2이므로, 배포 중 최소 2개의 정상 Task 유지를 목표로 한다.

단, ECS 배포 설정만으로 모든 순간의 ALB Healthy Target 2개가 보장되는 것은 아니다.

실제 배포 시 ALB Target Health와 Task 상태를 함께 검증해야 한다.

### 5.2 배포 전 EC2 증설

평상시에는 EC2 2대에 Backend Task 2개를 배치한다.

새 버전 배포 시 기존 Task를 유지하면서 신규 Task를 실행할 수 있도록 배포 시작 전에 EC2를 1대 추가한다.

```text
평상시
EC2 2대 / Backend Task 2개
          │
          ▼
배포 파이프라인 시작
          │
          ▼
ASG Desired Capacity: 2 → 3
          │
          ▼
신규 EC2 생성
          │
          ▼
ECS Cluster 등록 확인
          │
          ▼
Task 배치 가능 리소스 확인
          │
          ▼
ECS Service 업데이트
```

배포 파이프라인은 EC2가 생성되었다는 사실만으로 배포를 시작하지 않는다.

다음 항목을 확인한 후 배포를 진행한다.

- 신규 EC2가 ECS Cluster에 정상 등록되었는가?
- ECS Container Instance가 ACTIVE 상태인가?
- 신규 Backend Task를 실행할 CPU 및 메모리 여유가 있는가?
- Task 실행에 필요한 네트워크 리소스가 확보되었는가?

### 5.3 배포 완료 검증

배포 완료 후 다음 조건을 확인한다.

1. 신규 버전 Backend Task 2개가 실행 중이다.
2. ALB Healthy Target이 2개 이상이다.
3. 이전 버전 Backend Task가 남아 있지 않다.
4. Backend Task가 서로 다른 EC2 인스턴스에 배치되었다.
5. 최종 Backend Task가 서로 다른 AZ에 분산되어 있다.

### 5.4 배포 후 EC2 축소

배포 완료 후 EC2를 3대에서 2대로 축소한다.

단, ASG Desired Capacity만 단순히 3에서 2로 변경하지 않는다.

종료 대상 EC2를 명시적으로 선정해야 한다.

축소 절차는 다음과 같다.

1. Backend Task가 실행되지 않는 EC2를 찾는다.
2. 해당 EC2를 종료해도 AZ 분산이 유지되는지 확인한다.
3. ECS Container Instance를 DRAINING 상태로 변경한다.
4. 종료 대상 인스턴스를 지정하여 ASG에서 제거한다.
5. ASG Desired Capacity가 2로 감소했는지 확인한다.
6. Backend Task 2개와 ALB Healthy Target 2개가 유지되는지 확인한다.

종료할 수 있는 EC2가 없다면 자동 축소를 중단한다.

이 경우 EC2 3대를 일시적으로 유지하고 운영 알림을 발생시킨다.

자동 Task 재배치를 통한 AZ 분산 복구는 초기 구현 범위에서 제외하며, 추후 검증 후 도입한다.

## 6. 트래픽 기반 Auto Scaling

### 6.1 초기 운영 정책

초기에는 ECS Service의 Backend Task 수를 2개로 고정한다.

```hcl
desired_count = 2
```

트래픽 기반 ECS Service Auto Scaling은 초기 구현 범위에서 제외한다.

그 이유는 현재 V2 환경에서 Backend 확장이 필요한 임계값이 측정되지 않았기 때문이다.

### 6.2 추후 검증 항목

V2 환경에서 부하 테스트를 수행하여 다음 지표를 측정한다.

- ALB Request Count
- ALB Target Response Time (p95)
- Backend CPU 사용률
- Backend 메모리 사용률
- HikariCP Active Connections
- HikariCP Pending Connections
- RDS CPU 사용률
- RDS 연결 수 및 쿼리 지연

측정 결과를 바탕으로 다음 항목을 결정한다.

- ECS Service Auto Scaling 도입 여부
- Scale-out 임계값
- Scale-in 임계값
- 최소 및 최대 Backend Task 수
- Scaling Cooldown
- ASG 최대 인스턴스 수

현재 ASG Max Size 3은 배포용 임시 용량을 고려한 값이다.

추후 트래픽 기반 확장을 도입하면 배포용 여유 용량을 포함하여 ASG 상한을 재검토해야 한다.

## 7. Terraform 구성

Terraform AWS ECS 모듈 사용을 검토한다.

- 모듈: `terraform-aws-modules/ecs/aws`
- Cluster와 Service는 별도 서브모듈로 분리한다.
- EC2 Launch Template과 ASG는 별도 `ecs-capacity` 모듈에서 관리한다.

### 7.1 디렉터리 구조

```text
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
│
└── modules/
    ├── vpc/
    ├── security-group/
    ├── iam/
    │
    ├── ecs-cluster/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── ecs-capacity/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── user_data.sh.tpl
    │
    └── ecs-service/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### 7.2 모듈별 책임

| 모듈           | 담당 리소스                                   |
|--------------|------------------------------------------|
| ecs-cluster  | ECS Cluster                              |
| ecs-capacity | Launch Template, ASG, Capacity Provider  |
| ecs-service  | Task Definition, ECS Service, 배치 및 배포 정책 |

Capacity Provider의 Cluster 연결 위치는 모듈 간 의존성을 고려하여 결정한다.

## 8. 단계별 구현 계획

### 1단계: ECS Cluster

- ECS Cluster 생성
- Container Insights 초기 비활성화
- Terraform Plan 검증
- Cluster 생성 확인

### 2단계: ECS Capacity

- ECS Optimized AMI 조회
- Launch Template 작성
- ECS Instance Profile 연결
- ASG 작성
- Capacity Provider 연결
- ECS Cluster 등록 검증

### 3단계: Backend Service

- Task Definition 작성
- ECS Service 생성
- ALB Target Group 연결
- Placement Constraint 및 Strategy 설정
- Backend Task 2개 실행 검증

### 4단계: 배포 자동화

- 배포 전 ASG 증설
- ECS 신규 버전 배포
- Healthy Target 검증
- 배포 후 안전한 EC2 축소
- 배포 실패 시 롤백 검증

### 5단계: 성능 검증

- V2 부하 테스트
- 병목 구간 확인
- Auto Scaling 필요성 검토
- 확장 및 축소 기준 결정

## 9. 미검증 항목

| 항목                        | 상태  | 검증 방법                       |
|---------------------------|-----|-----------------------------|
| ECS Cluster 생성            | 예정  | Terraform Apply 및 AWS 콘솔 확인 |
| t3.small 메모리 여유           | 미검증 | 실제 Task 실행 후 메모리 측정         |
| EC2당 Backend Task 1개 배치   | 미검증 | ECS Placement 결과 확인         |
| AZ별 Backend Task 분산       | 미검증 | Task 배치 AZ 확인               |
| 배포 중 Healthy Target 2개 유지 | 미검증 | 실제 Rolling Deployment 테스트   |
| 배포 전 EC2 증설 자동화           | 미구현 | 파이프라인 테스트                   |
| 배포 후 안전한 EC2 축소           | 미구현 | 종료 대상 선정 및 장애 테스트           |
| 트래픽 기반 확장 임계값             | 미측정 | V2 부하 테스트                   |

## 10. 설계 결정 요약

| 결정 항목                    | 현재 결정              |
|--------------------------|--------------------|
| ECS 실행 환경                | EC2                |
| 초기 Backend Task 수        | 2                  |
| 초기 EC2 수                 | 2                  |
| 배포 시 최대 EC2 수            | 3                  |
| 배포 방식                    | Rolling Deployment |
| 배포 중 최소 정상 Task 목표       | 2                  |
| 배포 전 EC2 증설              | 배포 파이프라인에서 수행      |
| 배포 후 EC2 축소              | 안전성 검증 후 수행        |
| ECS Service Auto Scaling | 추후 도입 여부 결정        |
| Auto Scaling 임계값         | V2 부하 테스트 후 결정     |

---

**설계 상태: REVISION REQUIRED**

전체 아키텍처 방향은 정의되었으나, 배포 전 증설과 배포 후 축소의 자동화 방식 및 실제 무중단 배포 동작은 검증되지 않았다.

따라서 초기에는 ECS Cluster부터 구현하고, EC2 용량 관리와 배포 자동화는 단계적으로 검증한다.