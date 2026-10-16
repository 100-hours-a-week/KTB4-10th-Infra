# KGB V2 — IAM 설계

## 1. 개요

AWS IAM(Identity and Access Management)을 사용하여 EC2, ECS Task, GitHub Actions에 필요한 권한을 관리한다.

IAM 설계 목적

- AWS 리소스별 역할과 권한 분리
- 최소 권한 원칙 적용
- GitHub Actions의 장기 AWS Access Key 제거
- OIDC 기반 임시 자격 증명을 통한 배포
- Terraform을 통한 IAM 리소스 관리

IAM은 AWS API 접근 권한을 제어한다.

## 2. IAM 기본 개념

### 2.1 IAM Role

IAM Role은 AWS 서비스나 외부 시스템이 임시 자격 증명을 사용하여 AWS 리소스에 접근할 수 있도록 하는 IAM 자격 증명 주체이다.

KGB V2에서는 EC2, ECS Task, GitHub Actions가 각각 필요한 역할을 사용한다.

### 2.2 Trust Policy

Trust Policy는 **누가 해당 IAM Role을 사용할 수 있는지** 정의한다.

| Principal                 | 용도             |
|---------------------------|----------------|
| `ec2.amazonaws.com`       | EC2 인스턴스       |
| `ecs-tasks.amazonaws.com` | ECS Task       |
| GitHub OIDC Provider      | GitHub Actions |

### 2.3 Permission Policy

Permission Policy는 **해당 IAM Role이 어떤 AWS API를 호출할 수 있는지** 정의한다.

예를 들어 다음과 같은 권한을 부여한다.

- `secretsmanager:GetSecretValue`
- `ecs:UpdateService`
- `s3:PutObject`
- `cloudfront:CreateInvalidation`

Trust Policy와 Permission Policy는 별도로 관리한다.

### 2.4 Instance Profile

EC2 인스턴스에 IAM Role을 연결하기 위해 Instance Profile을 사용한다.

```text
EC2 Instance
    │
    ▼
IAM Instance Profile
    │
    ▼
IAM Role
    │
    ▼
Permission Policy
```

ECS Task는 EC2 Instance Profile이 아니라 ECS Task Definition에 지정한 역할을 사용한다.

---

## 3. IAM 구성

2026-10-16 기준으로 다음 역할이 배포되어 있다.

| IAM Role                        | 사용 주체            | 주요 목적                                     |
|---------------------------------|------------------|-------------------------------------------|
| `kgb-prod-ecs-instance-role`    | ECS Host EC2     | ECS 클러스터 등록, ECS Agent 동작, SSM 접속         |
| `kgb-prod-task-execution-role`  | ECS 실행 환경        | GHCR 인증 정보·비밀 값 조회, 로그 전송                 |
| `kgb-prod-task-role`            | Spring Boot 컨테이너 | S3 `kgb-s3-storage` 파일 저장                 |
| `kgb-prod-monitoring-role`      | Monitoring EC2   | 모니터링 대상 탐색, SSM 접속 (EC2는 아직 없음)           |
| `kgb-prod-nat-role`             | NAT Instance     | SSM 접속 (포트 포워딩 중계)                        |
| `kgb-prod-backend-deploy-role`  | GitHub Actions   | ECS Task Definition 등록 및 ECS Service 업데이트 |
| `kgb-prod-frontend-deploy-role` | GitHub Actions   | S3 업로드, CloudFront 캐시 무효화                 |

개발자용 SSM 포트 포워딩 정책(`kgb-prod-developer-port-forward-policy`)도 함께 관리한다(6장).

### 3.1 ECS Instance Role

**역할:** ECS Host EC2가 ECS 클러스터에 등록하고 ECS Agent를 실행할 수 있도록 한다.

**Trust Policy**

```text
ec2.amazonaws.com
```

**Permission Policy**

AWS 관리형 정책을 사용한다.

```text
AmazonEC2ContainerServiceforEC2Role   # ECS 등록, Agent 동작
AmazonSSMManagedInstanceCore          # SSM Session Manager
```

**Instance Profile**

```text
kgb-prod-ecs-instance-profile
```

Launch Template의 IMDS hop limit을 1로 설정해, bridge 모드 컨테이너는 이 Role의 자격 증명을 가져갈 수 없다. 컨테이너의 AWS 권한은 Task Role로만 부여한다.

ECS Host EC2의 Launch Template에 해당 Instance Profile을 연결한다.

### 3.2 ECS Task Execution Role

**역할:** ECS가 Backend Task를 실행하기 위해 필요한 작업을 수행한다.

KGB V2는 GHCR의 비공개 Docker 이미지를 사용하므로, ECS가 Secrets Manager에 저장된 GHCR 인증 정보를 조회할 수 있어야 한다.

**Trust Policy**

```text
ecs-tasks.amazonaws.com
```

추가로 동일 AWS 계정에서 시작된 ECS Task만 역할을 사용할 수 있도록 `aws:SourceAccount` 조건을 설정한다.

**Permission Policy**

| 권한                                 | 대상                     | 목적                                       |
|------------------------------------|------------------------|------------------------------------------|
| `AmazonECSTaskExecutionRolePolicy` | -                      | ECS 실행 및 CloudWatch Logs 전송 등에 필요한 기본 권한 |
| `secretsmanager:GetSecretValue`    | `secret:kgb-prod/*`    | GHCR 인증 정보(`kgb-prod/ghcr`) 조회           |
| `ssm:GetParameters`                | `parameter/kgb-prod/*` | Backend 비밀 환경 변수 7개 조회                   |

- GHCR 인증 정보는 Task Definition의 `repositoryCredentials`로 참조한다. ECS 비공개 레지스트리 인증은 Secrets Manager만 지원한다.
- Backend 비밀 값(`DB_PASSWORD`, 카카오 키 등)은 Parameter Store SecureString에 두고 Task Definition의 `secrets`로 주입한다. 기본 KMS 키(
  `aws/ssm`)로 암호화된다.

### 3.3 ECS Task Role

**역할:** 실행 중인 Spring Boot 애플리케이션이 AWS API를 호출할 때 사용한다.

**Trust Policy**

```text
ecs-tasks.amazonaws.com
```

**Permission Policy** (`kgb-prod-task-policy`)

| 권한                                                | 대상                 |
|---------------------------------------------------|--------------------|
| `s3:ListBucket`                                   | `kgb-s3-storage`   |
| `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` | `kgb-s3-storage/*` |

V1 Backend는 EC2 Role(`kgb-be-ec2-role`)의 `s3access` 정책으로 같은 버킷에 접근했다. V2는 컨테이너가 EC2 Role을 쓸 수 없으므로 같은 범위의 권한을 Task Role에
부여했다.

V1과 V2가 같은 버킷을 쓰므로, 컷오버 전 V2 Backend가 버킷의 파일을 쓰거나 지우지 않도록 주의한다.

다른 AWS 서비스에 직접 접근해야 하는 요구사항이 생기면 필요한 권한만 추가한다.

**Task Execution Role과 Task Role의 차이**

| 구분    | Task Execution Role | Task Role           |
|-------|---------------------|---------------------|
| 사용 주체 | ECS 실행 환경           | 실행 중인 애플리케이션        |
| 사용 시점 | 컨테이너 실행 준비 및 로그 전송  | 애플리케이션 실행 중         |
| 예시    | GHCR 인증 정보 조회       | Spring Boot의 S3 업로드 |

### 3.4 Monitoring Role

**역할:** Monitoring EC2가 AWS API를 사용해 Prometheus 수집 대상을 탐색할 수 있도록 한다.

현재 Terraform 코드에는 다음 읽기 권한이 정의되어 있다.

```text
ec2:DescribeAvailabilityZones
ec2:DescribeInstances

ecs:DescribeClusters
ecs:DescribeContainerInstances
ecs:DescribeServices
ecs:DescribeTaskDefinition
ecs:DescribeTasks

ecs:ListClusters
ecs:ListServices
ecs:ListTasks
```

**Instance Profile**

```text
kgb-prod-monitoring-profile
```

`AmazonSSMManagedInstanceCore`도 연결되어 있다. Monitoring EC2는 아직 만들지 않았다.

**미확정 사항**

Prometheus의 메트릭 수집 대상을 ECS API로 자동 탐색할지 아직 결정되지 않았다.

따라서 해당 IAM 권한의 필요성은 Prometheus 서비스 디스커버리 방식을 확정한 뒤 재검토한다.

### 3.5 GitHub Deploy Role — Backend

**역할:** GitHub Actions가 AWS ECS에 Backend를 배포할 수 있도록 한다.
OIDC 기반 임시 자격 증명을 사용한다.

**Trust Policy**

```text
GitHub Actions
    │
    ▼
GitHub OIDC Token
    │
    ▼
AWS STS
    │
    ▼
GitHub Deploy Role
```

다음 조건을 검증한다.

- `aud`: `sts.amazonaws.com`
- `sub`: 허용된 GitHub 저장소 및 브랜치

**Permission Policy**

| 권한                           | 목적                   |
|------------------------------|----------------------|
| `ecs:RegisterTaskDefinition` | 새 Task Definition 등록 |
| `ecs:DescribeTaskDefinition` | Task Definition 조회   |
| `ecs:DescribeServices`       | ECS Service 상태 조회    |
| `ecs:UpdateService`          | ECS Service 배포       |
| `iam:PassRole`               | 지정된 ECS Task 역할 전달   |

`iam:PassRole`은 ECS Task Execution Role과 Task Role에만 허용한다.

**검증 필요 사항**

- 실제 ECS Service ARN과 IAM 정책의 리소스 패턴 일치 여부
- Task Definition 관련 리소스 범위
- GitHub OIDC `sub` 조건의 저장소 및 브랜치 범위
- 실제 CD 워크플로에 필요한 추가 권한 여부

---

## 4. GitHub OIDC 구성

GitHub Actions의 AWS 인증에는 OIDC를 사용한다.

OIDC를 사용하면 AWS Access Key를 GitHub Secrets에 장기간 저장하지 않아도 된다.

### 4.1 OIDC Provider

```text
https://token.actions.githubusercontent.com
```

Client ID:

```text
sts.amazonaws.com
```

GitHub OIDC Provider는 AWS 계정에서 공유할 수 있으므로 Backend와 Frontend 배포 역할이 동일한 Provider를 사용한다.

기존 Provider가 있는 경우 중복 생성하지 않도록 Terraform에서 생성 여부를 관리한다.

### 4.2 Backend 배포 흐름

```text
GitHub Actions
    │
    ├── Docker 이미지 빌드
    │
    ├── GHCR Push
    │
    ▼
GitHub OIDC 인증
    │
    ▼
AWS STS
    │
    ▼
Backend Deploy Role
    │
    ├── Task Definition 등록
    │
    └── ECS Service 업데이트
```

GHCR에 이미지를 업로드하는 권한과 AWS ECS에 배포하는 IAM 권한은 별개이다.

---

## 5. Frontend Deploy Role

Frontend CD를 AWS Access Key 방식에서 GitHub OIDC 방식으로 전환하기 위한 역할이다. Role(`kgb-prod-frontend-deploy-role`)은 배포되어 있으며, 실제 CD
워크플로 전환 여부는 확인하지 않았다.

### 5.1 배포 흐름

```text
GitHub Actions
    │
    ├── npm ci
    │
    ├── npm run build
    │
    ▼
GitHub OIDC 인증
    │
    ▼
AWS STS
    │
    ▼
Frontend Deploy Role
    │
    ├── S3 정적 파일 업로드
    │
    ├── CloudFront 캐시 무효화
    │
    └── 배포 버전 검증
```

### 5.2 IAM 권한

현재 Frontend CD 워크플로를 기준으로 다음 권한이 필요하다.

| IAM Action                      | 목적                | 대상               |
|---------------------------------|-------------------|------------------|
| `s3:ListBucket`                 | 버킷 객체 목록 조회       | `kgb-frontend`   |
| `s3:PutObject`                  | 정적 파일 업로드         | `kgb-frontend/*` |
| `s3:DeleteObject`               | 불필요한 파일 삭제        | `kgb-frontend/*` |
| `cloudfront:CreateInvalidation` | CloudFront 캐시 무효화 | 지정된 Distribution |
| `cloudfront:GetInvalidation`    | 캐시 무효화 완료 여부 조회   | 지정된 Distribution |

프론트엔드 배포용 역할은 Backend ECS 배포 역할과 분리한다.

### 5.3 OIDC 전환 순서

1. Terraform으로 GitHub OIDC Provider 및 Frontend Deploy Role 생성
2. `terraform plan` 검토 후 `terraform apply`
3. GitHub Actions 인증 방식을 OIDC로 변경
4. S3 업로드 및 CloudFront 캐시 무효화 확인
5. 배포 버전 검증
6. 기존 Access Key의 다른 사용처 확인
7. 기존 Access Key 비활성화 및 삭제

기존 CD가 정상적으로 동작하는 상태에서 IAM을 먼저 생성하고, 이후 인증 방식을 변경한다.

---

## 6. SSM 운영 접근

KGB V2는 Bastion과 SSH(22)를 사용하지 않고 AWS Systems Manager Session Manager로 접근한다.

```text
운영자
    │
    │ SSM Session Manager (HTTPS)
    ▼
EC2 (SSM Agent)
    ├── NAT Instance ── 포트 포워딩 ──▶ RDS (3306), Monitoring (3000)
    ├── ECS Host
    └── Monitoring EC2
```

SSH 키를 관리하거나 22번 포트를 열 필요가 없고, 접속 기록이 남는다.

### 6.1 EC2 쪽 권한

다음 Role에 AWS 관리형 정책 `AmazonSSMManagedInstanceCore`를 연결한다.

| IAM Role                     | Instance Profile                | 대상             |
|------------------------------|---------------------------------|----------------|
| `kgb-prod-ecs-instance-role` | `kgb-prod-ecs-instance-profile` | ECS Host EC2   |
| `kgb-prod-monitoring-role`   | `kgb-prod-monitoring-profile`   | Monitoring EC2 |
| `kgb-prod-nat-role`          | `kgb-prod-nat-profile`          | NAT Instance   |

SSM Agent는 SSM 엔드포인트와 HTTPS(443)로 통신한다. 각 Security Group은 아웃바운드 443을 허용한다.

NAT Instance 2대와 ECS Host 2대는 SSM에 `Online`으로 등록된 것을 확인했다. Monitoring EC2는 아직 만들지 않았다.

### 6.2 개발자 포트 포워딩 정책

개발자가 RDS를 조회할 수 있도록 `kgb-prod-developer-port-forward-policy`를 만든다.

| 허용 범위        | 내용                                            |
|--------------|-----------------------------------------------|
| 세션 대상        | NAT Instance만                                 |
| SSM Document | `AWS-StartPortForwardingSessionToRemoteHost`만 |
| 세션 관리        | 본인이 시작한 세션만 종료·재개 가능                          |

`ssm:SessionDocumentAccessCheck` 조건으로 지정한 Document 외의 세션은 이 정책으로 허용하지 않는다.

**주의:** 이 정책은 Allow만 정의한다. 다른 정책에서 `ssm:StartSession`을 넓게 허용하고 있다면 셸 세션을 막지 못한다. 필요해지면 명시적 Deny를 추가한다.

정책은 만들었지만 아직 사용자나 그룹에 연결하지 않았다.

### 6.3 RDS 접속 예시

```bash
aws ssm start-session \
  --target <NAT Instance ID> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<RDS 엔드포인트>"],"portNumber":["3306"],"localPortNumber":["3306"]}'
```

로컬 `127.0.0.1:3306`으로 MySQL 클라이언트를 연결한다.

---

## 7. Terraform 코드 구조

IAM은 Security Group과 책임이 다르므로 별도 모듈로 관리한다.

```text
modules/iam/
├── main.tf        # 신뢰 정책, ECS Host / Task / Monitoring / NAT / GitHub 배포 Role, 개발자 정책
├── variables.tf
└── outputs.tf     # Instance Profile 이름, Role ARN 등 (ecs, nat, backend 모듈에서 사용)
```

모든 역할을 `main.tf` 한 파일에 `# ---------- 구분 ----------` 주석으로 나눠 작성했다. Terraform은 같은 디렉터리의 `.tf` 파일을 하나의 모듈로 처리하므로, 파일이 길어지면
역할별로 나눠도 동작은 같다.

GitHub OIDC Provider는 계정에 이미 있어서 `data` 소스로 읽기만 한다.

---

## 8. 보안 원칙

### 8.1 최소 권한

각 역할에는 필요한 AWS API 권한만 부여한다.

예를 들어 Frontend Deploy Role에는 ECS 배포 권한을 부여하지 않는다.

### 8.2 역할 분리

다음 역할은 별도로 관리한다.

- ECS Instance Role
- ECS Task Execution Role
- ECS Task Role
- Monitoring Role
- NAT Role
- Backend Deploy Role
- Frontend Deploy Role

### 8.3 장기 자격 증명 최소화

GitHub Actions의 AWS 인증에는 OIDC를 사용한다.

기존 Access Key는 OIDC 배포 검증 이후 제거한다.

### 8.4 신뢰 정책 제한

GitHub OIDC Trust Policy는 허용된 저장소와 브랜치로 제한한다.

ECS Task Trust Policy는 동일 계정 조건을 사용하며, 필요시 `aws:SourceArn` 조건을 추가 검토한다.

---

## 9. 검증 계획

| 검증 대상               | 검증 방법                                  | 성공 기준                            | 결과                           |
|---------------------|----------------------------------------|----------------------------------|------------------------------|
| Terraform IAM       | `terraform validate`, `terraform plan` | 문법 오류 및 의도하지 않은 권한 변경 없음         | 완료                           |
| ECS Instance Role   | ECS Host 클러스터 등록 확인                    | EC2가 ECS Container Instance로 등록됨 | **완료** (2대 등록, SSM `Online`) |
| 컨테이너의 EC2 Role 차단   | bridge 컨테이너에서 IMDS 토큰 요청               | 요청 실패                            | **완료** (시간 초과)               |
| Task Execution Role | 비공개 GHCR 이미지로 Task 실행                  | 이미지 인증, 비밀 값 주입 성공               | 미검증 (Task 0개)                |
| Task Role (S3)      | Backend에서 S3 업로드                       | `kgb-s3-storage` 쓰기 성공           | 미검증                          |
| CloudWatch Logs     | Backend Task 실행 후 로그 확인                | `/kgb-prod/backend`에 로그 기록       | 미검증                          |
| Backend OIDC        | GitHub Actions 배포 실행                   | 허용된 워크플로에서 ECS 배포 성공             | 미검증                          |
| Frontend OIDC       | GitHub Actions 배포 실행                   | S3 업로드 및 CloudFront 무효화 성공       | 미확인                          |
| OIDC 접근 제한          | 허용되지 않은 브랜치에서 역할 사용 시도                 | 역할 수임 거부                         | 미검증                          |
| 기존 Access Key 제거    | 키 사용처 확인 및 비활성화                        | 기존 배포 파이프라인 정상 동작                | 미확인                          |

---

## 10. 현재 설계 상태

2026-10-16 기준. 모든 역할이 배포되어 있으며, ECS Host 쪽은 실제 동작까지 확인했다. Backend Task와 GitHub 배포 쪽은 Task를 띄우거나 CD를 실행해야 검증할 수 있다.

| 우선순위 | 항목                                         | 상태                                                                   |
|------|--------------------------------------------|----------------------------------------------------------------------|
| P0   | ECS Task Execution Role 기본 관리형 정책 연결       | 완료                                                                   |
| P0   | Task Execution Role의 Parameter Store 읽기 권한 | 완료                                                                   |
| P0   | Task Role의 S3 권한                           | 완료 (동작 미검증)                                                          |
| P0   | GitHub Deploy Role의 ECS 리소스 ARN            | 코드 확인 완료 (`service/kgb-prod-*/*`가 `kgb-prod-cluster`와 일치), 실제 배포 미검증 |
| P0   | GitHub OIDC Trust Policy의 저장소·브랜치 제한 확인    | 검증 필요                                                                |
| P1   | Frontend Deploy Role                       | 배포 완료, CD 전환 미확인                                                     |
| P1   | SSM 접근 (ECS Host, Monitoring, NAT)         | 완료                                                                   |
| P1   | 개발자 포트 포워딩 정책 사용자·그룹 연결                    | 미연결                                                                  |
| P1   | Prometheus 서비스 디스커버리 방식 확정                 | 미확정                                                                  |
