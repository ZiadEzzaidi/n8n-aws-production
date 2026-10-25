variable "environment" {
  description = "Environment name, used in resource names and secret paths (e.g. prod, staging)."
  type        = string
  default     = "prod"
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "n8n_version" {
  description = "Pinned n8n image tag. Upgrades are deliberate: change it here, test in staging first."
  type        = string
  default     = "2.42.6"
}

variable "timezone" {
  type    = string
  default = "Africa/Casablanca"
}

variable "domain" {
  description = "Public hostname for n8n (DNS A record pointing to the server)."
  type        = string
}
