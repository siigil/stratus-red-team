terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.18.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.3.2"
    }
  }
}

locals {
  resource_prefix = "stratus-red-team-ddl" # stratus red team delete dns logs
}


resource "google_dns_policy" "logging_policy" {
  name           = "${local.resource_prefix}-policy-${var.correlation.short}"
  enable_logging = true

  networks {
    network_url = google_compute_network.vpc.id
  }
}

resource "google_compute_network" "vpc" {
  name                    = "${local.resource_prefix}-vpc-${var.correlation.short}"
  auto_create_subnetworks = false
}

output "policy_name" {
  value = google_dns_policy.logging_policy.name
}

output "display" {
  value = format("Cloud DNS policy %s with query logging enabled", google_dns_policy.logging_policy.name)
}
