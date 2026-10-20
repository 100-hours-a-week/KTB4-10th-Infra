# NAT 인스턴스 (AZ별 1대)
resource "aws_instance" "nat" {
  count = length(var.public_subnet_ids)

  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id              = var.public_subnet_ids[count.index]
  vpc_security_group_ids = [var.security_group_id]

  # EIP를 쓰면 자동 공인 IP는 받지 않음
  associate_public_ip_address = !var.use_eip

  # EIP가 붙으면 true로 읽혀서 인스턴스가 교체되는 것 방지
  lifecycle {
    ignore_changes = [associate_public_ip_address]
  }

  # NAT 패킷 전달 허용
  source_dest_check = false

  # SSM Session Manager
  iam_instance_profile = var.instance_profile_name

  # IP 포워딩, SNAT 설정
  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
    # NAT 인스턴스가 직접 요청한 경우에만 토큰 받음
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-nat-${substr(var.azs[count.index], -1, 1)}"
  }
}

resource "aws_eip" "nat" {
  count = var.use_eip ? length(var.public_subnet_ids) : 0

  domain = "vpc"

  tags = {
    Name = "${var.name}-nat-eip-${substr(var.azs[count.index], -1, 1)}"
  }
}

# EIP를 NAT EC2에 연결
resource "aws_eip_association" "nat" {
  count = var.use_eip ? length(var.public_subnet_ids) : 0

  instance_id   = aws_instance.nat[count.index].id
  allocation_id = aws_eip.nat[count.index].id
}

# private-app subnet의 외부 통신 경로 (같은 AZ의 NAT로 전송)
resource "aws_route" "private_app_nat" {
  count = length(var.private_app_route_table_ids)

  route_table_id         = var.private_app_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[count.index].primary_network_interface_id

  depends_on = [aws_eip_association.nat]
}
