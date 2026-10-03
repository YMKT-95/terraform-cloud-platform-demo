locals {
  name = "terraform-demo-${var.environment}"
}

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "app" {
  ami                         = nonsensitive(data.aws_ssm_parameter.ami.value)
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    image_ref = var.image_ref
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  credit_specification {
    cpu_credits = "standard"
  }

  # A subnet reference alone does not wait for its internet route or SG rules.
  depends_on = [
    aws_route.internet,
    aws_route_table_association.public,
    aws_vpc_security_group_egress_rule.outbound,
    aws_iam_role_policy_attachment.ssm,
  ]

  tags = { Name = "${local.name}-app" }
}
