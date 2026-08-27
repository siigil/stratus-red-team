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
  resource_prefix = "stratus-red-team-mvns" # modify vertex notebook startup
}


resource "google_compute_network" "vpc" {
  name                    = "${local.resource_prefix}-vpc-${var.correlation.short}"
  auto_create_subnetworks = true
}

resource "google_workbench_instance" "notebook" {
  name     = "${local.resource_prefix}-${var.correlation.short}"
  location = "us-central1-a"

  gce_setup {
    machine_type = "e2-standard-2"

    boot_disk {
      disk_size_gb = 150
    }

    network_interfaces {
      network = google_compute_network.vpc.self_link
    }
  }
}

output "instance_name" {
  value = google_workbench_instance.notebook.name
}

output "location" {
  value = google_workbench_instance.notebook.location
}

output "display" {
  value = format("Vertex AI Workbench instance %s in %s ready", google_workbench_instance.notebook.name, google_workbench_instance.notebook.location)
}
