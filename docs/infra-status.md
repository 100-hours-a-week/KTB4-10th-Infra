# KGB 인프라 구현 현황

2026-10-14 기준. 네트워크, 보안 그룹, IAM, NAT Instance, RDS까지 코드 작성, 커밋, AWS 반영이 완료된 상태다.

## 개요

| 항목                    | 내용                                                |
|-----------------------|---------------------------------------------------|
| 프로젝트                  | KGB (KGuideBook) AWS 인프라                          |
| 환경                    | `prod`                                            |
| 리전                    | `ap-northeast-2` (서울)                             |
| IaC                   | Terraform                                         |
| 완료 범위                 | VPC, Security Group, IAM, NAT Instance, RDS MySQL |
| Terraform state 리소스 수 | 77개 (data source 제외)                             |
| 현재 발생 비용              | 있음 (NAT Instance 2대, EIP 2개, RDS Multi-AZ)       |

## 구현 단계

| 단계 | 모듈         | 구현 범위                                                | 상태 |
|----|------------|------------------------------------------------------|----|
| 1  | `network`  | VPC, Subnet 6개, IGW, Route Table                     | 완료 |
| 2  | `security` | Security Group 6개 및 규칙                               | 완료 |
| 3  | `iam`      | ECS·Monitoring·NAT Role, GitHub OIDC 배포 Role, 개발자 정책 | 완료 |
| 4  | `nat`      | NAT Instance 2대, EIP, private-app NAT 경로             | 완료 |
| 5  | `rds`      | RDS MySQL (Multi-AZ), DB Subnet Group, Parameter Group | 완료 |
| 6  | -          | ALB, Target Group                                    | 예정 |
| 7  | -          | ECS Cluster, EC2, ECS Service                        | 예정 |
| 8  | -          | S3, CloudFront                                       | 예정 |
| 9  | -          | V1 → V2 데이터 마이그레이션 (AWS DMS + CDC)                  | 예정 |

## AWS에 만들어진 리소스 (77개)

| 모듈         | 개수 | 주요 리소스                                                         |
|------------|----|----------------------------------------------------------------|
| `network`  | 19 | VPC, IGW, Subnet 6, Route Table 4, Route 1, Association 6      |
| `security` | 27 | Security Group 6, 인바운드·아웃바운드 규칙 21                             |
| `iam`      | 20 | Role 7, Instance Profile 3, Policy 연결·인라인 정책 9, 개발자 포트 포워딩 정책 1 |
| `nat`      | 8  | NAT Instance 2, EIP 2, EIP Association 2, private-app Route 2  |
| `rds`      | 3  | DB Subnet Group, Parameter Group, DB Instance                  |

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

| 이름                          | 연결된 Subnet                 | 경로                                   |
|-----------------------------|----------------------------|--------------------------------------|
| `kgb-prod-public-rt`        | public-a, public-c         | VPC 내부 + `0.0.0.0/0` → IGW           |
| `kgb-prod-private-app-rt-a` | private-app-a              | VPC 내부 + `0.0.0.0/0` → NAT Instance A |
| `kgb-prod-private-app-rt-c` | private-app-c              | VPC 내부 + `0.0.0.0/0` → NAT Instance C |
| `kgb-prod-private-db-rt`    | private-db-a, private-db-c | VPC 내부만                              |

private-app 서브넷은 같은 AZ의 NAT Instance를 통해 외부로 나가고, private-db 서브넷은 외부 경로가 없다.

### Security Group

| 이름                        | 용도                  |
|---------------------------|---------------------|
| `kgb-prod-alb-sg`         | ALB                 |
| `kgb-prod-backend-task-sg` | Backend ECS Task    |
| `kgb-prod-ecs-host-sg`    | ECS Host EC2        |
| `kgb-prod-rds-sg`         | RDS                 |
| `kgb-prod-monitoring-sg`  | Monitoring EC2      |
| `kgb-prod-nat-sg`         | NAT Instance        |

인터넷 방향 아웃바운드는 443만 허용한다. 80과 SSH(22)는 열지 않는다.

### NAT Instance

| 이름               | AZ                | 타입         | AMI                                |
|------------------|-------------------|------------|------------------------------------|
| `kgb-prod-nat-a` | `ap-northeast-2a` | `t3.micro` | Ubuntu 26.04 amd64 (`nat_ami_id`로 고정) |
| `kgb-prod-nat-c` | `ap-northeast-2c` | `t3.micro` | Ubuntu 26.04 amd64 (`nat_ami_id`로 고정) |

- 공인 IP는 EIP로만 사용한다.
- user data에서 IP 포워딩, iptables MASQUERADE, SSM Agent를 설정한다.
- 두 대 모두 SSM Session Manager에 `Online`으로 등록된 것을 확인했다.

### RDS

| 항목             | 값                                  |
|----------------|------------------------------------|
| 식별자            | `kgb-prod-db`                      |
| 엔진             | MySQL 8.4.11                       |
| 인스턴스 클래스       | `db.t3.small`                      |
| 배포             | Multi-AZ                           |
| 스토리지           | gp3 20GiB (자동 확장 상한 50GiB), 암호화     |
| 초기 데이터베이스      | `kgb`                              |
| Parameter Group | `kgb-prod-mysql-params` (`sql_mode` V1과 일치) |

자세한 내용은 [rds.md](rds.md)를 참고한다.

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

리소스별 `Name` 태그는 모듈 안에서 `${var.name}-...` 형태로 따로 단다.

### 입력 값 (`prod/terraform.tfvars`)

`terraform.tfvars`는 `.gitignore` 대상이라 git에 올라가지 않는다. `allowed_account_ids`와 `db_master_password`는 이 문서에 적지 않는다.

```hcl
name = "kgb-prod"
cidr = "10.10.0.0/16"
azs = ["ap-northeast-2a", "ap-northeast-2c"]

public_subnets = ["10.10.0.0/24", "10.10.1.0/24"]
private_app_subnets = ["10.10.10.0/24", "10.10.20.0/24"]
private_db_subnets = ["10.10.40.0/24", "10.10.50.0/24"]
```

## 코드 구조

```text
kgb-infra/
├── README.md
├── .gitignore
├── docs/                    # 설계 문서
├── prod/
│   ├── main.tf              # Terraform·provider 설정, 모듈 호출
│   ├── variables.tf         # 입력 변수
│   ├── terraform.tfvars     # 실제 값 (git 제외)
│   └── .terraform.lock.hcl  # provider 버전 고정
└── modules/
    ├── network/             # VPC, Subnet, IGW, Route Table
    ├── security/            # Security Group 및 규칙
    ├── iam/                 # IAM Role, Policy, Instance Profile
    ├── nat/                 # NAT Instance, EIP, NAT 경로 (user_data.sh 포함)
    └── rds/                 # DB Subnet Group, Parameter Group, DB Instance
```

## 설계 결정

| 결정                                              | 이유                                                                                               |
|-------------------------------------------------|--------------------------------------------------------------------------------------------------|
| 서브넷을 public / private-app / private-db로 분리      | Application과 Database의 네트워크 정책을 독립적으로 관리                                                         |
| public 서브넷의 공인 IP 자동 할당을 끔                      | ALB는 AWS가 공인 IP를 자동으로 붙이고, NAT Instance는 EIP를 쓴다. 켜두면 그 서브넷에 띄우는 인스턴스가 전부 공인 IP를 받아 실수로 노출될 수 있다 |
| private-app Route Table을 AZ별로 분리                | NAT Instance를 AZ마다 1대씩 두고, 각 테이블에 해당 AZ의 NAT 경로를 건다                                              |
| private-db Route Table은 1개, 외부 경로 없음            | DB 서브넷에는 인터넷으로 나가는 NAT 경로를 두지 않는다                                                                |
| NAT Gateway 대신 NAT Instance                     | 비용 절감. AZ별 1대로 한쪽 AZ 장애가 다른 AZ에 영향을 주지 않는다                                                       |
| Bastion·SSH 대신 SSM Session Manager             | SSH 키 관리와 22번 포트 개방이 필요 없고 접속 기록이 남는다. RDS는 NAT Instance를 경유한 포트 포워딩으로 접속한다                       |
| 인터넷 방향 아웃바운드는 443만 허용                           | 필요한 통신이 모두 HTTPS다. NAT Instance의 apt 저장소도 HTTPS로 바꿨다                                             |
| NAT Instance AMI ID 고정                         | 최신 AMI 조회 결과가 바뀌어 인스턴스가 의도치 않게 교체되는 것을 막는다                                                       |
| NAT Instance의 `associate_public_ip_address` 무시 | EIP를 붙이면 AWS가 `true`로 반환해 매 plan마다 교체 대상으로 잡히는 문제를 막는다                                            |
| RDS 비밀번호는 `password_wo`로 전달                     | Terraform state와 plan 출력에 비밀번호가 남지 않는다                                                            |
| RDS 사용자 정의 Parameter Group                      | RDS 기본 `sql_mode`가 V1과 달라서 V1 값으로 맞춘다                                                            |
| 공통 태그는 provider `default_tags`, `Name`만 리소스에 선언 | 같은 태그를 리소스마다 반복하지 않고, 환경별 값은 환경 디렉터리에서만 바꾼다                                                      |
| 모듈에 환경별 CIDR·이름을 하드코딩하지 않음                      | `prod`와 `staging`이 같은 모듈을 쓴다                                                                     |

## 검증

| 검증                                | 결과                                                         |
|-----------------------------------|------------------------------------------------------------|
| `terraform fmt -check -recursive` | 통과                                                         |
| `terraform validate`              | `Success! The configuration is valid.`                     |
| `terraform plan`                  | `No changes. Your infrastructure matches the configuration.` |
| `terraform state list`            | data source 제외 77개                                          |
| NAT Instance SSM 등록               | 2대 모두 `Online`                                             |

## 아직 없는 것

- ALB, Target Group
- ECS Cluster, EC2, ECS Service
- Monitoring EC2 (Security Group과 IAM Role만 있음)
- S3, CloudFront
- RDS 애플리케이션·개발자 계정 (현재 마스터 계정만 있음)
- 개발자 포트 포워딩 정책의 사용자·그룹 연결
- CloudWatch 알람
- V1 → V2 마이그레이션 리소스 (VPC 피어링, DMS)
- `staging/` 환경 디렉터리
