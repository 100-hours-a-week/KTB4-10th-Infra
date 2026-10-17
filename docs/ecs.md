# KGB V2 ECS 인프라 설계

2026-10-16 기준.

개념 설명은 [ecs-guide.md](ecs-guide.md) 참고

## 1. 설계 목적

KGB V2의 Spring Boot Backend를 AWS ECS on EC2 환경에서 운영한다.

- Backend Task 2개를 서로 다른 EC2 인스턴스에서 실행한다.
- 가능한 한 서로 다른 가용 영역(AZ)에 Backend Task를 분산한다.
- 배포 시 필요한 EC2 용량을 일시적으로 확장한다(블루/그린 검토 중).
- 트래픽 기반 Auto Scaling은 기준 결정 필요

## 2. 아키텍처

```text
CloudFront (V1 리소스 재사용)
    │ HTTPS 443
    ▼
Application Load Balancer (예정)
    │ 8080 (API) / 8081 (헬스 체크)
    ▼
ECS Cluster (kgb-prod-cluster)
    │
    ├── EC2 (ap-northeast-2a, private-app)
    │     ├── Backend Task        :8080, :8081
    │     ├── node-exporter       :9100 (예정, Daemon)
    │     └── cAdvisor            :8082 (예정, Daemon)
    │
    └── EC2 (ap-northeast-2c, private-app)
          ├── Backend Task        :8080, :8081
          ├── node-exporter       :9100 (예정, Daemon)
          └── cAdvisor            :8082 (예정, Daemon)

Backend → RDS (3306, VPC 내부)
Backend → NAT → 인터넷 (443: GHCR, 카카오, Tour API, S3 등)
```

- ECS Cluster는 Backend 컨테이너의 실행 환경을 제공한다.
- Auto Scaling Group(ASG)은 ECS용 EC2 인스턴스를 관리한다.
- Capacity Provider는 ECS와 ASG를 연결한다.
- ECS Service는 원하는 Backend Task 수를 유지한다.
- ALB는 정상 상태의 Backend Task로 요청을 전달한다(예정).

## 3. ECS 실행 방식

| 항목                     | 설정                                    |
|------------------------|---------------------------------------|
| ECS Launch Type        | EC2 (Capacity Provider)               |
| EC2 인스턴스               | t3.small                              |
| ECS Service Scheduling | REPLICA                               |
| Backend Desired Count  | 운영 2 (현재 0)                           |
| Network Mode           | `bridge`                              |
| Port Mapping           | 8080:8080 (API), 8081:8081 (Actuator) |
| ALB Target Group Type  | `instance`                            |
| Placement Constraint   | `distinctInstance`                    |
| Placement Strategy     | `spread` (AZ 기준)                      |

### 3.1 Task 배치 정책

`distinctInstance`로 같은 Service의 Backend Task가 서로 다른 EC2에 배치되도록 한다. AZ 기준 `spread`로 서로 다른 AZ에 분산되도록 유도한다.

- `distinctInstance`는 EC2 인스턴스 단위의 분리를 보장한다.
- AZ 기준 `spread`는 분산을 유도하는 전략이며, AZ별 Task 1개를 절대적으로 보장하지 않는다.
- 배포 완료 후 실제 Task의 AZ 분포를 검증해야 한다.

### 3.2 네트워크 모드: bridge

| 항목        | bridge (선택)                                | awsvpc                           |
|-----------|--------------------------------------------|----------------------------------|
| 컨테이너 네트워크 | EC2 네트워크를 Docker 브리지로 공유                   | Task마다 ENI와 IP                   |
| 적용되는 SG   | **EC2의 SG (`ecs-host-sg`)**                | Task의 SG                         |
| 포트        | 호스트 포트에 매핑                                 | 컨테이너 포트 그대로                      |
| ALB 대상 타입 | `instance`                                 | `ip`                             |
| 선택 이유     | V1에서 사용하던 방식으로 운영 경험이 있음. Task별 ENI가 필요 없음 | `t3.small`은 ENI 최대 3개라 Task 수 제한 |

bridge에서는 Task에 SG를 붙일 수 없어, awsvpc용으로 만들었던 `backend-task-sg`를 삭제하고 Backend 관련 규칙을 `ecs-host-sg`로 옮겼다.

### 3.3 포트

| 포트   | 용도                                                         | 허용 출발지                 |
|------|------------------------------------------------------------|------------------------|
| 8080 | Backend API                                                | ALB                    |
| 8081 | Backend 관리 포트 (`/actuator/health`, `/actuator/prometheus`) | ALB(헬스 체크), Monitoring |
| 8082 | cAdvisor (예정)                                              | Monitoring             |
| 9100 | node-exporter (예정)                                         | Monitoring             |

- 8081은 ALB Listener에 연결하지 않으므로 외부에서 접근할 수 없다. ALB는 헬스 체크 요청만 8081로 보낸다.
- 호스트 포트는 고정이다. EC2당 Backend Task가 1개라 동적 포트의 이점이 없고, SG를 포트 하나로 좁게 열 수 있다.

### 3.4 메모리

| 항목                         | 값             |
|----------------------------|---------------|
| EC2가 Task에 할당 가능한 메모리      | 1913 MiB (실측) |
| Backend 컨테이너 상한 (`memory`) | 1536 MiB      |
| 모니터링 Daemon 몫              | 약 377 MiB     |

- V1 Backend 실사용량은 약 514 MiB(`docker stats` 측정)이다.
- V1 cAdvisor + node-exporter 실사용량은 약 58 MiB이다.
- 상한을 넘으면 컨테이너가 강제 종료된다.
- JVM 힙은 컨테이너 상한 기준으로 정해진다(기본 약 25%). JVM 메모리 옵션 여부는 Backend 팀 확인이 필요하다.

## 4. EC2 용량 관리

### 4.1 Auto Scaling Group

| 항목                  | 설정                 |
|---------------------|--------------------|
| 이름                  | `kgb-prod-ecs-asg` |
| Instance Type       | t3.small           |
| Min / Desired / Max | 2 / 2 / 4          |
| Subnet              | private-app 2a, 2c |
| Health Check        | EC2                |

- Max 4는 블루/그린 배포 시 기존 2대 + 신규 2대를 고려한 값이다.
- `desired_capacity`는 `ignore_changes`로 처리한다. 배포 중 늘린 대수를 다음 apply가 되돌려 서버를 종료하지 않도록 하기 위함이다.
- ASG 안의 인스턴스는 정지(stop)하면 ASG가 교체한다. 비용을 줄이려면 ASG를 0대로 줄인다.
- Capacity Provider를 연결하면 ECS가 ASG에 `AmazonECSManaged` 태그를 자동으로 붙인다. 코드에도 같은 태그를 선언해 plan 차이를 없앴다.

### 4.2 Launch Template

| 항목               | 설정                                                                                        |
|------------------|-------------------------------------------------------------------------------------------|
| AMI              | SSM `/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id` (apply 시점 최신) |
| 루트 볼륨            | gp3 30GiB, 암호화                                                                            |
| Instance Profile | `kgb-prod-ecs-instance-profile` (ECS 등록, SSM)                                             |
| IMDS             | IMDSv2 필수, hop limit 1                                                                    |
| user data        | `ECS_CLUSTER=kgb-prod-cluster`, `ECS_ENABLE_TASK_IAM_ROLE=true`                           |
| 태그               | 인스턴스와 볼륨에 `Name` + provider `default_tags`                                                |

- AMI는 보안 패치 반영을 위해 자동 조회한다. AWS가 새 AMI를 내면 plan에 Launch Template 변경이 나타나고, 이후 새로 뜨는 EC2부터 적용된다. 기존 EC2는 바뀌지 않는다.
- hop limit 1로 bridge 컨테이너가 IMDS에 접근하지 못하게 해서, 컨테이너가 EC2 Role 자격 증명을 가져갈 수 없다. 컨테이너 권한은 Task Role로만 받는다.
- ASG가 만드는 EC2와 볼륨에는 provider `default_tags`가 자동으로 붙지 않아 `aws_default_tags` data 소스로 직접 지정함.

### 4.3 ECS Capacity Provider

| 항목                             | 설정                                  |
|--------------------------------|-------------------------------------|
| 이름                             | `kgb-prod-ecs-cp`                   |
| Managed Scaling                | DISABLED                            |
| Managed Termination Protection | DISABLED                            |
| 클러스터 기본 전략                     | `kgb-prod-ecs-cp`, weight 1, base 0 |

현재는 ECS가 Task 수요에 따라 EC2를 자동으로 늘리지 않는다. 블루/그린 배포를 도입하면 Managed Scaling과 Termination Protection을 켜는 방안을 검토한다(6장).

## 5. Backend Task Definition과 Service

### 5.1 Task Definition

| 항목             | 설정                                                                 |
|----------------|--------------------------------------------------------------------|
| Family         | `kgb-prod-backend`                                                 |
| 이미지            | `ghcr.io/100-hours-a-week/ktb4-10-be:6b98f8f-20261013` (V1과 같은 버전) |
| 이미지 인증         | `repositoryCredentials` → Secrets Manager `kgb-prod/ghcr`          |
| Execution Role | `kgb-prod-task-execution-role`                                     |
| Task Role      | `kgb-prod-task-role`                                               |
| 로그             | `awslogs`, Log Group `/kgb-prod/backend` (90일)                     |
| 컨테이너 헬스 체크     | 없음 (이미지에 curl 포함 여부 미확인, ALB 헬스 체크 사용 예정)                          |

- GHCR 이미지가 비공개라 인증이 필요하다. ECS 비공개 레지스트리 인증은 Secrets Manager만 지원한다. 값은
  `{"username": ..., "password": <read:packages PAT>}` 형식이다.
- AWS가 저장 시 `mountPoints`, `volumesFrom`, `systemControls`를 빈 값으로 채우므로 코드에도 빈 값으로 명시. 없으면 매 plan마다 Task Definition 교체가
  나타난다.

### 5.2 환경 변수와 비밀 값

| 구분   | 위치                                                   | 개수 | 예                                               |
|------|------------------------------------------------------|----|-------------------------------------------------|
| 일반 값 | `prod/backend.tf` (`locals`)                         | 17 | `DB_URL`, `DB_USERNAME`, `CORS_ALLOWED_ORIGINS` |
| 비밀 값 | Parameter Store `/kgb-prod/backend/*` (SecureString) | 7  | `DB_PASSWORD`, `KAKAO_CLIENT_SECRET`            |

- Terraform은 Parameter Store를 `CHANGE_ME`로 만들고(`ignore_changes = [value]`), 실제 값은 콘솔에서 직접 입력한다. state와 git에 비밀 값이 남지
  않는다.
- 비밀 값은 Task Definition에 ARN만 들어가고, Task 시작 시점에 ECS가 값을 꺼내 주입한다. 값을 바꾸면 Task를 다시 시작해야 반영된다.
- `DB_USERNAME`은 V1 앱 계정과 같은 `kgb`이다. RDS 계정은 SQL로 직접 생성([rds.md](rds.md) 7.4).
- `TOUR_API_SCHEDULER_ENABLED`는 V1과 동시 실행을 막기 위해 `false`로 시작한다.

### 5.3 Service

| 항목                         | 설정                         |
|----------------------------|----------------------------|
| 이름                         | `kgb-prod-backend`         |
| Desired Count              | **0** (컷오버 시 2)            |
| Minimum Healthy Percent    | 50                         |
| Maximum Percent            | 100                        |
| Deployment Circuit Breaker | Enabled, 자동 롤백             |
| Load Balancer              | 없음 (ALB 단계에서 연결)           |
| Tags                       | `propagate_tags = SERVICE` |

- 호스트 포트가 고정이라 같은 EC2에 새 Task를 함께 띄울 수 없다. ALB와 블루/그린 도입 전까지는 1개씩 교체(최소 50%, 최대 100%)한다.
- 기본 Task 수는 0개다. 시험 기동할 때만 `-var backend_desired_count=2`로 올리고 끝나면 내린다. RDS `kgb` DB의 데이터는 DMS 테스트 마이그레이션 결과라, 실제 이전 전에 비우고 다시 옮긴다.

### 5.4 IAM

| Role                           | 권한                                                                                              |
|--------------------------------|-------------------------------------------------------------------------------------------------|
| `kgb-prod-task-execution-role` | `AmazonECSTaskExecutionRolePolicy`, Secrets Manager `kgb-prod/*`, Parameter Store `/kgb-prod/*` |
| `kgb-prod-task-role`           | S3 `kgb-s3-storage` 목록 조회, 객체 읽기·쓰기·삭제 (V1 `kgb-be-ec2-role`의 `s3access`와 같은 범위)                |

V1은 EC2 Role로 S3에 접근했지만, V2는 IMDS를 막아 두어 Task Role에 권한을 따로 부여했다.

## 6. 배포 전략

### 6.1 방향 (결정)

| 상황                     | 방식                                          | 이유                                     |
|------------------------|---------------------------------------------|----------------------------------------|
| V1 → V2 전환 (1회)        | 1차: V1 Backend를 RDS로 전환 → 2차: V1·V2 사이 **카나리** (10% → 50% → 100%) | 서버·네트워크·DB가 한꺼번에 바뀌는 큰 전환이라, 문제를 일부 사용자 범위에서 먼저 발견 |
| 평소 배포 (V2 → V2 새 버전)   | **블루/그린**                                   | 배포 중 처리 용량이 줄지 않고, 문제 시 ALB 전환만 되돌려 즉시 롤백 |
| 트래픽이 늘어난 뒤             | 평소 배포에도 카나리 검토                              | Task 2개·적은 트래픽에서는 비율 분할과 문제 발견 효과가 작음  |

- 카나리는 두 버전이 **같은 DB**를 쓸 때만 가능하다. V1이 V1 MySQL, V2가 RDS를 쓰는 상태에서 트래픽을 나누면 데이터가 두 DB로 갈라진다. 그래서 V1 전환은 DB 전환(1차) 후에 카나리(2차)로 진행한다.
- V1·V2 카나리의 비율 분할 방법(Route 53 가중치 레코드, CloudFront 연속 배포)과 오리진 프로토콜 차이(V1 HTTP 8080, V2 HTTPS 443) 처리는 컷오버 설계 때 정한다.
- 롤링(1개씩 교체)과 블루/그린은 모두 무중단이다. 롤링은 교체 중 처리 용량이 절반이 되고, 블루/그린은 배포 중 EC2가 2배 필요하다.

### 6.2 현재 설정과 블루/그린 비교

| 항목        | 현재              | 블루/그린 (예정)                              |
|-----------|-----------------|-----------------------------------------|
| 방식        | Rolling, 1개씩 교체 | 신규 Task 2개를 새 EC2 2대에 띄우고 ALB로 전환       |
| EC2 수     | 2               | 배포 중 최대 4                               |
| 필요 조건     | -               | ALB, Target Group 2개, 확인 시간(bake time)  |
| EC2 증설·축소 | -               | Capacity Provider Managed Scaling 사용 검토 |

- `t3.small` 1대에 Backend Task가 1개만 들어가므로, 신규 Task를 띄우려면 EC2가 추가로 필요하다.

**고정 포트에서의 블루/그린**

```text
1. EC2 2대 추가 (2 → 4)
   EC2-A [Blue :8080]  EC2-C [Blue :8080]  EC2-B [비어 있음]  EC2-D [비어 있음]
2. Green Task 2개 시작
   A, C는 8080이 사용 중 → ECS가 비어 있는 B, D에 배치
3. ALB가 Green Target Group(B, D)으로 트래픽 전환
4. 확인 시간 동안 문제 없으면 Blue 종료, 문제 있으면 Blue로 복귀
5. 빈 EC2 A, C 축소 (4 → 2)
```

- ECS는 Task를 배치할 때 필요한 호스트 포트가 비어 있는 EC2를 고른다. 고정 포트는 Green이 Blue와 같은 EC2에 배치되지 않도록 하는 역할을 한다.
- 실제 제약은 포트가 아니라 메모리다. EC2당 가용 메모리 1913 MiB에 1536 MiB Task가 1개만 들어가므로, 동적 포트로 바꿔도 EC2 추가가 필요하다.
- 따라서 고정 포트를 유지하고, 배포 중 EC2를 늘리고 줄이는 방법(Managed Scaling 또는 파이프라인)을 정하는 것이 핵심이다.
- 현재 Service 설정(최소 50%, 최대 100%)은 Blue 1개를 내리고 Green 1개를 띄우는 Rolling 방식이라 EC2 추가 없이 동작하지만, 배포 중 Task가 1개로 줄어든다.
- Managed Scaling 없이 ASG를 직접 4 → 2로 줄이면 ASG가 Task가 있는 EC2를 종료할 수 있다. Managed Termination Protection을 켜면 Task가 있는 EC2는 축소
  대상에서 제외된다.
- Managed Scaling의 축소는 EC2가 빈 뒤 약 15분 후에 일어난다. 롤백을 위한 확인 시간은 배포 설정의 bake time으로 보장해야 한다.
- 블루와 그린이 같은 RDS를 쓰므로 DB 스키마 변경(Flyway)은 이전 버전과 호환되도록 나눠서 배포해야 한다.
- ECS 자체 블루/그린 배포가 bridge + `instance` Target Group 조합을 지원하는지는 ALB 단계에서 확인한다.

## 7. 트래픽 기반 Auto Scaling

초기에는 Backend Task 수를 2개로 고정하고, ECS Service Auto Scaling은 도입하지 않는다. V2 환경에서 확장이 필요한 임계값을 아직 측정하지 않았기 때문이다.

부하 테스트로 다음 지표를 측정한 뒤 도입 여부와 기준을 정한다.

- ALB Request Count, Target Response Time (p95)
- Backend CPU·메모리 사용률
- HikariCP Active / Pending Connections
- RDS CPU 사용률, 연결 수, 쿼리 지연

트래픽 기반 확장을 도입하면 배포용 여유 용량을 포함해 ASG 상한(현재 4)을 재검토한다.

## 8. Terraform 구성

커뮤니티 모듈(`terraform-aws-modules/ecs/aws`)을 검토했으나, 다른 모듈과 같이 리소스를 직접 작성했다. 커뮤니티 모듈을 써도 ASG와 Launch Template은 직접 작성해야 하고,
Fargate 예시는 bridge 모드를 지원하지 않는다.

| 위치                  | 담당 리소스                                                                         |
|---------------------|--------------------------------------------------------------------------------|
| `modules/ecs`       | ECS Cluster, Launch Template, ASG, Capacity Provider                           |
| `modules/backend`   | Secrets Manager(GHCR), Parameter Store 7개, Log Group, Task Definition, Service |
| `prod/backend.tf`   | Backend 일반 환경 변수 (`locals`)                                                    |
| `prod/variables.tf` | 인스턴스 타입, ASG 대수, 이미지, 메모리, Task 수, DB 계정 이름                                    |

## 9. 구현 단계

| 단계 | 내용                                      | 상태            |
|----|-----------------------------------------|---------------|
| 1  | ECS Cluster                             | 완료            |
| 2  | Launch Template, ASG, Capacity Provider | 완료 (2대 등록 확인) |
| 3  | Backend Task Definition, Service        | 완료 (Task 0개)  |
| 4  | ALB, Target Group, Service 연결           | 예정            |
| 5  | 모니터링 Daemon (cAdvisor, node-exporter)   | 예정            |
| 6  | 배포 방식 (블루/그린, CD)                       | 검토 중          |
| 7  | 성능 검증, Auto Scaling                     | 예정            |

## 10. 검증

### 10.1 확인한 것

| 항목                        | 결과                                      |
|---------------------------|-----------------------------------------|
| EC2 2대 Cluster 등록         | 완료, `ACTIVE`, Agent 연결                  |
| AZ 분산                     | 2a 1대, 2c 1대                            |
| private-app → NAT → 외부 통신 | 양쪽 AZ 정상 (ECS API, SSM, 이미지 다운로드)       |
| SSM 접속                    | 두 EC2 모두 `Online`                       |
| 컨테이너의 IMDS 접근 차단          | bridge 컨테이너에서 토큰 요청 시 시간 초과 (`exit=28`) |
| Task에 할당 가능한 자원           | EC2당 CPU 2048, 메모리 1913 MiB             |
| 공통 태그                     | EC2 교체 후 `Project = KGB-V2` 확인          |
| `terraform plan`          | `No changes`                            |

### 10.2 미검증

| 항목                                         | 검증 시점              |
|--------------------------------------------|--------------------|
| Backend Task 기동 (이미지 다운로드, 비밀 값 주입, DB 연결) | 빈 DB로 시험 기동 또는 컷오버 |
| Backend 메모리 사용량, JVM 힙                     | Task 실행 후          |
| AZ별 Backend Task 분산                        | Task 실행 후          |
| ALB 헬스 체크(8081)                            | ALB 구축 후           |
| 배포 중 Healthy Target 유지                     | 배포 방식 구현 후         |
| 트래픽 기반 확장 임계값                              | 부하 테스트             |

## 11. 컷오버 시 주의

- Backend Task를 띄우면 사용자 요청이 없어도 스케줄 작업이 RDS에 쓴다.
    - Tour API 동기화: `TOUR_API_SCHEDULER_ENABLED`로 제어 (현재 `false`)
    - 월 무료 생성권 보충: **매월 1일 00:00**, 끄는 설정 없음
    - SSE 하트비트: 15초마다, DB 쓰기 없음
- 시험 기동으로 Task를 띄웠다면 **매월 1일 00:00 전에 반드시 0개로 내린다.** V1과 V2가 함께 생성권을 충전해 RDS에 기록이 중복된다.
- 스케줄러 중복 실행 방지(락)는 같은 DB 안에서만 동작한다. V1과 V2는 DB가 달라 서로의 락을 볼 수 없으므로, 전환 시 V1 스케줄러를 먼저 끄고 V2를 켠다.

## 12. 설계 결정 요약

| 결정 항목                    | 현재 결정                                     |
|--------------------------|-------------------------------------------|
| ECS 실행 환경                | EC2 (t3.small)                            |
| 네트워크 모드                  | bridge, 호스트 포트 고정                         |
| Backend 포트               | API 8080, 관리 8081                         |
| Backend Task 수           | 운영 2, 컷오버 전 0                             |
| EC2 수                    | 평상시 2, 배포 시 최대 4                          |
| AMI                      | SSM 파라미터로 최신 권장 AMI 자동 조회                 |
| 비밀 값                     | Parameter Store, GHCR 인증만 Secrets Manager |
| 배포 방식                    | 현재 Rolling(1개씩), 블루/그린 검토 중               |
| ECS Service Auto Scaling | 부하 테스트 후 결정                               |
