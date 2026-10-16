# KGB 인프라 구현 현황

2026-10-16 기준.

네트워크, 보안 그룹, IAM, NAT Instance, RDS, ECS(Cluster, EC2, Backend Service)까지 코드 작성, 커밋, AWS 반영이 완료된 상태다.
Backend Task는 기본 0개로 두고 시험 기동할 때만 올린다. DMS는 테스트 마이그레이션(2026-10-15)만 진행했다.

## 개요

| 항목                    | 내용                                                                      |
|-----------------------|-------------------------------------------------------------------------|
| 프로젝트                  | KGB (KGuideBook) AWS 인프라                                                |
| 환경                    | `prod`                                                                  |
| 리전                    | `ap-northeast-2` (서울)                                                   |
| IaC                   | Terraform                                                               |
| 완료 범위                 | VPC, Security Group, IAM, NAT Instance, RDS MySQL, ECS, Backend Service |
| Terraform state 리소스 수 | 95개 (data source 제외)                                                    |
| 현재 발생 비용              | NAT Instance 2대, EIP 2개, RDS Multi-AZ, ECS Host 2대, Secrets Manager 1개  |
| Terraform 외부 리소스      | DMS, V1↔V2 VPC 피어링 및 관련 라우트·SG 규칙 (마이그레이션 담당자 구성)                       |

## 구현 단계

| 단계 | 모듈         | 구현 범위                                                         | 상태                  |
|----|------------|---------------------------------------------------------------|---------------------|
| 1  | `network`  | VPC, Subnet 6개, IGW, Route Table                              | 완료                  |
| 2  | `security` | Security Group 5개 및 규칙                                        | 완료                  |
| 3  | `iam`      | ECS·Task·Monitoring·NAT Role, GitHub OIDC 배포 Role, 개발자 정책     | 완료                  |
| 4  | `nat`      | NAT Instance 2대, EIP, private-app NAT 경로                      | 완료                  |
| 5  | `rds`      | RDS MySQL (Multi-AZ), DB Subnet Group, Parameter Group, 로그 그룹 | 완료                  |
| 6  | `ecs`      | ECS Cluster, Launch Template, ASG, Capacity Provider          | 완료                  |
| 7  | `backend`  | Task Definition, Service, Log Group, 비밀 값 저장소                 | 완료 (Task 0개)        |
| 8  | -          | ACM 인증서, ALB, Target Group                                    | 예정 (컷오버 전 apply)    |
| 9  | -          | Monitoring EC2, cAdvisor·node-exporter Daemon                 | 예정                  |
| 10 | -          | S3, CloudFront                                                | V1 리소스 재사용 예정       |
| 11 | -          | V1 → V2 데이터 마이그레이션 (DMS)                                      | 테스트 완료, 실제 이전 예정 (Terraform 외부) |

## AWS에 만들어진 리소스 (95개)

| 모듈         | 개수 | 주요 리소스                                                                    |
|------------|----|---------------------------------------------------------------------------|
| `network`  | 19 | VPC, IGW, Subnet 6, Route Table 4, Route 1, Association 6                 |
| `security` | 27 | Security Group 5, 인바운드·아웃바운드 규칙 22                                        |
| `iam`      | 21 | Role 7, Instance Profile 3, 정책 연결·인라인 정책 10, 개발자 포트 포워딩 정책 1              |
| `nat`      | 8  | NAT Instance 2, EIP 2, EIP Association 2, private-app Route 2             |
| `rds`      | 4  | DB Subnet Group, Parameter Group, DB Instance, error 로그 그룹                |
| `ecs`      | 5  | Cluster, Launch Template, ASG, Capacity Provider, Cluster-CP 연결           |
| `backend`  | 11 | Secrets Manager 1, Parameter Store 7, Log Group, Task Definition, Service |

### Subnet

| 이름                            | CIDR            | AZ                | Route Table                 |
|-------------------------------|-----------------|-------------------|-----------------------------|
| `kgb-prod-public-snet-a`      | `10.10.0.0/24`  | `ap-northeast-2a` | `kgb-prod-public-rt`        |
| `kgb-prod-public-snet-c`      | `10.10.1.0/24`  | `ap-northeast-2c` | `kgb-prod-public-rt`        |
| `kgb-prod-private-app-snet-a` | `10.10.10.0/24` | `ap-northeast-2a` | `kgb-prod-private-app-rt-a` |
| `kgb-prod-private-app-snet-c` | `10.10.20.0/24` | `ap-northeast-2c` | `kgb-prod-private-app-rt-c` |
| `kgb-prod-private-db-snet-a`  | `10.10.40.0/24` | `ap-northeast-2a` | `kgb-prod-private-db-rt`    |
| `kgb-prod-private-db-snet-c`  | `10.10.50.0/24` | `ap-northeast-2c` | `kgb-prod-private-db-rt`    |

### Route Table

| 이름                          | 연결된 Subnet                 | 경로                                                 |
|-----------------------------|----------------------------|----------------------------------------------------|
| `kgb-prod-public-rt`        | public-a, public-c         | VPC 내부 + `0.0.0.0/0` → IGW                         |
| `kgb-prod-private-app-rt-a` | private-app-a              | VPC 내부 + `0.0.0.0/0` → NAT Instance A              |
| `kgb-prod-private-app-rt-c` | private-app-c              | VPC 내부 + `0.0.0.0/0` → NAT Instance C              |
| `kgb-prod-private-db-rt`    | private-db-a, private-db-c | VPC 내부 + `10.0.0.0/16` → V1 피어링 (**Terraform 외부**) |

### Security Group

| 이름                       | 용도                                 |
|--------------------------|------------------------------------|
| `kgb-prod-alb-sg`        | ALB (CloudFront → 443)             |
| `kgb-prod-ecs-host-sg`   | ECS Host와 Backend 컨테이너 (bridge 모드) |
| `kgb-prod-rds-sg`        | RDS                                |
| `kgb-prod-monitoring-sg` | Monitoring EC2                     |
| `kgb-prod-nat-sg`        | NAT Instance                       |

- 인터넷 방향 아웃바운드는 443만 허용한다. 80과 SSH(22)는 열지 않는다.
- awsvpc용 `kgb-prod-backend-task-sg`는 bridge 모드로 바꾸면서 삭제했다.

**ECS Host SG 주요 규칙**

| 방향    | 포트   | 상대              | 용도                          |
|-------|------|-----------------|-----------------------------|
| 인바운드  | 8080 | ALB             | Backend API                 |
| 인바운드  | 8081 | ALB, Monitoring | 헬스 체크, Actuator 메트릭         |
| 인바운드  | 9100 | Monitoring      | node-exporter               |
| 인바운드  | 8082 | Monitoring      | cAdvisor                    |
| 아웃바운드 | 3306 | RDS             | Backend → DB                |
| 아웃바운드 | 443  | `0.0.0.0/0`     | ECS Agent, 이미지 다운로드, 외부 API |

**RDS SG 인바운드 3306**

| 출발지                              | 관리               | 용도                               |
|----------------------------------|------------------|----------------------------------|
| `kgb-prod-ecs-host-sg`           | Terraform        | Backend 컨테이너                     |
| `kgb-prod-nat-sg`                | Terraform        | SSM 포트 포워딩 (사람)                  |
| DMS SG (`sg-082f04447b141b5e1`)  | **Terraform 외부** | DMS 복제                           |
| `10.0.0.210/32` (V1 Backend EC2) | **Terraform 외부** | 설명: "Temporary V1 to RDS access" |

Terraform 외부 규칙은 Terraform이 관리하지 않으므로 plan에 나타나지 않는다. 특히 V1 서버에서 RDS로 직접 접근하는 임시 규칙은 용도가 끝나면 삭제해야 한다.

### NAT Instance

| 이름               | AZ                | 타입         | AMI                                   |
|------------------|-------------------|------------|---------------------------------------|
| `kgb-prod-nat-a` | `ap-northeast-2a` | `t3.micro` | Ubuntu 26.04 amd64 (`nat_ami_id`로 고정) |
| `kgb-prod-nat-c` | `ap-northeast-2c` | `t3.micro` | Ubuntu 26.04 amd64 (`nat_ami_id`로 고정) |

- 공인 IP는 EIP로만 사용한다.
- user data에서 IP 포워딩, iptables MASQUERADE, SSM Agent를 설정한다.
- private-app의 외부 통신과 SSM 포트 포워딩(RDS 접속) 중계를 함께 담당한다.

### RDS

| 항목              | 값                                            |
|-----------------|----------------------------------------------|
| 식별자             | `kgb-prod-db`                                |
| 엔진              | MySQL 8.4.11                                 |
| 인스턴스 클래스        | `db.t3.small`                                |
| 배포              | Multi-AZ                                     |
| 스토리지            | gp3 20GiB (자동 확장 상한 50GiB), 암호화              |
| 데이터베이스          | `kgb` (DMS 테스트 마이그레이션 데이터)                   |
| 계정              | `admin`(마스터), `kgb`(Backend 앱), `dms_target` |
| Parameter Group | `kgb-prod-mysql-params` (`sql_mode` V1과 일치)  |
| 로그              | error 로그 → CloudWatch (90일)                  |

자세한 내용은 [rds.md](rds.md)를 참고한다.

### ECS

| 항목              | 값                                                      |
|-----------------|--------------------------------------------------------|
| Cluster         | `kgb-prod-cluster`                                     |
| ECS Host        | `t3.small` 2대 (2a, 2c), ASG 최소 2 / 희망 2 / 최대 4         |
| AMI             | ECS 최적화 AL2023 (SSM 파라미터로 자동 조회)                       |
| Backend Service | `kgb-prod-backend`, **Task 0개** (컷오버 시 2)              |
| Task Definition | `kgb-prod-backend:2`, bridge, 8080·8081, 메모리 1536 MiB  |
| 이미지             | `ghcr.io/100-hours-a-week/ktb4-10-be:6b98f8f-20261013` |
| 비밀 값            | Parameter Store 7개, GHCR 인증 Secrets Manager 1개         |
| 로그              | `/kgb-prod/backend` (90일)                              |

자세한 내용은 [ecs.md](ecs.md)를 참고한다.

## Terraform 설정

| 항목               | 값                                           |
|------------------|---------------------------------------------|
| Terraform CLI    | `~> 1.16.0`                                 |
| AWS Provider     | `~> 6.0` (`.terraform.lock.hcl`로 6.68.0 고정) |
| State            | HCP Terraform (로컬 실행)                       |
| HCP Organization | `KGuideBook`                                |
| HCP Workspace    | `kgb-infra-prod`                            |
| 계정 제한            | `allowed_account_ids`로 허용 계정만 지정            |

### 공통 태그 (`default_tags`)

provider에 선언되어 태그를 지원하는 모든 리소스에 자동으로 붙는다.

```hcl
default_tags {
  tags = {
    Project     = "KGB-V2"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
```

- 리소스별 `Name` 태그는 모듈 안에서 `${var.name}-...` 형태로 따로 단다.
- ASG가 만드는 EC2와 볼륨에는 `default_tags`가 자동으로 붙지 않아, Launch Template에서 `aws_default_tags`로 직접 지정한다.

### 입력 값 (`prod/terraform.tfvars`)

`terraform.tfvars`는 `.gitignore` 대상이라 git에 올라가지 않는다. 계정 ID, DB 마스터 비밀번호, GitHub OIDC subject 등 git에 올리면 안 되는 값만 둔다.
Backend 일반 환경 변수는 `prod/backend.tf`에서 관리한다.

## 코드 구조

```text
kgb-infra/
├── README.md
├── docs/                    # 설계 문서
├── prod/
│   ├── main.tf              # Terraform·provider 설정, 모듈 호출
│   ├── backend.tf           # Backend 일반 환경 변수 (locals)
│   ├── variables.tf         # 입력 변수
│   ├── terraform.tfvars     # 민감한 값 (git 제외)
│   └── .terraform.lock.hcl  # provider 버전 고정
└── modules/
    ├── network/             # VPC, Subnet, IGW, Route Table
    ├── security/            # Security Group 및 규칙
    ├── iam/                 # IAM Role, Policy, Instance Profile
    ├── nat/                 # NAT Instance, EIP, NAT 경로 (user_data.sh)
    ├── rds/                 # DB Subnet Group, Parameter Group, DB Instance, 로그 그룹
    ├── ecs/                 # Cluster, Launch Template, ASG, Capacity Provider (user_data.sh.tpl)
    └── backend/             # 비밀 값 저장소, Log Group, Task Definition, Service
```

## Terraform과 AWS가 다르게 표현해 생긴 차이 (해결함)

| 리소스                     | 현상                                                       | 해결                 |
|-------------------------|----------------------------------------------------------|--------------------|
| NAT Instance            | EIP 연결 후 `associate_public_ip_address`가 `true`로 읽혀 교체 표시 | `ignore_changes`   |
| ECS ASG                 | Capacity Provider 연결 시 ECS가 `AmazonECSManaged` 태그 추가     | 태그를 코드에 선언         |
| RDS error 로그 그룹         | RDS가 자동 생성, 보존 기간 무기한                                    | `import` 후 90일로 관리 |
| Backend Task Definition | AWS가 `mountPoints` 등을 빈 값으로 채워 매번 교체 표시                  | 빈 값을 코드에 명시        |

## 검증

| 검증                                | 결과                                     |
|-----------------------------------|----------------------------------------|
| `terraform fmt -check -recursive` | 통과                                     |
| `terraform validate`              | `Success! The configuration is valid.` |
| `terraform plan`                  | `No changes`                           |
| `terraform state list`            | data source 제외 95개                     |
| NAT Instance, ECS Host SSM 등록     | 4대 모두 `Online`                         |
| ECS Cluster 등록                    | ECS Host 2대 `ACTIVE`, Agent 연결         |
| private-app 외부 통신                 | 양쪽 AZ 정상 (ECS API, SSM, 이미지 다운로드)      |

## 아직 없는 것

- ACM 인증서(서울), ALB, Target Group
- Monitoring EC2, cAdvisor·node-exporter Daemon Service
- V2 Backend → AI 서버(`kgb-ai`, V1 VPC) 경로
- 개발자 포트 포워딩 정책의 사용자·그룹 연결, 개발자용 읽기 전용 DB 계정
- CloudWatch 알람
- Backend CD (V2 배포 파이프라인), 블루/그린 배포
- `staging/` 환경 디렉터리
