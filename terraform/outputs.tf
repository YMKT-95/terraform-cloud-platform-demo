output "instance_id" {
  description = "Instance to select in Systems Manager Session Manager."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Ephemeral public IPv4 address; it can change after replacement or stop/start."
  value       = aws_instance.app.public_ip
}

output "application_url" {
  description = "HTTP URL; wait for bootstrap and verify /health after apply."
  value       = "http://${aws_instance.app.public_ip}"
}

output "vpc_id" {
  description = "VPC managed by this configuration."
  value       = aws_vpc.main.id
}
