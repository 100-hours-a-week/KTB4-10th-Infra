# KGB V2 — AI 서버 설계

2026-10-17 기준.

V2 ECS 클러스터에 AI 전용 EC2 1대를 추가하고, Backend가 고정 IP로 AI를 호출하도록 구성한다.

> **원칙:** 기존 Backend ASG, Capacity Provider, Service를 변경하지 않고 AI 리소스를 추가한다.

## 1. 결정 사항과 근거

| 구분             | 결정 / 값                                 | 근거                   |
|----------------|----------------------------------------|----------------------|
| VPC            | V2 `10.10.0.0/16`                      | 사실                   |
| ECS            | 기존 클러스터 `kgb-prod-cluster` 재사용         | 사실                   |
| AI 서버          | 전용 EC2 1대 (`aws_instance`, `t3.small`) | 설계 결정                |
| AI 위치          | private-app-a (`10.10.10.0/24`)        | 설계 결정                |
| AI 주소          | 사설 IP 고정 `10.10.10.250`, 포트 8000       | 설계 결정                |
| AI Task 수      | 1개                                     | 작업 큐를 메모리에 둠         |
| Backend와의 관계   | 서로 다른 EC2, 서로 다른 배치 방식                 | 자원·장애·확장 분리          |
| AI 컨테이너 최대 메모리 | 134.4 MiB (2026-10-02 14:45–15:00)     | 측정                   |
| AI 컨테이너 최대 CPU | 1분 평균 최대 약 0.92% (1 core 기준)           | 측정                   |
| AI 동시 작업       | 워커 최대 3개                               | 기존 테스트 기준, 구현 재확인 필요 |
| 생성 시간          | p95 약 57.75초                           | 기존 측정                |
| 장애 허용 시간(RTO)  | 미정                                     | 미확인                  |

위 CPU·메모리는 V1 AI(가짜 LLM 모드)에서 측정한 값이다. RunPod 연동 이후에도 같다고 보장할 수 없다.

### 1.1 Backend와 분리한 이유

AI를 Backend 서버(ECS Host)에 같이 두는 방안(DAEMON)도 검토했으나, 다음 이유로 분리했다.

- Backend 메모리 사용량이 트래픽에 따라 늘어날 예정이라 AI와 자원을 다툰다.
- Backend 서버를 늘리면 AI도 같이 늘어나 따로 확장할 수 없다.
- 서버 한 대의 장애가 Backend와 AI에 함께 영향을 준다.

### 1.2 AI를 1대로 둔 이유

- AI가 작업 큐(`jobs`, `queue_size`, `running`)를 **메모리에** 들고 있다. 2대로 늘리면 각자 다른 큐를 갖게 된다.
- AI가 2대면 Backend가 둘 중 어디로 보낼지 정해야 해서 내부 ALB가 필요해진다.

### 1.3 IP를 고정한 이유

ECS의 ASG나 awsvpc Task는 교체될 때마다 IP가 바뀐다. 그래서 다음 중 하나가 필요하다.

| 방법                 | 주소                  | 판단                                    |
|--------------------|---------------------|---------------------------------------|
| **EC2 1대 + IP 고정** | `10.10.10.250:8000` | **선택.** V1 `kgb-ai`와 같은 방식, 추가 리소스 없음 |
| 내부 DNS (Cloud Map) | `ai.kgb.local:8000` | AI Task를 awsvpc로 바꿔야 함                |
| 내부 ALB             | ALB DNS             | AI 1대에 비해 비용이 큼 (월 약 $16~20)          |

AI가 1대인 동안은 IP 고정이 가장 단순하다. AI를 여러 대로 늘리거나 SQS로 바꿀 때 다시 검토한다.

## 2. 아키텍처

```text
V2 VPC 10.10.0.0/16
│
├─ private-app-a (2a)
│  ├─ ECS Host (Backend ASG) ── Backend Task :8080 ─┐
│  └─ AI 서버 10.10.10.250 ── AI Task :8000 ◀───────┤ http://10.10.10.250:8000
│                                                  │
├─ private-app-c (2c)                              │
│  └─ ECS Host (Backend ASG) ── Backend Task :8080 ─┘
│
├─ ECS Cluster kgb-prod-cluster
│  ├─ Backend: ASG → Capacity Provider → Backend Service
│  └─ AI: aws_instance (workload=ai) → AI Service (launch_type EC2)
│
└─ AI Task → NAT → HTTPS → RunPod (향후 연동)
```

- 다른 AZ의 Backend(2c)도 VPC 내부 통신으로 AI에 접근한다. NAT나 피어링은 필요 없다.
- V1 `kgb-ai`(`10.0.0.214`, V1 VPC)는 사용하지 않는다.

## 3. Terraform 리소스

| 위치                  | 리소스                           | 내용                                                                                   |
|---------------------|-------------------------------|--------------------------------------------------------------------------------------|
| `modules/ai`        | `aws_instance.ai`             | `t3.small`, IP 고정, AMI 고정, gp3 30GiB 암호화, IMDSv2 hop limit 1                         |
|                     | `aws_cloudwatch_log_group.ai` | `/kgb-prod/ai` (90일)                                                                 |
|                     | `aws_ecs_task_definition.ai`  | `kgb-prod-ai`, bridge, 8000:8000, 메모리 상한 1024 MiB, `stopTimeout` 120초                |
|                     | `aws_ecs_service.ai`          | `kgb-prod-ai`, Task 1개, `launch_type = EC2`, `workload == ai`에만 배치                   |
| `modules/security`  | `aws_security_group.ai`       | `kgb-prod-ai-sg`                                                                     |
|                     | 규칙 3개                         | ECS Host → AI 8000, AI → 외부 443, ECS Host 아웃바운드 → AI 8000                            |
| `prod/ai.tf`        | `local.ai_environment`        | AI 환경 변수                                                                             |
| `prod/backend.tf`   | `AI_SERVER_BASE_URL`          | `module.ai.base_url` (`http://10.10.10.250:8000`)                                    |
| `prod/variables.tf` | AI 변수                         | `ai_image`, `ai_ami_id`, `ai_instance_type`, `ai_private_ip`, `ai_memory`, `ai_port` |

### 3.1 AI 서버 (`aws_instance`)

- ASG 대신 단일 인스턴스로 두어 사설 IP를 고정한다.
- user data로 같은 클러스터에 등록하고, `ECS_INSTANCE_ATTRIBUTES={"workload":"ai"}`로 AI 서버임을 표시한다.
- Instance Profile은 ECS Host와 같은 `kgb-prod-ecs-instance-profile`을 쓴다 (ECS 등록, SSM).
- **AMI는 ID로 고정**한다. `aws_instance`는 AMI가 바뀌면 서버가 교체되기 때문이다(Backend ECS Host는 Launch Template이라 자동 조회).

### 3.2 AI Service 배치

- AI Service는 `launch_type = EC2` + `memberOf(attribute:workload == ai)`로 AI 서버에만 배치된다.
- Backend Service는 Capacity Provider(ASG 서버)로 배치되므로 AI 서버에 오지 않는다.
- 기존 `aws_ecs_cluster_capacity_providers`는 수정하지 않는다.

### 3.3 Task Definition

| 항목            | 값                                                |
|---------------|--------------------------------------------------|
| 이미지           | `ghcr.io/100-hours-a-week/ktb4-10-ai:image_name` |
| 이미지 인증        | Backend와 같은 `kgb-prod/ghcr` (같은 조직 이미지)          |
| 포트            | 8000 (컨테이너, 호스트 동일)                              |
| 헬스 체크         | `GET /health` (컨테이너 헬스 체크는 설정하지 않음)              |
| 메모리 상한        | 1024 MiB                                         |
| `stopTimeout` | 120초                                             |
| Task Role     | 없음 (AWS API 호출 없음)                               |

### 3.4 배포 설정

| 항목                      | 값         | 이유                                      |
|-------------------------|-----------|-----------------------------------------|
| Minimum Healthy Percent | 0         | AI 서버 1대, 고정 포트라 기존 Task를 먼저 내려야 함      |
| Maximum Percent         | 100       | Task 1개 유지 (작업 큐가 메모리에 있음)              |
| Circuit Breaker         | 켜짐, 자동 롤백 |                                         |
| `stopTimeout`           | 120초      | 생성 작업(p95 약 58초)이 배포 중에 잘리지 않도록. 기본 30초 |

**배포 중에는 AI가 잠깐 중단된다.** 기존 Task가 내려가고 새 Task가 뜰 때까지 AI 요청은 실패한다. 진행 중이던 작업은 `stopTimeout` 안에 끝나면 유지되지만, 메모리 큐에 대기 중이던
작업은 사라진다.

## 4. Backend → AI 통신

```text
Backend (2a, 2c) ──HTTP──▶ 10.10.10.250:8000 (AI)
```

| 항목      | 값                                               |
|---------|-------------------------------------------------|
| 주소      | `AI_SERVER_BASE_URL = http://10.10.10.250:8000` |
| 연결 타임아웃 | `AI_SERVER_CONNECT_TIMEOUT = 3s`                |
| 읽기 타임아웃 | `AI_SERVER_READ_TIMEOUT = 10s`                  |
| SG      | ECS Host → AI 8000만 허용                          |

### 4.1 `/health`와 `/metrics`

`/health` 응답 예시:

```json
{
  "status": "ok",
  "llm_mode": "real",
  "jobs": 3,
  "queue_size": 0,
  "running": 1
}
```

- 서버가 살아 있으면 항상 200이다. 큐가 가득 차거나 가짜 모드여도 200이다.
- 큐가 밀리는지는 `queue_size`, `running` 또는 `/metrics`로 따로 봐야 한다.
- **`/metrics`는 외부에 열면 안 된다.** AI SG는 ECS Host에서 오는 8000만 허용하고, ALB에도 연결하지 않는다. 모니터링을 붙일 때 Monitoring SG에서만 8000을 추가로
  허용한다.

### 4.2 타임아웃 확인 필요

생성 p95가 약 58초인데 Backend 읽기 타임아웃은 10초다. V1에서도 같은 값으로 동작 중이므로, Backend가 작업을 맡기고 결과는 나중에 조회하는 **비동기 구조**일 가능성이 높다. 동기 호출이라면
V2에서도 10초에 끊기므로 Backend·AI 담당자에게 확인해야 한다.

### 4.3 AI → Backend 호출 여부

AI가 작업 완료 콜백 등으로 Backend를 다시 부르는지 확인이 필요하다. 부른다면 AI → Backend 경로와 SG 규칙이 추가로 필요하다.

## 5. 장애 시 동작

| 장애                 | 결과                                           |
|--------------------|----------------------------------------------|
| AI 컨테이너 종료         | ECS가 같은 서버에 다시 띄움 → 같은 IP. 메모리 큐의 대기 작업은 사라짐 |
| AI 서버 재부팅          | 같은 서버, 같은 IP                                 |
| 하드웨어 장애            | EC2 자동 복구가 같은 IP로 다시 띄움                      |
| AZ(2a) 장애          | 2a가 복구될 때까지 AI 중단. ASG가 없어 다른 AZ로 옮기지 않음     |
| AI 서버 장애 중 Backend | Backend는 계속 동작. AI 기능만 실패                    |

AI 1대는 단일 장애 지점이다. V1 `kgb-ai`도 같은 조건이었다.

## 6. 배포 순서

1. 현재 상태 확인: Backend Task 수가 의도대로인지 (`-var backend_desired_count=2` 없이 apply하면 0개로 내려감)
2. `terraform plan -var backend_desired_count=2 -out=tfplan`
    - 추가: AI SG와 규칙, AI 서버, Log Group, Task Definition, Service
    - 변경: Backend Task Definition(`AI_SERVER_BASE_URL`), Backend Service
    - AMI 자동 업데이트가 있으면 ECS Launch Template·ASG 변경이 함께 나옴
3. `terraform apply tfplan`
4. AI 서버가 클러스터에 등록되고 `workload=ai` 속성이 보이는지 확인
5. AI Task가 AI 서버에만 떴는지 확인
6. Backend 2개(2a, 2c) 모두에서 AI 호출 확인

**plan 승인 기준:** Backend Service의 `desired_count` 변경, ECS ASG 교체, 기존 Capacity Provider 제거 같은 의도하지 않은 변경이 없어야 한다.

## 7. 검증

| 항목               | 방법                                                                     | 통과 기준                   |
|------------------|------------------------------------------------------------------------|-------------------------|
| AI 서버 등록         | ECS Container Instance 목록, <br/>사용자 지정 속성: `workload=ai`               | 등록됨                     |
| AI Task 배치       | `describe-tasks`                                                       | AI 서버에만 배치              |
| AI 응답            | AI 서버에서 `curl localhost:8000/health`                                   | 200                     |
| **Backend → AI** | 2a, 2c ECS Host의 Backend 컨테이너에서 `curl http://10.10.10.250:8000/health` | 두 경로 모두 200             |
| 재시작 후 주소         | AI Task를 멈춘 뒤 다시 뜨면 위 확인 반복                                            | 같은 주소로 응답               |
| 생성 부하            | 동시 3건 + 대기 요청                                                          | OOM 없이 완료               |
| AI 서버 장애         | AI 서버 재부팅                                                              | 복구 시간 측정, Backend 영향 없음 |

## 8. 모니터링 (예정)

- AI 컨테이너: CPU, 메모리, 재시작, 동시 실행 수, 대기 수, 작업 시간 p95, 실패율 (`/metrics`)
- AI 서버: CPU, CPUCreditBalance, 메모리, 디스크, ECS Agent 상태
- 모니터링 Daemon(node-exporter, cAdvisor)을 올리면 같은 클러스터의 AI 서버에도 자동으로 배치된다. 이때 AI SG에 Monitoring → 9100, 8082, 8000 규칙을
  추가한다.

## 9. 향후 개선

| 단계 | 작업                            | 해결되는 것                                                |
|----|-------------------------------|-------------------------------------------------------|
| 1  | **SQS 도입** (Backend·AI 코드 변경) | AI 주소 고정 불필요, 타임아웃 문제 해소, AI 장애 시 작업이 큐에 대기, AI 확장 쉬움 |
| 2  | AI 2대 이상                      | 단일 장애 지점 제거 (SQS 또는 내부 ALB 필요)                        |
| 3  | RunPod 연동 (`LLM_MODE` 변경)     | 실제 생성. 메모리·CPU·외부 호출 지표 다시 측정                         |

## 10. 미해결 확인 사항

1. **AI 기능의 허용 중단 시간(RTO)**: 배포·장애 중 몇 분 중단이 허용되는지
2. **Backend → AI 호출이 동기인지 비동기인지**: 타임아웃 10초 vs 생성 약 58초
3. **AI가 Backend를 다시 부르는지**: 콜백이 있다면 경로·SG 추가
4. **워커 3개의 제한 방식**: 프로세스 수, 세마포어, 큐 소비자 중 무엇인지
5. **동시 3건 처리 중 최대 메모리**: 메모리 상한 1024 MiB 적정성
