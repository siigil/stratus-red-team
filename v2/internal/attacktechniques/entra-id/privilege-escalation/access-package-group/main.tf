terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "2.53.1"
    }
    external = {
      source = "hashicorp/external"
    }
  }
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Initialize + Random
# # # # # # # # # # # # # # # # # # # # # # # # # # # # #
data "azuread_domains" "default" {
  only_initial = true
}

data "azuread_client_config" "current" {}

locals {
  resource_prefix = "srt-eapg" # stratus red team entra access package group
  domain_name     = data.azuread_domains.default.domains.0.domain_name
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# User Data
# NOTE: If the STRATUS_RED_TEAM_ATTACKER_ACCOUNT env var is unset during execution,
# this may cause an error in cleanup. However, this does not seem likely to be frequent.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Fetch user to apply policy to
data "external" "stratus_account" {
  program = [
    "bash", "-c",
    "if [ -z \"$STRATUS_RED_TEAM_ATTACKER_ACCOUNT\" ]; then echo 'STRATUS_RED_TEAM_ATTACKER_ACCOUNT must be set to the UPN of an existing Entra ID user. Use export STRATUS_RED_TEAM_ATTACKER_ACCOUNT=[ACCOUNT NAME] to set.' >&2; exit 1; fi; jq -n --arg upn \"$STRATUS_RED_TEAM_ATTACKER_ACCOUNT\" '{upn: $upn}'"
  ]
}

# Fetch details from Entra
data "azuread_user" "user" {
  user_principal_name = data.external.stratus_account.result.upn
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Role-Assignable Group + Role Assignment
# # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Role-assignable security group that will hold the Global Administrator role
resource "azuread_group" "target" {
  display_name       = "${local.resource_prefix}-group-${random_string.suffix.result}"
  security_enabled   = true
  assignable_to_role = true
}

resource "azuread_directory_role" "ga" {
  display_name = "Global Administrator"
}

# Assign the Global Administrator role to the group
resource "azuread_directory_role_assignment" "group_ga" {
  role_id             = azuread_directory_role.ga.id
  principal_object_id = azuread_group.target.object_id
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Catalog + Access Package (group membership assignment)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # #

resource "azuread_access_package_catalog" "catalog" {
  display_name = "${local.resource_prefix}-catalog-${random_string.suffix.result}"
  description  = "Stratus Red Team access package catalog"
}

resource "azuread_access_package" "package" {
  catalog_id   = azuread_access_package_catalog.catalog.id
  display_name = "${local.resource_prefix}-access-package-${random_string.suffix.result}"
  description  = "Stratus Red Team access package granting role-assignable group membership"
}

# Add the role-assignable group to the catalog as an assignable resource
resource "azuread_access_package_resource_catalog_association" "group" {
  catalog_id             = azuread_access_package_catalog.catalog.id
  resource_origin_id     = azuread_group.target.object_id
  resource_origin_system = "AadGroup"
}

# Grant membership of the group through the access package
resource "azuread_access_package_resource_package_association" "group" {
  access_package_id               = azuread_access_package.package.id
  catalog_resource_association_id = azuread_access_package_resource_catalog_association.group.id
  access_type                     = "Member"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Assignment Policy (current user may request, no approval)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # #

resource "azuread_access_package_assignment_policy" "policy" {
  access_package_id = azuread_access_package.package.id
  display_name      = "${local.resource_prefix}-policy-${random_string.suffix.result}"
  description       = "Allows the current user to request assignment without approval"
  duration_in_days  = 365

  requestor_settings {
    requests_accepted = true
    scope_type        = "SpecificDirectorySubjects"

    requestor {
      object_id    = data.azuread_user.user.object_id
      subject_type = "singleUser"
    }
  }

  approval_settings {
    approval_required = false
  }
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Output
# # # # # # # # # # # # # # # # # # # # # # # # # # # # #

output "group_id" {
  value = azuread_group.target.object_id
}

output "access_package_id" {
  value = azuread_access_package.package.id
}

output "target_user_name" {
  value = data.azuread_user.user.user_principal_name
}

output "domain" {
  value = data.azuread_domains.default.domains.0.domain_name
}

output "display" {
  value = format(
    "Existing user %s is eligible to request membership in role-assignable group %s (Global Administrator) through access package %s without approval.",
    data.azuread_user.user.user_principal_name,
    azuread_group.target.display_name,
    azuread_access_package.package.display_name
  )
}
