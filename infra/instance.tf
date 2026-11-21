# Ubuntu 24.04 LTS for ARM, the newest image Canonical publishes.
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

resource "aws_security_group" "instance" {
  name        = "botchat-instance"
  description = "Web traffic in; anything out"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "instance_web" {
  for_each          = toset(["80", "443"]) # 80 for HTTP-to-HTTPS redirects and Let's Encrypt
  security_group_id = aws_security_group.instance.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.key)
  to_port           = tonumber(each.key)
}

resource "aws_vpc_security_group_egress_rule" "instance_all" {
  security_group_id = aws_security_group.instance.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # all protocols: OpenRouter, AWS APIs, ECR, OS updates
}

resource "aws_instance" "k3s" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.instance_type
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  # A temporary public address so first boot can download k3s; the Elastic IP replaces it.
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/k3s-init.sh", { k3s_version = var.k3s_version })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only: no credentials from a simple GET
    http_put_response_hop_limit = 2          # one extra hop, so pods can reach it
  }

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "botchat" }

  lifecycle {
    # A new Ubuntu image or an edited script must not silently replace the machine
    # (and everything inside k3s). Rebuild on purpose instead (13.12).
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "instance" {
  domain   = "vpc"
  instance = aws_instance.k3s.id
  tags     = { Name = "botchat" }
}
