output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ip" {
  description = "Public IP address of the NAT gateway"
  value       = aws_eip.nat.public_ip
}

output "web_security_group_id" {
  description = "Security group ID for the web tier"
  value       = aws_security_group.web.id
}

output "app_security_group_id" {
  description = "Security group ID for the app tier"
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "Security group ID for the database tier"
  value       = aws_security_group.db.id
}
