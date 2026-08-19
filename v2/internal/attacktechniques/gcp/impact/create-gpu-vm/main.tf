terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.18.1"
    }
  }
}


output "suffix" {
  value = var.correlation.short
}

output "display" {
  value = "Ready to create a GPU-enabled GCE instance"
}
