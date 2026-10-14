# KGB V2 — IAM 설계

## 1. 개요

KGB V2는 AWS IAM(Identity and Access Management)을 사용하여 EC2, ECS Task, GitHub Actions에 필요한 권한을 관리한다.

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

현재 작성한 Terraform 코드에는 다음 역할이 포함되어 있다.

| IAM Role                | 사용 주체            | 주요 목적                                     |
|-------------------------|------------------|-------------------------------------------|
| ECS Instance Role       | ECS Host EC2     | ECS 클러스터 등록 및 ECS Agent 동작                |
| ECS Task Execution Role | ECS 실행 환경        | GHCR 인증 정보 조회 및 컨테이너 실행 지원                |
| ECS Task Role           | Spring Boot 컨테이너 | 애플리케이션의 AWS API 접근                        |
| Monitoring Role         | Monitoring EC2   | 모니터링 대상 탐색을 위한 AWS API 조회                 |
| GitHub Deploy Role      | GitHub Actions   | ECS Task Definition 등록 및 ECS Service 업데이트 |

추가로 프론트엔드 CD의 OIDC 전환을 위해 **Frontend Deploy Role을 별도로 구성할 예정**이다.

### 3.1 ECS Instance Role

**역할:** ECS Host EC2가 ECS 클러스터에 등록하고 ECS Agent를 실행할 수 있도록 한다.

**Trust Policy**

```text
ec2.amazonaws.com
```

**Permission Policy**

AWS 관리형 정책을 사용한다.

```text
AmazonEC2ContainerServiceforEC2Role
```

**Instance Profile**

```text
kgb-ecs-instance-profile
```

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

| 권한                                 | 목적                                       |
|------------------------------------|------------------------------------------|
| `secretsmanager:GetSecretValue`    | GHCR 인증 정보 조회                            |
| `AmazonECSTaskExecutionRolePolicy` | ECS 실행 및 CloudWatch Logs 전송 등에 필요한 기본 권한 |

**주의:** 현재 작성한 코드에는 `AmazonECSTaskExecutionRolePolicy` 연결이 누락되어 있어 추가가 필요하다.

GHCR 인증 정보는 ECS Task Definition의 `repositoryCredentials`를 통해 참조할 예정이다.

### 3.3 ECS Task Role

**역할:** 실행 중인 Spring Boot 애플리케이션이 AWS API를 호출할 때 사용한다.

**Trust Policy**

```text
ecs-tasks.amazonaws.com
```

현재는 Spring Boot가 직접 호출해야 하는 AWS API가 확정되지 않았으므로 별도의 Permission Policy를 부여하지 않는다.

향후 S3, SQS 등 AWS 서비스에 직접 접근해야 하는 요구사항이 발생하면 필요한 권한만 추가한다.

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
kgb-monitoring-profile
```

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

현재 Frontend CD의 AWS Access Key 방식을 GitHub OIDC 방식으로 전환할 예정

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

| IAM Role                       | Instance Profile                 | 대상             |
|--------------------------------|----------------------------------|----------------|
| `kgb-prod-ecs-instance-role`   | `kgb-prod-ecs-instance-profile`  | ECS Host EC2   |
| `kgb-prod-monitoring-role`     | `kgb-prod-monitoring-profile`    | Monitoring EC2 |
| `kgb-prod-nat-role`            | `kgb-prod-nat-profile`           | NAT Instance   |

SSM Agent는 SSM 엔드포인트와 HTTPS(443)로 통신한다. 각 Security Group은 아웃바운드 443을 허용한다.

NAT Instance 2대는 SSM에 `Online`으로 등록된 것을 확인했다. ECS Host와 Monitoring EC2는 아직 만들지 않았다.

### 6.2 개발자 포트 포워딩 정책

개발자가 RDS를 조회할 수 있도록 `kgb-prod-developer-port-forward-policy`를 만든다.

| 허용 범위        | 내용                                               |
|--------------|--------------------------------------------------|
| 세션 대상        | NAT Instance만                                    |
| SSM Document | `AWS-StartPortForwardingSessionToRemoteHost`만    |
| 세션 관리        | 본인이 시작한 세션만 종료·재개 가능                             |

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
terraform/
├── modules/
│   ├── network/
│   ├── security/
│   └── iam/
│       ├── main.tf
│       ├── ecs.tf
│       ├── github.tf
│       ├── monitoring.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── envs/
    └── prod/
        └── main.tf
```

위 파일 구조는 권장안이며, 현재 코드가 실제로 이 파일들에 분리되어 있다는 의미는 아니다.

Terraform은 같은 모듈 디렉터리의 `.tf` 파일들을 하나의 모듈로 처리한다.

따라서 역할별로 파일을 분리하더라도 별도 Terraform 모듈을 생성할 필요는 없다.

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

| 검증 대상               | 검증 방법                                  | 성공 기준                            |
|---------------------|----------------------------------------|----------------------------------|
| Terraform IAM       | `terraform validate`, `terraform plan` | 문법 오류 및 의도하지 않은 권한 변경 없음         |
| ECS Instance Role   | ECS Host 클러스터 등록 확인                    | EC2가 ECS Container Instance로 등록됨 |
| Task Execution Role | 비공개 GHCR 이미지로 Task 실행                  | 이미지 인증 및 다운로드 성공                 |
| CloudWatch Logs     | Backend Task 실행 후 로그 확인                | 지정된 로그 그룹에 로그 기록                 |
| Backend OIDC        | GitHub Actions 배포 실행                   | 허용된 워크플로에서 ECS 배포 성공             |
| Frontend OIDC       | GitHub Actions 배포 실행                   | S3 업로드 및 CloudFront 무효화 성공       |
| OIDC 접근 제한          | 허용되지 않은 브랜치에서 역할 사용 시도                 | 역할 수임 거부                         |
| 기존 Access Key 제거    | 키 사용처 확인 및 비활성화                        | 기존 배포 파이프라인 정상 동작                |

---

## 10. 현재 설계 상태

**판정: REVISION REQUIRED**

IAM의 역할 분리 방향은 타당하지만, 실제 적용 전에 다음 항목을 수정하거나 확인해야 한다.

| 우선순위 | 항목                                      | 상태    |
|------|-----------------------------------------|-------|
| P0   | ECS Task Execution Role 기본 관리형 정책 연결    | 수정 필요 |
| P0   | GitHub OIDC Trust Policy의 저장소·브랜치 제한 확인 | 검증 필요 |
| P0   | GitHub Deploy Role의 ECS 리소스 ARN 확인      | 검증 필요 |
| P1   | Frontend Deploy Role 추가                 | 구현 예정 |
| P1   | Prometheus 서비스 디스커버리 방식 확정              | 미확정   |
| P2   | SSM 전환에 필요한 IAM 권한                      | 향후 작업 |
