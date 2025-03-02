output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main_vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the created public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the created private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "internet_gateway_id" {
  description = "ID of the created internet gateway"
  value       = aws_internet_gateway.main_igw.id
}

output "bastion_host_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion_host.public_ip
}



