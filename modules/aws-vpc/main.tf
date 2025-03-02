# Main VPC configuration
# Creates a Virtual Private Cloud with specified CIDR block
resource "aws_vpc" "main_vpc" {
  cidr_block       = var.vpc_cidr_block
  instance_tenancy = "default"
  tags = {
    Name = "main_vpc"
  }
}

# Public subnet configuration
# Creates public subnets in different availability zones with auto-assigned public IPs
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

# Private subnet configuration
# Creates private subnets in different availability zones without public IP assignment
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_ciders)
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.private_subnet_ciders[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "private_subnet_${count.index + 1}"
  }
}

# Internet Gateway configuration
# Enables communication between VPC and the internet
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "main_igw"
  }
}

# Public Route Table
# Routes traffic from public subnets to the internet via IGW
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

# Private Route Table
# Routes traffic from private subnets through NAT Gateway for internet access
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

# Public subnet route table associations
# Associates public subnets with the public route table
resource "aws_route_table_association" "public_subnet_associations" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Private subnet route table associations
# Associates private subnets with the private route table
resource "aws_route_table_association" "private_subnet_associations" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Elastic IP for NAT Gateway
# Allocates a static public IP from Amazon's pool
resource "aws_eip" "aws_public_eip" {
  public_ipv4_pool = "amazon"
  tags = {
    Name = "aws_public_eip"
  }
}

# NAT Gateway configuration
# Enables private subnet instances to access internet while remaining private
resource "aws_nat_gateway" "public_nat_gateway" {
  allocation_id     = aws_eip.aws_public_eip.id
  subnet_id         = aws_subnet.public_subnets[0].id
  connectivity_type = "public"
  tags = {
    Name = "public_nat_gateway"
  }
}

# Bastion Host Security Group
# Defines security rules for the bastion host/VPN endpoint
# Allows SSH access from VPC and HTTPS for Cloudflare Tunnel/VPN
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Private EC2 Security Group
# Defines security rules for private EC2 instances
# Allows SSH from bastion and web traffic from ALB
resource "aws_security_group" "private_ec2_sg" {
  name        = "private_ec2_sg"
  description = "Private EC2 security group"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "Allow SSH from Bastion Host"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  ingress {
    description = "Allow HTTP from ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]
  }

  ingress {
    description = "Allow HTTPS from ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application Load Balancer Security Group
# Defines security rules for the ALB
# Allows HTTP/HTTPS from internet and forwards to private instances
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
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.private_ec2_sg.id]
  }

  depends_on = [aws_security_group.private_ec2_sg]
}

# Public Network ACL
# Network level firewall for public subnets
# Allows all TCP traffic in and out (relies on security groups for detailed filtering)
resource "aws_network_acl" "public_acl" {
  vpc_id     = aws_vpc.main_vpc.id
  subnet_ids = [for s in aws_subnet.public_subnets : s.id]
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

# Private Network ACL
# Network level firewall for private subnets
# Restricts inbound access to VPC CIDR and allows all outbound
resource "aws_network_acl" "private_acl" {
  vpc_id     = aws_vpc.main_vpc.id
  subnet_ids = [for s in aws_subnet.private_subnets : s.id]
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr_block
    from_port  = 22
    to_port    = 22
  }
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = var.vpc_cidr_block
    from_port  = 80
    to_port    = 80
  }
  ingress {
    protocol   = "tcp"
    rule_no    = 210
    action     = "allow"
    cidr_block = var.vpc_cidr_block
    from_port  = 443
    to_port    = 443
  }
  ingress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = var.bastion_key_name
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "bastion_host" {
  ami                    = var.bastion_ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = aws_key_pair.bastion_key.key_name

  tags = {
    Name = "bastion_host"
  }
}
