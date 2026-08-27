package entra_id

import (
	"context"
	_ "embed"
	"fmt"
	"log"
	"time"

	"github.com/datadog/stratus-red-team/v2/pkg/stratus"
	"github.com/datadog/stratus-red-team/v2/pkg/stratus/mitreattack"
	msgraphsdk "github.com/microsoftgraph/msgraph-sdk-go"
	graphcore "github.com/microsoftgraph/msgraph-sdk-go-core"
	graphidentitygovernance "github.com/microsoftgraph/msgraph-sdk-go/identitygovernance"
	graphmodels "github.com/microsoftgraph/msgraph-sdk-go/models"
)

const (
	assignmentRemovalPollInterval = 5 * time.Second
	assignmentRemovalTimeout      = 3 * time.Minute
)

//go:embed main.tf
var tf []byte

func init() {
	const codeBlock = "```"
	stratus.GetRegistry().RegisterAttackTechnique(&stratus.AttackTechnique{
		ID:           "entra-id.privilege-escalation.access-package-group",
		FriendlyName: "Escalate to Entra ID role-assignable group using access package",
		Description: `
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
- RoleAssignmentSchedule.ReadWrite.Directory
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

Detonation:
- Provide the MyAccess Portal URL where the configured user can request the access package to demonstrate group membership assignment and escalation to Global Administrator

References:
- https://learn.microsoft.com/en-us/entra/id-governance/entitlement-management-overview
- https://github.com/hashicorp/terraform-provider-azuread/issues/1069
`,
		Detection: `
Sample [Entra ID audit logs](https://learn.microsoft.com/en-us/entra/identity/monitoring-health/concept-audit-logs) to monitor:

` + codeBlock + `json hl_lines="4 14"
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
` + codeBlock + `
`,
		Platform:                   stratus.EntraID,
		IsIdempotent:               true,
		IsSlow:                     false,
		MitreAttackTactics:         []mitreattack.Tactic{mitreattack.PrivilegeEscalation},
		PrerequisitesTerraformCode: tf,
		Detonate:                   detonate,
		Revert:                     revert,
	})
}

func detonate(params map[string]string, providers stratus.CloudProviders) error {
	log.Println("Starting technique execution")

	domain := params["domain"]
	accessPackageID := params["access_package_id"]
	targetUserName := params["target_user_name"]
	requestURL := fmt.Sprintf("https://myaccess.microsoft.com/@%s#/access-packages/%s", domain, accessPackageID)

	log.Printf("Request the access package as %s to demonstrate escalation to Global Administrator via group membership:\n\n  %s", targetUserName, requestURL)

	log.Println("Technique execution completed")
	return nil
}

func revert(params map[string]string, providers stratus.CloudProviders) error {
	ctx := context.Background()
	accessPackageID := params["access_package_id"]
	graphClient := providers.EntraId().GetGraphClient()

	log.Printf("Listing active assignments for access package %s", accessPackageID)
	assignments, err := listActiveAssignments(ctx, graphClient, accessPackageID)
	if err != nil {
		return fmt.Errorf("failed to list active access package assignments: %w", err)
	}

	if len(assignments) == 0 {
		log.Println("No active access package assignments found")
		return nil
	}

	for _, assignment := range assignments {
		assignmentID := assignment.GetId()
		if assignmentID == nil || *assignmentID == "" {
			return fmt.Errorf("failed to remove access package assignment: assignment has no ID")
		}

		log.Printf("Removing access package assignment %s", *assignmentID)
		requestBody := graphmodels.NewAccessPackageAssignmentRequest()
		requestType := graphmodels.ADMINREMOVE_ACCESSPACKAGEREQUESTTYPE
		requestBody.SetRequestType(&requestType)

		assignmentToRemove := graphmodels.NewAccessPackageAssignment()
		assignmentToRemove.SetId(assignmentID)
		requestBody.SetAssignment(assignmentToRemove)

		_, err = graphClient.IdentityGovernance().EntitlementManagement().AssignmentRequests().Post(ctx, requestBody, nil)
		if err != nil {
			return fmt.Errorf("failed to request removal of access package assignment %s: %w", *assignmentID, err)
		}
	}

	log.Println("Waiting for active access package assignments to be removed")
	waitCtx, cancel := context.WithTimeout(ctx, assignmentRemovalTimeout)
	defer cancel()

	for {
		assignments, err = listActiveAssignments(waitCtx, graphClient, accessPackageID)
		if err != nil {
			return fmt.Errorf("failed to check active access package assignments: %w", err)
		}
		if len(assignments) == 0 {
			log.Println("All active access package assignments removed")
			return nil
		}

		select {
		case <-waitCtx.Done():
			return fmt.Errorf("timed out waiting for %d active access package assignment(s) to be removed: %w. Try reverting again.", len(assignments), waitCtx.Err())
		case <-time.After(assignmentRemovalPollInterval):
		}
	}
}

func listActiveAssignments(ctx context.Context, graphClient *msgraphsdk.GraphServiceClient, accessPackageID string) ([]*graphmodels.AccessPackageAssignment, error) {
	filter := fmt.Sprintf("accessPackage/id eq '%s'", accessPackageID)
	response, err := graphClient.IdentityGovernance().EntitlementManagement().Assignments().Get(ctx, &graphidentitygovernance.EntitlementManagementAssignmentsRequestBuilderGetRequestConfiguration{
		QueryParameters: &graphidentitygovernance.EntitlementManagementAssignmentsRequestBuilderGetQueryParameters{
			Filter: &filter,
		},
	})
	if err != nil {
		return nil, err
	}

	iterator, err := graphcore.NewPageIterator[*graphmodels.AccessPackageAssignment](response, graphClient.GetAdapter(), graphmodels.CreateAccessPackageAssignmentCollectionResponseFromDiscriminatorValue)
	if err != nil {
		return nil, err
	}

	activeAssignments := make([]*graphmodels.AccessPackageAssignment, 0)
	err = iterator.Iterate(ctx, func(assignment *graphmodels.AccessPackageAssignment) bool {
		if isActiveAssignment(assignment) {
			activeAssignments = append(activeAssignments, assignment)
		}
		return true
	})
	if err != nil {
		return nil, err
	}

	return activeAssignments, nil
}

func isActiveAssignment(assignment *graphmodels.AccessPackageAssignment) bool {
	state := assignment.GetState()
	if state == nil {
		return false
	}

	switch *state {
	case graphmodels.DELIVERING_ACCESSPACKAGEASSIGNMENTSTATE,
		graphmodels.PARTIALLYDELIVERED_ACCESSPACKAGEASSIGNMENTSTATE,
		graphmodels.DELIVERED_ACCESSPACKAGEASSIGNMENTSTATE:
		return true
	default:
		return false
	}
}
