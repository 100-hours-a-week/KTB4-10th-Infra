# KGB V2 — RDS 설계

## 1. 개요

KGB V2는 Amazon RDS for MySQL을 사용하여 Backend의 데이터를 저장한다.

RDS 설계 목적

- V1 MySQL과 동일한 버전·설정으로 구성하여 데이터 이전 시 차이 제거
- Multi-AZ 구성으로 AZ 장애와 유지보수 시 중단 시간 최소화
- Private Subnet 배치와 보안 그룹으로 접근 경로 제한
- 자동 백업과 삭제 보호로 데이터 유실 방지
- Terraform을 통한 RDS 리소스 관리

## 2. 구성 요약

| 항목        | 값                               |
|-----------|---------------------------------|
| 식별자       | `kgb-prod-db`                   |
| DB 엔진     | MySQL 8.4.11                    |
| 인스턴스 사양   | `db.t3.small` (2 vCPU, 2GiB)    |
| 스토리지      | gp3 20GiB, 자동 확장 상한 50GiB, 암호화  |
| 배포 방식     | Multi-AZ (운영 1대 + 대기 1대)        |
| 네트워크      | private-db subnet 2개, 퍼블릭 접근 차단 |
| 포트        | 3306                            |
| 초기 데이터베이스 | `kgb`                           |
| 마스터 계정    | `admin`                         |

## 3. 아키텍처

```text
ECS Backend Task ──── TCP 3306 ────┐
                                   ▼
                           RDS Endpoint
                                   │
              ┌────────────────────┴────────────────────┐
              ▼                                         ▼
   private-db-snet-a (2a)                    private-db-snet-c (2c)
   운영 또는 대기 인스턴스                        운영 또는 대기 인스턴스

개발자 PC ── SSM 포트 포워딩 ── NAT Instance ── TCP 3306 ── RDS Endpoint
```

- 운영 인스턴스와 대기 인스턴스가 어느 AZ에 놓일지는 AWS가 생성 시점에 정한다.
- 장애 조치(failover)가 일어나면 운영과 대기의 위치가 바뀐다.
- 애플리케이션은 RDS Endpoint 하나로 접속하며, Endpoint는 항상 현재 운영 인스턴스를 가리킨다.

## 4. Terraform 리소스

`modules/rds`에서 3개의 리소스를 생성한다.

| 리소스                      | 이름                         | 역할                 |
|--------------------------|----------------------------|--------------------|
| `aws_db_subnet_group`    | `kgb-prod-db-subnet-group` | RDS를 배치할 subnet 목록 |
| `aws_db_parameter_group` | `kgb-prod-mysql-params`    | MySQL 설정값          |
| `aws_db_instance`        | `kgb-prod-db`              | RDS MySQL 인스턴스     |

### 4.1 DB Subnet Group

RDS 인스턴스는 subnet을 직접 지정하지 않고 DB Subnet Group을 통해 배치된다.

```text
RDS Instance → DB Subnet Group → private-db-snet-a, private-db-snet-c
```

DB Subnet Group에 private-db subnet만 포함했으므로 RDS는 다른 subnet에 생성될 수 없다.

### 4.2 Parameter Group

AWS가 제공하는 기본 Parameter Group(`default.mysql8.4`)은 수정할 수 없다.
설정을 변경하려면 전용 Parameter Group이 필요하므로 처음부터 전용 그룹을 사용한다.

현재 변경한 값은 `sql_mode` 하나이다.

| 파라미터       | RDS 기본값                  | 적용 값 (V1과 동일)                                                                                                           |
|------------|--------------------------|-------------------------------------------------------------------------------------------------------------------------|
| `sql_mode` | `NO_ENGINE_SUBSTITUTION` | `ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION` |

RDS 기본값을 그대로 쓰면 다음과 같은 차이가 생긴다.

- `STRICT_TRANS_TABLES`가 없으면 컬럼 길이를 넘는 값이 오류 없이 잘려서 저장된다.
- `ONLY_FULL_GROUP_BY`가 없으면 `GROUP BY`에 없는 컬럼을 조회할 때 임의의 값이 반환된다.

## 5. V1과의 설정 비교

V1 MySQL에서 직접 조회한 값과 V2 RDS 설정을 비교했다.

| 항목                       | V1                   | V2 RDS               | 조치                  |
|--------------------------|----------------------|----------------------|---------------------|
| 버전                       | 8.4.11               | 8.4.11               | 동일 버전 지정            |
| `character_set_server`   | `utf8mb4`            | `utf8mb4`            | 엔진 기본값 사용           |
| `collation_server`       | `utf8mb4_0900_ai_ci` | `utf8mb4_0900_ai_ci` | 엔진 기본값 사용           |
| `time_zone`              | UTC                  | UTC                  | RDS 기본값 사용          |
| `lower_case_table_names` | `0`                  | `0`                  | 엔진 기본값 사용           |
| `sql_mode`               | 엄격 모드 6개             | 엄격 모드 6개             | Parameter Group에 지정 |
| 데이터베이스 이름                | `kgb`                | `kgb`                | `db_name`으로 지정      |

- DB의 time zone은 UTC로 유지한다. `Asia/Seoul`로 변경하면 V1에서 이전한 시간 데이터와 새 데이터가 9시간 어긋난다.
- `lower_case_table_names`는 RDS 생성 후 변경할 수 없다.

## 6. 인스턴스 사양

### 6.1 인스턴스 클래스

| 항목               | 메모리      |
|------------------|----------|
| V1 MySQL 평상시 사용량 | 760.7MiB |
| `db.t3.micro`    | 1,024MiB |
| `db.t3.small`    | 2,048MiB |

`db.t3.micro`는 V1 평상시 사용량만으로 메모리의 약 74%를 차지하므로 `db.t3.small`을 사용한다.

- MySQL은 설정된 버퍼 풀 크기만큼 메모리를 사용하므로, V1의 사용량은 필요한 최소량이 아니라 V1 설정에서의 사용량이다.
- RDS는 버퍼 풀을 인스턴스 메모리의 약 75%로 설정한다.
- V1 데이터 크기(357MiB)는 `db.t3.small`의 버퍼 풀에 모두 올라가는 크기이다.
- `t3`는 버스트 타입이므로 CPU 크레딧을 모두 소진하면 추가 요금이 발생한다.
- `db.t3.small`은 Performance Insights를 지원하지 않는다.

사양의 적정성은 부하 테스트로 검증한다.

### 6.2 스토리지

| 항목               | 값      |
|------------------|--------|
| V1 MySQL 디스크 사용량 | 357MiB |
| 초기 스토리지          | 20GiB  |
| 자동 확장 상한         | 50GiB  |
| 볼륨 유형            | gp3    |

- 20GiB는 RDS gp3의 최소 용량이다.
- RDS MySQL의 gp3는 400GiB 미만에서 3,000 IOPS와 125MiB/s로 고정되며 추가 프로비저닝을 할 수 없다.
- 스토리지는 늘릴 수만 있고 줄일 수 없다.
- 여유 공간이 부족해지면 상한(50GiB)까지 자동으로 확장된다.
- 스토리지 암호화는 생성 후 변경할 수 없으므로 처음부터 활성화한다.

## 7. 접근 제어

### 7.1 네트워크

| 출발지             | 포트   | 용도                 |
|-----------------|------|--------------------|
| Backend Task SG | 3306 | 애플리케이션의 DB 접속      |
| NAT SG          | 3306 | 개발자의 SSM 포트 포워딩 접속 |

- RDS SG에는 아웃바운드 규칙이 없다.
- private-db subnet의 Route Table에는 VPC 내부 경로만 있으며 외부로 나가는 경로가 없다.
- Backend는 VPC 내부에서 RDS에 직접 접속하며 NAT를 거치지 않는다.

### 7.2 개발자 접속

개발자는 NAT Instance를 거치는 SSM 포트 포워딩으로 접속한다.

```bash
aws ssm start-session --target <NAT 인스턴스 ID> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<RDS Endpoint>"],"portNumber":["3306"],"localPortNumber":["3306"]}'
```

세션을 연 상태에서 DB 클라이언트로 `127.0.0.1:3306`에 접속한다.

### 7.3 계정

| 계정      | 용도             | 비밀번호 관리                                 |
|---------|----------------|-----------------------------------------|
| `admin` | 초기 설정, 계정 생성   | `terraform.tfvars` (git 제외)             |
| 애플리케이션용 | Backend의 DB 접속 | Secrets Manager `kgb-prod/` 접두사 (생성 예정) |
| 개발자용    | 조회 및 확인        | 생성 예정                                   |

마스터 비밀번호는 `password_wo`(write-only) 속성으로 전달한다.

- Terraform이 비밀번호를 RDS에 전달만 하고 state에는 저장하지 않는다.
- 비밀번호를 변경할 때는 `terraform.tfvars`의 값을 수정하고 `password_wo_version`을 올린 뒤 apply한다.
- 버전을 올리지 않으면 값을 바꿔도 반영되지 않는다.
- 콘솔에서 비밀번호를 변경하면 Terraform은 이를 감지하지 못한다.

Backend는 마스터 계정을 사용하지 않고 권한을 제한한 별도 계정을 사용한다.

## 8. 백업 및 유지보수

| 설정                           | 값                           | 역할                       |
|------------------------------|-----------------------------|--------------------------|
| `backup_retention_period`    | 7                           | 자동 백업을 7일간 보관            |
| `backup_window`              | `17:00-18:00` (UTC)         | 매일 02:00~03:00 KST에 백업   |
| `maintenance_window`         | `sun:18:00-sun:19:00` (UTC) | 월요일 03:00~04:00 KST      |
| `auto_minor_version_upgrade` | `false`                     | 마이너 버전을 직접 올림            |
| `apply_immediately`          | `false`                     | 재시작이 필요한 변경은 유지보수 시간에 적용 |
| `deletion_protection`        | `true`                      | 실수로 인한 삭제 방지             |
| `skip_final_snapshot`        | `false`                     | 삭제 시 최종 스냅샷 생성           |
| `final_snapshot_identifier`  | `kgb-prod-mysql-final`      | 최종 스냅샷 이름                |

### 8.1 백업

- 매일 백업 시간대에 스냅샷을 생성하고, 트랜잭션 로그를 5분 간격으로 저장한다.
- 보관 기간(7일) 안의 원하는 시점으로 복구할 수 있다.
- Multi-AZ에서는 대기 인스턴스에서 스냅샷을 생성하므로 운영 인스턴스에 미치는 영향이 작다.

### 8.2 유지보수

- 유지보수 시간대는 작업을 시작할 수 있는 허용 구간이며, 매주 작업이 실행되는 것은 아니다.
- OS 패치 등 AWS가 예약한 작업이나 재시작이 필요한 설정 변경이 있을 때만 실행된다.
- Multi-AZ에서는 대기 인스턴스에 먼저 적용한 뒤 장애 조치를 수행하므로, 연결이 끊기는 시간은 1~2분이다.
- 백업 시간대와 유지보수 시간대는 겹칠 수 없다.

### 8.3 삭제

`deletion_protection`이 활성화되어 있어 `terraform destroy`가 실패한다.
삭제하려면 먼저 `deletion_protection`을 `false`로 변경하여 apply해야 한다.

## 9. 로그

| 로그    | 전송 대상           |
|-------|-----------------|
| 에러 로그 | CloudWatch Logs |

- 로그 그룹은 RDS가 자동으로 생성하며 보관 기간은 무기한이다.
- 슬로우 쿼리 로그는 현재 비활성화 상태이다. 필요 시 Parameter Group에 추가하며 재부팅은 필요하지 않다.

## 10. 설계 결정

| 결정                          | 이유                                      |
|-----------------------------|-----------------------------------------|
| Multi-AZ 사용                 | AZ 장애와 유지보수 시 중단 시간을 1~2분으로 줄인다         |
| 전용 Parameter Group 사용       | 기본 그룹은 수정할 수 없고, V1과 `sql_mode`를 맞춰야 한다 |
| DB time zone을 UTC로 유지       | V1과 동일하게 유지하여 이전한 데이터와 새 데이터의 기준을 맞춘다   |
| 마스터 비밀번호를 `password_wo`로 전달 | 비밀번호를 직접 정하되 Terraform state에는 남기지 않는다  |
| 마이너 버전 자동 업그레이드 비활성화        | 예고 없는 장애 조치를 피하고 업그레이드 일정을 직접 정한다       |
| 스토리지 자동 확장 상한 설정            | 향후 데이터 증가량이 확인되지 않았고, 스토리지는 줄일 수 없다     |
| 모듈에 환경별 값을 하드코딩하지 않음        | `prod`와 `staging`이 같은 모듈을 쓴다            |

## 11. 검증

| 검증                                | 결과                                            |
|-----------------------------------|-----------------------------------------------|
| `terraform fmt -check -recursive` | 통과                                            |
| `terraform validate`              | `Success! The configuration is valid.`        |
| `terraform plan`                  | `Plan: 58 to add, 0 to change, 0 to destroy.` |

Plan의 58개에는 아직 apply하지 않은 Security Group 27개, IAM 20개, NAT 8개가 포함되어 있으며 RDS는 3개이다.

### 구축 후 확인할 것

- [ ] ECS Backend → RDS 연결
- [ ] SSM 포트 포워딩을 통한 개발자 접속
- [ ] Multi-AZ 구성 및 운영·대기 AZ 확인
- [ ] 자동 백업, 삭제 보호 설정 확인
- [ ] 장애 조치 후 Backend 커넥션 풀의 재연결 확인
- [ ] CloudWatch `FreeableMemory`, `CPUUtilization`, `CPUCreditBalance`, `FreeStorageSpace` 확인
- [ ] 부하 테스트로 `db.t3.small` 사양 검증

## 12. 후속 작업

- [ ] V1 → V2 데이터 이전 방식 결정 및 필요한 네트워크 경로 구성
- [ ] 애플리케이션용 DB 계정 생성 및 Secrets Manager 등록
- [ ] 개발자용 DB 계정 생성
- [ ] CloudWatch 알람 구성
- [ ] 메이저 버전 업그레이드에 대비한 Parameter Group 이름 변경 검토
