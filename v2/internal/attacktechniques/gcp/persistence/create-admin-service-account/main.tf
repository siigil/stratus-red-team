terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.3.2"
    }
  }
}

locals {
  resource_prefix = "srt-casa" # stratus red team create admin service account
}


output "service_account_name" {
  value = format("%s-sa-%s", local.resource_prefix, var.correlation.short)
}
