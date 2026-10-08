# KTB4-10th-infra

# KGB V2 Infrastructure

## 1. 프로젝트 개요

KGB V2 인프라를 AWS와 Terraform으로 구축한다.
기존 V1 인프라는 유지하고, V2를 별도로 구축 및 검증한 후 트래픽을 전환할 예정

## 2. 전체 아키텍처

> 아래는 **현재 목표 아키텍처** 

```
                         Users
                           │
                           ▼
                       CloudFront
                           │
                  ┌────────┴────────┐
                  │                 │
                  ▼                 ▼
             S3 (Frontend)      ALB (Public)
                                    │
                          ┌─────────┴─────────┐
                          │                   │
                          ▼                   ▼
                    ECS Backend A       ECS Backend C
                    Private App A       Private App C
                          │                   │
                          └─────────┬─────────┘
                                    │
                              RDS MySQL
                              (Single-AZ)

              Private App A             Private App C
                    │                         │
                    ▼                         ▼
              NAT Instance A            NAT Instance C
                    │                         │
                    └──────────┬──────────────┘
                               │
                           Internet
                               │
                         RunPod API
```

### 네트워크 구성

|구분|AZ|CIDR|
|---|---|---|
|VPC|-|`10.10.0.0/16`|
|Public A|ap-northeast-2a|`10.10.0.0/24`|
|Public C|ap-northeast-2c|`10.10.1.0/24`|
|Private App A|ap-northeast-2a|`10.10.10.0/24`|
|Private App C|ap-northeast-2c|`10.10.20.0/24`|
|Private DB A|ap-northeast-2a|`10.10.40.0/24`|
|Private DB C|ap-northeast-2c|`10.10.50.0/24`|

## 3. Terraform 구현 및 커밋 계획

| 단계  | 구현 범위                                   | 커밋 메시지                                 | 상태   |
| --- | --------------------------------------- | -------------------------------------- | ---- |
| 1   | VPC, Subnet 6개, IGW, Route Table        | `feat: add VPC network foundation`     | 진행 중 |
| 2   | NAT Instance 2대, NAT SG, EIP, NAT Route | `feat: add NAT instances and routing`  | 예정   |
| 3   | ALB, ALB SG, Target Group               | `feat: add application load balancer`  | 예정   |
| 4   | ECS Cluster, EC2, ECS Service           | `feat: add ECS backend infrastructure` | 예정   |
| 5   | RDS MySQL, DB Subnet Group, DB SG       | `feat: add RDS MySQL database`         | 예정   |
| 6   | S3, CloudFront                          | `feat: add frontend hosting`           | 예정   |


## 4. 배포 원칙

- Terraform 코드는 기능 단위로 작성하고 GitHub에 커밋한다.
- `terraform fmt`, `validate`, `plan`을 확인한 뒤 AWS 배포를 결정한다.
- GitHub에 코드를 올리는 것과 `terraform apply`는 별개

<details>
<summary><strong>Terraform 주요 명령어 보기</strong></summary>

### 1. 작업 디렉터리 이동

```bash
cd prod
```

### 2. Terraform 초기화

```bash
terraform init
```

Provider 및 모듈을 초기화한다.

### 3. 코드 포맷 확인 및 정리

```bash
terraform fmt -recursive
```

Terraform 코드의 형식을 정리한다.

### 4. 코드 유효성 검사

```bash
terraform validate
```

Terraform 설정의 기본적인 유효성을 검사한다.

### 5. 변경 사항 미리 확인

```bash
terraform plan
```

AWS에 적용될 리소스 생성·변경·삭제 계획을 확인한다.

### 6. 배포 계획 저장

```bash
terraform plan -out=tfplan
```

검토한 배포 계획을 파일로 저장한다.

### 7. AWS에 실제 적용

```bash
terraform apply tfplan
```

저장한 배포 계획을 AWS에 적용한다.

> **주의:** `terraform apply`는 실제 AWS 리소스를 생성·변경·삭제하며 비용이 발생할 수 있다. 반드시 Plan을 검토한 뒤 실행한다.

### 8. 적용된 리소스 확인

```bash
terraform state list
```

Terraform State에서 관리 중인 리소스를 확인한다.

</details>
