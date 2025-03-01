resource "aws_vpc" "main_vpc" {
  cidr_block       = var.vpc_cidr_block
  instance_tenancy = "default"
  tags = {
    Name = "main_vpc"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_ciders)
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnet_ciders[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "public_subnet_${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_ciders)
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.private_subnet_ciders[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "private_subnet_${count.index + 1}"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "main_igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }
  tags = {
    Name = "public_rt"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public_nat_gateway.id
  }
  tags = {
    Name = "private_rt"
  }
}

resource "aws_route_table_association" "public_subnet_associations" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_subnet_associations" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_eip" "aws_public_eip" {
  public_ipv4_pool = "amazon"
  tags = {
    Name = "aws_public_eip"
  }
}

resource "aws_nat_gateway" "public_nat_gateway" {
  allocation_id     = aws_eip.aws_public_eip.id
  subnet_id         = aws_subnet.public_subnets[0].id
  connectivity_type = "public"
  tags = {
    Name = "public_nat_gateway"
  }
}

resource "aws_security_group" "bastion_sg" {
  name        = "bastion_sg"
  description = "Cloudflare Tunnel or VPN"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "Allow SSH from internal VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  ingress {
    description = "Allow HTTPS from anywhere (Cloudflare Tunnel/VPN)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Allow outbound SSH to private EC2"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.private_ec2_sg.id]
  }

  egress {
    description = "Allow outbound HTTPS for updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_ec2_sg" {
  name        = "private_ec2_sg"
  description = "Private EC2 security group"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description     = "Allow SSH from Bastion Host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  ingress {
    description = "Allow HTTP from ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.public_subnet_ciders
  }

  ingress {
    description = "Allow HTTPS from ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.public_subnet_ciders
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  description = "Security Group for Application Load Balancer"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Allow all outbound traffic to private EC2 instances"
    from_port       = 0
    to_port         = 65535
    protocol        = "-1"
    security_groups = [aws_security_group.private_ec2_sg.id]
  }

  depends_on = [aws_security_group.private_ec2_sg]
}



# data "aws_ssm_parameter" "client_vpn_certificate" {
#   name = "vpn_server_certificate_arn"
# }

# resource "aws_cloudwatch_log_group" "client_vpn_log_group" {
#   name              = "client_vpn_log_group"
#   retention_in_days = 30
# }

# resource "client_vpn_endpoint" "vpn" {
#   description            = "Client VPN endpoint"
#   server_certificate_arn = data.aws_ssm_parameter.client_vpn_certificate.value
#   client_cidr_block      = "10.0.0.0/22"
#   connection_log_options {
#     enabled              = true
#     cloudwatch_log_group = aws_cloudwatch_log_group.client_vpn_log_group.name
#   }
#   authentication_options {
#     type                       = "certificate-authentication"
#     root_certificate_chain_arn = data.aws_ssm_parameter.client_vpn_certificate.value
#   }
# }

# resource "aws_client_vpn_network_association" "vpn_assoc" {
#   client_vpn_endpoint_id = client_vpn_endpoint.vpn.id
#   subnet_id              = aws_subnet.private_subnets[0].id
# }
