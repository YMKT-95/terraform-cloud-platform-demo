# These plan tests use fake provider data and never call AWS.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-southeast-2a"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
}

variables {
  image_ref         = "ghcr.io/ymkt-95/terraform-cloud-platform-demo@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  allowed_http_cidr = "203.0.113.10/32"
}

run "deployment_contract" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.http.cidr_ipv4 == "203.0.113.10/32" && aws_vpc_security_group_ingress_rule.http.from_port == 80 && aws_vpc_security_group_ingress_rule.http.to_port == 80
    error_message = "The HTTP rule must preserve the caller's source restriction and expose only port 80."
  }

  assert {
    condition     = aws_instance.app.associate_public_ip_address && aws_route.internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "The public deployment needs a public IP and an internet route."
  }

  assert {
    condition     = aws_instance.app.metadata_options[0].http_tokens == "required" && aws_instance.app.root_block_device[0].encrypted && aws_instance.app.root_block_device[0].delete_on_termination
    error_message = "Require IMDSv2 and an encrypted root disk that is removed with the instance."
  }

  assert {
    condition     = aws_instance.app.user_data_replace_on_change
    error_message = "Image/bootstrap changes must replace the instance to execute user data again."
  }
}

run "reject_mutable_image" {
  command = plan
  variables {
    image_ref = "ghcr.io/ymkt-95/terraform-cloud-platform-demo:latest"
  }
  expect_failures = [var.image_ref]
}

run "reject_invalid_client_network" {
  command = plan
  variables {
    allowed_http_cidr = "not-a-cidr"
  }
  expect_failures = [var.allowed_http_cidr]
}

run "reject_arm_instance_for_amd64_image" {
  command = plan
  variables {
    instance_type = "t4g.micro"
  }
  expect_failures = [var.instance_type]
}
