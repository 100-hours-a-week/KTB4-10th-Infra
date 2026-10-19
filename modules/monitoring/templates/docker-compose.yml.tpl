services:
  prometheus:
    image: ${prometheus_image}
    container_name: prometheus
    restart: unless-stopped
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=${retention_time}
      - --storage.tsdb.retention.size=${retention_size}
    # 서버 안에서 확인용. 외부에는 열지 않음
    ports:
      - "127.0.0.1:9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus

  grafana:
    image: ${grafana_image}
    container_name: grafana
    restart: unless-stopped
    # NAT 경유 SSM 포트 포워딩으로 접속 (SG가 NAT에서 오는 것만 허용)
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: $${GRAFANA_ADMIN_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_AUTH_ANONYMOUS_ENABLED: "false"
      GF_ANALYTICS_REPORTING_ENABLED: "false"
      GF_ANALYTICS_CHECK_FOR_UPDATES: "false"
      GF_SERVER_DOMAIN: localhost
      GF_SERVER_ROOT_URL: http://localhost:3000
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    depends_on:
      - prometheus

  mysqld-exporter:
    image: ${mysqld_exporter_image}
    container_name: mysqld-exporter
    restart: unless-stopped
    command:
      - --mysqld.address=${db_address}
      - --mysqld.username=${db_username}
      # 대시보드는 global status/variables만 사용. 권한이 없는 수집 항목은 끔
      - --no-collect.slave_status
      - --no-collect.info_schema.innodb_cmp
      - --no-collect.info_schema.innodb_cmpmem
      - --no-collect.info_schema.query_response_time
    environment:
      MYSQLD_EXPORTER_PASSWORD: $${MYSQL_EXPORTER_PASSWORD}

volumes:
  prometheus-data:
    name: prometheus-data
  grafana-data:
    name: grafana-data
