terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0.0"
    }
  }
}
provider "aws" {
  skip_region_validation      = true
  skip_credentials_validation = true
  default_tags {
    tags = merge(var.config.aws.tags, {
      StratusRedTeam = true
    })
  }
}


locals {
  resource_prefix = "${var.config.aws.prefix}stratus-red-team-dns-delete-${var.correlation.short}"
}

locals {
  bucket-name = "${local.resource_prefix}-bucket"
}

resource "aws_route53_resolver_query_log_config" "config" {
  name            = "${local.resource_prefix}-config"
  destination_arn = aws_s3_bucket.query_log.arn
}

resource "aws_s3_bucket" "query_log" {
  bucket        = local.bucket-name
  force_destroy = true
}

output "route53_logger_id" {
  value = aws_route53_resolver_query_log_config.config.id
}

output "display" {
  value = format("Route53 query log config %s is ready", aws_route53_resolver_query_log_config.config.name)
}
