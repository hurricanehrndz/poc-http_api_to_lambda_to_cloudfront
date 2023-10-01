variable "aws_region" {
  default = "us-west-2"
}

variable "bucket" {
  default = "hhrdz-docs"
}

variable "bucket_region" {
  default = "us-east-1"
}

variable "project" {
  default = "hurricanenotes"
}

variable "owner" {
  default = "hrndz"
}

variable "domain" {
  description = "The entry point DNS for the Edge gateway stack. Normally this is an application FQDN like jira.yelpcorp.com"
  type        = string
}
