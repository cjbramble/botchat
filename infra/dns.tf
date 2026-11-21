data "aws_route53_zone" "main" {
  name = var.zone_name
}

resource "aws_route53_record" "viewer" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.instance.public_ip]
}
