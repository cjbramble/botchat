variable "domain" {
  type        = string
  description = "Public name of the viewer, for example botchat.example.com."
}

variable "zone_name" {
  type        = string
  description = "Route 53 hosted zone that holds the domain, for example example.com."
}

variable "k3s_version" {
  type        = string
  default     = "v1.36.5+k3s1"
  description = "k3s release installed on first boot. See github.com/k3s-io/k3s/releases."
}

variable "instance_type" {
  type        = string
  default     = "t4g.xlarge"
  description = "An ARM (Graviton) type, so images are built for linux/arm64."
}
