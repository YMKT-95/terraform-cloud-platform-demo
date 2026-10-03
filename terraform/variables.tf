variable "aws_region" {
  description = "AWS region for this demo. The example uses Sydney."
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Short environment name used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.environment))
    error_message = "Use 1-16 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "vpc_cidr" {
  description = "IPv4 /16 network; the public /24 subnet is derived with cidrsubnet."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/16$", var.vpc_cidr))
    error_message = "Provide a valid IPv4 /16 CIDR, for example 10.20.0.0/16."
  }
}

variable "instance_type" {
  description = "Small x86 instance compatible with the AMD64 image and AMI."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "This demo supports t3.micro or t3.small; ARM instances need a different AMI and image."
  }
}

variable "image_ref" {
  description = "Public GHCR image pinned by digest, copied from the publish workflow summary."
  type        = string

  validation {
    condition     = can(regex("^ghcr\\.io/[a-z0-9._/-]+@sha256:[0-9a-f]{64}$", var.image_ref))
    error_message = "Provide ghcr.io/owner/image@sha256:<64 lowercase hex characters>; mutable tags are not accepted."
  }
}

variable "allowed_http_cidr" {
  description = "Source IPv4 CIDR allowed to reach port 80. Prefer your public IP with /32."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_http_cidr))
    error_message = "Provide a valid IPv4 CIDR, for example your public IPv4 address followed by /32."
  }
}
