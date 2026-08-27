---
title: Escalate to Entra ID role-assignable group using access package
---

# Escalate to Entra ID role-assignable group using access package


 <span class="smallcaps w3-badge w3-blue w3-round w3-text-white" title="This attack technique can be detonated multiple times">idempotent</span> 

Platform: Entra ID

## Mappings

- MITRE ATT&CK
    - Privilege Escalation



## Description


Escalates a user to the Global Administrator Entra ID role using eligible group membership through an access package that does not require approvals.

Roles allowing Entra ID administration are generally not available for assignment in access packages. However, role-assignable security groups allowing Entra ID administrative role assignment are still allowed.

**Licensing:** This technique requires Entra ID Governance licensing.

Requirements:
Before running this technique, you will need to create an SP as a Global Administrator account and designate an account you will make the access request from:
1. [Create an app registration and service principal](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app) (SP)
2. [Add the following](https://learn.microsoft.com/en-us/entra/identity-platform/howto-add-app-roles-in-apps#assign-app-roles-to-applications) Microsoft Graph application permissions to the app registration:
- EntitlementManagement.ReadWrite.All
- Group.ReadWrite.All
- User.ReadWrite.All
- RoleManagement.ReadWrite.Directory
3. Select "Grant consent for [Directory Name]" to consent to all permissions
4. [Add a secret](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials?tabs=client-secret) to the application
5. Log the Azure CLI out of your current user account:
<code>
az logout
</code>
6. Copy the app registration's secret, client ID, and your tenant ID and sign in as the SP on the command line:
<code>
az login \
  --service-principal \
  --allow-no-subscriptions \
  --username "$APP_ID" \
  --password "$CLIENT_SECRET" \
  --tenant "$TENANT_ID"
</code>
7. Configure the STRATUS_RED_TEAM_ATTACKER_ACCOUNT variable:
<code>
export STRATUS_RED_TEAM_ATTACKER_ACCOUNT="[USER@DOMAIN.ONMICROSOFT.COM]"
</code>
8. Delete the app registration once testing has completed

Warmup:
- Create a role-assignable security group
- Assign the "Global Administrator" role to the group
- Create an Entra ID catalog and access package with group membership assignment
- Configure the access package policy to allow the configured user (<code>STRATUS_RED_TEAM_ATTACKER_ACCOUNT</code>) to request assignment and not require approval

<span style="font-variant: small-caps;">Detonation</span>:
- Provide the MyAccess Portal URL where the configured user can request the access package to demonstrate group membership assignment and escalation to Global Administrator

References:
- https://learn.microsoft.com/en-us/entra/id-governance/entitlement-management-overview
- https://github.com/hashicorp/terraform-provider-azuread/issues/1069


## Instructions

```bash title="Detonate with Stratus Red Team"
stratus detonate entra-id.privilege-escalation.access-package-group
```
## Detection


Sample [Entra ID audit logs](https://learn.microsoft.com/en-us/entra/identity/monitoring-health/concept-audit-logs) to monitor:

```json hl_lines="4 14"
{
  "category": "EntitlementManagement",
  "result": "success",
  "activityDisplayName": "User requests access package assignment",
  "activityDateTime": "2026-08-27T13:36:36.512743Z",
  "loggedByService": "Entitlement Management",
  "operationType": "CreateEntitlementGrantUserAddRequest",
  "targetResources": [REMOVED]
}

{
  "category": "EntitlementManagement",
  "result": "success",
  "activityDisplayName": "Auto approve access package assignment request",
  "activityDateTime": "2026-08-27T13:28:45.223011Z",
  "loggedByService": "Entitlement Management",
  "operationType": "AutoApproveEntitlementGrantRequest",
  "targetResources": [REMOVED]
}
```


