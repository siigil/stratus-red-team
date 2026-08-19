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
  resource_prefix = "stratus-red-team-rvfl" # stratus red team remove vpc flow logs
}


resource "google_compute_network" "vpc" {
  name                    = "${local.resource_prefix}-vpc-${var.correlation.short}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${local.resource_prefix}-subnet-${var.correlation.short}"
  ip_cidr_range = "10.10.0.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc.id

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

output "subnet_name" {
  value = google_compute_subnetwork.subnet.name
}

output "region" {
  value = google_compute_subnetwork.subnet.region
}

output "display" {
  value = format("Subnet %s in region %s with VPC flow logs enabled", google_compute_subnetwork.subnet.name, google_compute_subnetwork.subnet.region)
}
