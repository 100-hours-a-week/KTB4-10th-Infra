# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.name}-vpc"
  }
}

# Public subnet 1, 2
resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name}-public-snet-${substr(var.azs[count.index], -1, 1)}"
  }
}

# Private app subnet 1, 2
resource "aws_subnet" "private_app" {
  count = length(var.private_app_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name}-private-app-snet-${substr(var.azs[count.index], -1, 1)}"
  }
}

# Private db subnet 1, 2
resource "aws_subnet" "private_db" {
  count = length(var.private_db_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_db_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name}-private-db-snet-${substr(var.azs[count.index], -1, 1)}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-public-rt"
  }
}

# 트래픽 전송 경로
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# subnet 라우팅 규칙
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_app" {
  count  = length(var.private_app_subnets)
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-private-app-rt-${substr(var.azs[count.index], -1, 1)}"
  }
}

resource "aws_route_table_association" "private_app" {
  count = length(aws_subnet.private_app)

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-private-db-rt"
  }
}

resource "aws_route_table_association" "private_db" {
  count = length(aws_subnet.private_db)

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}
