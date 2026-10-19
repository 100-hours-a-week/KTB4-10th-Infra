# job 이름과 server 라벨은 V1과 동일 (대시보드 호환)
global:
  scrape_interval: 10s
  evaluation_interval: 10s

scrape_configs:
  # ECS Host는 ASG가 교체하면 IP가 바뀌므로 EC2 태그로 탐색
  - job_name: "backend"
    scrape_timeout: 8s
    metrics_path: "/actuator/prometheus"
    ec2_sd_configs:
      - region: ${region}
        port: ${management_port}
        filters:
          - name: tag:Name
            values: ["${ecs_host_name}"]
          - name: instance-state-name
            values: ["running"]
    relabel_configs:
      - target_label: server
        replacement: backend
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
      # 대시보드 범례용 (ap-northeast-2a -> 2a). Backend는 AZ마다 1대
      - source_labels: [__meta_ec2_availability_zone]
        regex: '.*-([0-9][a-z])'
        target_label: az

  - job_name: "ai"
    scrape_timeout: 8s
    metrics_path: "/metrics"
    static_configs:
      - targets: ["${ai_target}"]
        labels:
          server: ai

  - job_name: "mysql"
    scrape_timeout: 8s
    metrics_path: "/metrics"
    static_configs:
      - targets: ["mysqld-exporter:9104"]

  - job_name: "node"
    scrape_timeout: 8s
    metrics_path: "/metrics"
    ec2_sd_configs:
      - region: ${region}
        port: ${node_exporter_port}
        filters:
          - name: tag:Name
            values: ["${ecs_host_name}", "${ai_name}"]
          - name: instance-state-name
            values: ["running"]
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Name]
        regex: "${ecs_host_name}"
        target_label: server
        replacement: backend
      - source_labels: [__meta_ec2_tag_Name]
        regex: "${ai_name}"
        target_label: server
        replacement: ai
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
      # 대시보드 범례용 (ap-northeast-2a -> 2a). Backend는 AZ마다 1대
      - source_labels: [__meta_ec2_availability_zone]
        regex: '.*-([0-9][a-z])'
        target_label: az

  - job_name: "cadvisor"
    scrape_timeout: 8s
    metrics_path: "/metrics"
    ec2_sd_configs:
      - region: ${region}
        port: ${cadvisor_port}
        filters:
          - name: tag:Name
            values: ["${ecs_host_name}", "${ai_name}"]
          - name: instance-state-name
            values: ["running"]
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Name]
        regex: "${ecs_host_name}"
        target_label: server
        replacement: backend
      - source_labels: [__meta_ec2_tag_Name]
        regex: "${ai_name}"
        target_label: server
        replacement: ai
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
      # 대시보드 범례용 (ap-northeast-2a -> 2a). Backend는 AZ마다 1대
      - source_labels: [__meta_ec2_availability_zone]
        regex: '.*-([0-9][a-z])'
        target_label: az
