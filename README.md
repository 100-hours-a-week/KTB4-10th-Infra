# KGB V2 Infrastructure

KGuideBook(KGB) V2 서비스의 AWS 인프라를 Terraform으로 관리하는 저장소입니다.

## 1. 프로젝트 개요

- KGB V2 인프라를 AWS와 Terraform으로 구축하고 관리합니다.
- 기존 V1 인프라는 유지하면서 V2를 별도 VPC에 구축·검증한 후 트래픽을 전환할 예정입니다.
- V1은 단일 EC2 기반으로 운영 중이며, V2에서는 Backend를 ECS로 운영하고 데이터베이스를 RDS MySQL Multi-AZ로 분리할 계획입니다.
- Terraform을 통해 인프라 구성의 재현성과 변경 관리 효율성을 높이고자 합니다.

| 항목 | 내용 |
| --- | --- |
| 리전 | `ap-northeast-2` (서울) |
| 가용 영역 | `ap-northeast-2a`, `ap-northeast-2c` |
| Terraform | `~> 1.16.0` |
| AWS Provider | `~> 6.0` |
| State | HCP Terraform (`KGuideBook` 조직, `kgb-infra-prod` 워크스페이스, 로컬 실행) |

## 2. 전체 아키텍처

> 아래는 **목표 아키텍처**입니다. 실제 배포 상태는 [3. 구현 현황](#3-구현-현황)을 참고합니다.

```text
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
                              (Multi-AZ)

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

| 구분 | AZ | CIDR |
| --- | --- | --- |
| VPC | - | `10.10.0.0/16` |
| Public A | ap-northeast-2a | `10.10.0.0/24` |
| Public C | ap-northeast-2c | `10.10.1.0/24` |
| Private App A | ap-northeast-2a | `10.10.10.0/24` |
| Private App C | ap-northeast-2c | `10.10.20.0/24` |
| Private DB A | ap-northeast-2a | `10.10.40.0/24` |
| Private DB C | ap-northeast-2c | `10.10.50.0/24` |

### 네트워크 설계

- Public Subnet에 ALB와 NAT Instance를 배치합니다.
- Private App Subnet에 ECS Backend를 배치합니다.
- Private DB Subnet에 RDS MySQL을 배치합니다.
- Private App Subnet의 인터넷 방향 트래픽은 동일 AZ의 NAT Instance를 경유하도록 구성했습니다.
- Private DB Subnet에는 인터넷으로 향하는 기본 경로를 설정하지 않았습니다.
- ECS Backend와 RDS는 VPC 내부 네트워크를 통해 통신하며 NAT Instance를 경유하지 않습니다.

> NAT Instance와 라우팅 구성은 완료했으며, Private App Subnet에서 실제 외부 통신이 가능한지는 추가 검증이 필요합니다.

### 운영 접근 방식

- 외부 SSH(22) 포트를 개방하지 않고 **SSM Session Manager**를 사용합니다.
- RDS는 Private Subnet에 배치하고 Public Access를 비활성화했습니다.
- 로컬에서 RDS에 접근할 때는 NAT Instance를 SSM 포트 포워딩의 중계 EC2로 활용합니다.
- IAM Identity Center를 통해 AWS 접근 권한을 관리합니다.

```text
Local PC
   │
   │ SSM Session Manager
   ▼
NAT Instance (SSM 중계 EC2)
   │
   │ TCP 3306
   ▼
RDS MySQL (Private)
```

SSM 포트 포워딩 예시:

```bash
aws sso login --profile kgb-dev

aws ssm start-session \
  --profile kgb-dev \
  --target <NAT_INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<RDS_ENDPOINT>"],"portNumber":["3306"],"localPortNumber":["13306"]}' \
  --region ap-northeast-2
```

세션 연결 후 로컬 DB 클라이언트에서 `127.0.0.1:13306`으로 접속할 수 있습니다.

> NAT Instance는 NAT 기능이 아니라 SSM 포트 포워딩의 중계 서버 역할을 수행합니다. 중계 EC2가 중지되면 해당 경로를 통한 접속은 불가능합니다.

## 3. 구현 현황

| 단계 | 모듈 | 구현 범위 | 상태 |
| --- | --- | --- | --- |
| 1 | `network` | VPC, Subnet 6개, IGW, Route Table | 배포 완료 |
| 2 | `security` | Security Group 6개 (ALB, Backend Task, ECS Host, RDS, Monitoring, NAT) | 배포 완료 |
| 3 | `iam` | ECS·Monitoring·NAT Role, GitHub Actions OIDC 배포 Role, 개발자 포트 포워딩 정책 | 배포 완료 |
| 4 | `nat` | NAT Instance 2대, EIP, Private App 라우팅 | 배포 완료 / 통신 검증 필요 |
| 5 | `rds` | RDS MySQL 8.4 Multi-AZ, DB Subnet Group, Parameter Group | 배포 완료 |
| 6 | - | ALB, Target Group | 예정 |
| 7 | - | ECS Cluster, EC2, ECS Service | 설계 중 |
| 8 | - | S3, CloudFront | 예정 |
| 9 | - | V1 → V2 데이터 마이그레이션 (AWS DMS Full Load + CDC) | 검토 중 |

> 배포 완료는 AWS 리소스 생성이 완료된 상태를 의미하며, 장애 대응 및 운영 검증까지 완료했다는 의미는 아닙니다.

## 4. 디렉터리 구조

```text
.
├── modules/
│   ├── network/     # VPC, Subnet, IGW, Route Table
│   ├── security/    # Security Group 및 규칙
│   ├── iam/         # IAM Role, Policy, OIDC
│   ├── nat/         # NAT Instance, EIP, 라우팅
│   └── rds/         # RDS MySQL, Subnet Group, Parameter Group
├── prod/            # 운영 환경 루트 모듈
├── docs/            # 모듈별 설계 문서
└── .github/         # PR 템플릿
```

- 리소스는 `modules/<이름>`에 정의하고 `prod/main.tf`에서 호출합니다.
- 리소스 이름은 `kgb-prod-<용도>` 형식을 따릅니다.
- 현재 Dev 환경은 수동으로 관리합니다.

## 5. 주요 설계 결정

| 항목 | 결정 | 이유 및 고려 사항 |
| --- | --- | --- |
| NAT | NAT Gateway 대신 NAT Instance (`t3.micro` × 2) | 비용 절감을 고려한 선택. AZ별 NAT를 분리해 장애 영향 범위를 제한하지만, 해당 AZ의 NAT 장애 시 아웃바운드 통신에 영향이 발생할 수 있음 |
| 접근 | SSM Session Manager | SSH 포트 개방과 SSH 키 관리 없이 IAM 기반으로 접근 제어 |
| 아웃바운드 | 인터넷 방향 TCP 443 허용 | 필요한 HTTPS 통신을 기준으로 제한. 실제 서비스 통신 검증 필요 |
| DB 비밀번호 | `password_wo` (write-only) | Terraform State에 비밀번호 값이 저장되지 않도록 구성 |
| DB 파라미터 | 사용자 정의 Parameter Group | V1과 `sql_mode`를 일치시켜 데이터 이전 후 동작 차이를 줄이기 위함 |
| DB 보호 | 삭제 방지, 최종 스냅샷, 자동 백업 7일 | 의도하지 않은 삭제와 데이터 손실 위험 감소 |
| AMI | NAT Instance AMI ID 고정 | 최신 AMI 변경으로 인한 의도하지 않은 인스턴스 교체 방지 |

### RDS 구성

| 항목 | 구성 |
| --- | --- |
| Engine | MySQL 8.4 |
| Instance Class | `db.t3.small` |
| Storage | gp3, 20 GiB |
| Multi-AZ | 활성화 |
| Public Access | 비활성화 |
| Backup Retention | 7일 |
| Deletion Protection | 활성화 |

RDS Multi-AZ는 데이터베이스 인스턴스 장애 시 자동 장애 조치를 통해 가용성을 높이기 위한 구성입니다.

장애 조치 과정에서 일시적인 연결 오류가 발생할 수 있으므로, 애플리케이션의 재연결 동작과 실제 복구 시간은 추가 검증할 예정입니다.

### ECS 설계 방향

> ECS는 현재 설계 단계이며, 실제 구축 및 동작 검증은 진행 예정입니다.

| 항목 | 설계 방향 |
| --- | --- |
| 실행 방식 | ECS on EC2 |
| EC2 Instance Type | `t3.small` |
| 운영 EC2 수 | 2대 |
| 가용 영역 | ap-northeast-2a, ap-northeast-2c |
| Backend Service | REPLICA |
| Desired Task Count | 2 |
| Placement Constraint | `distinctInstance` |
| Placement Strategy | AZ Spread |
| Network Mode | `bridge` |
| Container Port | 8080 |
| Host Port | 8080 |
| ALB Target Type | `instance` |
| 모니터링 | cAdvisor, node-exporter DAEMON Service |

Backend Task를 서로 다른 EC2에 배치하도록 설계했습니다.

EC2당 Backend Task 하나를 실행하는 구조이므로 `bridge` 네트워크 모드와 고정 포트 매핑을 사용할 계획입니다.

다만 AZ Spread는 배치 선호 전략이므로, 장애 상황에서도 AZ별 Task 하나가 항상 유지되는 것은 아닙니다.

실제 구축 후 다음 항목을 검증할 예정입니다.

- Backend 및 모니터링 Task의 CPU·메모리 사용량
- ALB와 Backend 간 요청 전달 및 헬스 체크
- EC2 장애 시 Task 재배치
- AZ별 Task 분산 동작
- 호스트 및 컨테이너 메트릭 수집

### 배포 전략 검토

현재 ECS 배포 전략으로 Rolling과 Blue/Green을 비교 검토하고 있습니다.

| 항목 | Rolling | Blue/Green |
| --- | --- | --- |
| 배포 방식 | 기존 Task를 신규 Task로 교체 | 기존 버전과 신규 버전을 동시에 유지 |
| 사전 검증 | Staging 중심 | Staging 및 운영 트래픽 전환 전 검증 가능 |
| 롤백 | 이전 버전 Task 재실행이 필요할 수 있음 | Blue 유지 중 빠른 트래픽 복귀 가능 |
| 운영 복잡도 | 상대적으로 낮음 | 상대적으로 높음 |
| 추가 용량 | 배포 설정에 따라 필요 | 신구 버전 동시 실행 용량 필요 |

현재 검토 중인 운영 조건:

- 평상시 EC2 2대 운영
- 배포 중 필요 시 최대 4대까지 확장
- 배포 완료 후 EC2 2대로 축소
- Staging 환경에서 주요 API 사전 검증
- Blue/Green 적용 시 기존 버전을 약 30분간 유지하는 방안 검토

추가 검토 사항:

- 배포 실패 감지 기준
- 실제 롤백 소요 시간
- 배포 후 안전한 EC2 축소 절차
- DB 스키마 변경 시 이전 버전과의 호환성
- 배포 중 추가 인스턴스 운영 비용

> 배포 전략은 아직 확정되지 않았으며, 복구 목표와 운영 복잡도, 비용을 기준으로 결정할 예정입니다.

## 6. 데이터 이전 계획

기존 V1 MySQL에서 V2 RDS MySQL로 데이터를 이전하기 위해 AWS DMS를 검토하고 있습니다.

```text
V1 MySQL
   │
   ├── Full Load
   │
   └── CDC
        │
        ▼
V2 RDS MySQL
```

- **Full Load:** 기존 데이터를 V2 RDS로 초기 이전
- **CDC:** 초기 이전 이후 발생하는 데이터 변경 사항을 지속적으로 반영

### 검증 예정 항목

- V1과 V2 데이터 정합성
- CDC 복제 지연
- 최종 전환 시 쓰기 중단 및 동기화 절차
- 데이터 이전 실패 시 대응 방안
- 서비스 트래픽 전환 및 롤백 절차

## 7. 시작하기

### 사전 준비

- Terraform `1.16.x`
- AWS CLI 및 SSO 프로필
- HCP Terraform 로그인 (`terraform login`)
- Session Manager 플러그인 (RDS 접속 시)

### 변수 파일

`prod/terraform.tfvars`에는 계정 ID와 DB 비밀번호 등 민감한 설정이 포함될 수 있으므로 **Git에 커밋하지 않습니다.**

저장소를 처음 받으면 환경에 맞게 직접 생성해야 합니다.

```hcl
allowed_account_ids = ["<AWS_ACCOUNT_ID>"]

cidr                = "10.10.0.0/16"
public_subnets      = ["10.10.0.0/24", "10.10.1.0/24"]
private_app_subnets = ["10.10.10.0/24", "10.10.20.0/24"]
private_db_subnets  = ["10.10.40.0/24", "10.10.50.0/24"]

github_backend_subjects  = ["<GITHUB_OIDC_SUBJECT>"]
github_frontend_subjects = ["<GITHUB_OIDC_SUBJECT>"]

frontend_bucket_name                = "<S3_BUCKET_NAME>"
frontend_cloudfront_distribution_id = "<CLOUDFRONT_DISTRIBUTION_ID>"

db_master_password = "<RDS_MASTER_PASSWORD>"
```

### 실행

```bash
aws sso login --profile <PROFILE>
export AWS_PROFILE=<PROFILE>

cd prod

terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

## 8. 배포 원칙

- Terraform 코드는 기능 단위로 작성하고 브랜치 및 PR을 통해 `main`에 반영합니다.
- `terraform fmt`, `validate`, `plan`을 확인한 뒤 AWS 적용 여부를 결정합니다.
- GitHub에 코드를 커밋하는 것과 `terraform apply`는 별개입니다.
- 운영 환경의 `apply`는 최신 `main`을 기준으로 실행합니다.
- 오래된 코드로 적용하면 기존 변경 사항이 되돌려지거나 리소스 교체·삭제가 발생할 수 있으므로 주의합니다.
- `plan`에서 `must be replaced` 또는 `# forces replacement`가 표시되면 원인을 확인한 뒤 진행합니다.
- `apply` 이후 `plan`을 다시 실행하여 의도하지 않은 변경 사항이 남아 있지 않은지 확인합니다.

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

Provider 및 모듈을 초기화합니다.

### 3. 코드 포맷 확인 및 정리

```bash
terraform fmt -recursive
```

Terraform 코드의 형식을 정리합니다.

### 4. 코드 유효성 검사

```bash
terraform validate
```

Terraform 설정의 기본적인 유효성을 검사합니다.

### 5. 변경 사항 확인

```bash
terraform plan
```

AWS에 적용될 리소스 생성·변경·삭제 계획을 확인합니다.

### 6. 배포 계획 저장

```bash
terraform plan -out=tfplan
```

검토한 배포 계획을 파일로 저장합니다.

> `tfplan`에는 민감정보가 포함될 수 있으므로 Git에 커밋하지 않습니다.

### 7. AWS에 실제 적용

```bash
terraform apply tfplan
```

저장한 배포 계획을 AWS에 적용합니다.

> **주의:** `terraform apply`는 실제 AWS 리소스를 생성·변경·삭제하며 비용이 발생할 수 있습니다. 반드시 Plan을 검토한 뒤 실행합니다.

### 8. 적용된 리소스 확인

```bash
terraform state list
```

Terraform State에서 관리 중인 리소스를 확인합니다.

</details>

## 9. 향후 작업

| 순서 | 작업 | 주요 검증 항목 |
| --- | --- | --- |
| 1 | NAT Instance 통신 검증 | Private App Subnet에서 외부 통신 확인 |
| 2 | ECS 및 ALB 구축 | Backend Task 배치 및 요청 전달 |
| 3 | 모니터링 구성 | 호스트 및 컨테이너 메트릭 수집 |
| 4 | 배포 전략 구현 | 서비스 중단 최소화 및 롤백 |
| 5 | 장애 대응 테스트 | EC2 장애, Task 재배치, 복구 시간 |
| 6 | DMS 데이터 이전 | 데이터 정합성 및 CDC 지연 |
| 7 | V2 서비스 전환 | 트래픽 전환 및 장애 대응 |

## 10. 문서

| 문서 | 내용 |
| --- | --- |
| [docs/infra-status.md](docs/infra-status.md) | 인프라 구축 현황 |
| [docs/iam.md](docs/iam.md) | IAM Role 및 정책 설계 |
| [docs/rds.md](docs/rds.md) | RDS 설계, V1 비교, 접속 방법 |
| [docs/ecs.md](docs/ecs.md) | ECS 설계 |

> 문서 링크는 해당 파일이 저장소에 함께 커밋된 이후 정상적으로 동작합니다.
