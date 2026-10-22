# References & Verification Ledger

Every procedure in this guide was checked against official Microsoft documentation before
being written. The ledger below maps each procedure to its supporting page, required
permission/license, and documented limitation.

## Verification Ledger

| Procedure | Official page | Permission / license | Documented limitation |
|---|---|---|---|
| Graph PowerShell authentication | [Get started with the Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/get-started) | Delegated scopes per exercise | Consent is separate from the operator's Entra role |
| Bulk user creation | [New-MgUser](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users/new-mguser?view=graph-powershell-1.0) | `User.ReadWrite.All` | UPN suffix must be a verified domain |
| Add group members via Graph | [Add members (group)](https://learn.microsoft.com/en-us/graph/api/group-post-members?view=graph-rest-1.0) | `Group.ReadWrite.All` | `@odata.id` reference body required |
| Remove group membership via Graph | [Remove member (group)](https://learn.microsoft.com/en-us/graph/api/group-delete-members?view=graph-rest-1.0) | `Group.ReadWrite.All` | `DELETE /groups/{id}/members/{directoryObjectId}/$ref` |
| Dynamic membership rules | [Manage rules for dynamic membership groups](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-membership) | P1 per unique dynamic-group user | Processing is asynchronous; 15,000 dynamic groups per tenant |
| Dynamic groups via Graph | [Manage groups in Microsoft Graph](https://learn.microsoft.com/en-us/graph/api/resources/groups-overview?view=graph-rest-1.0) | `Group.ReadWrite.All` | Requires `DynamicMembership` groupTypes value |
| AU-scoped role assignment | [Assign Microsoft Entra roles — AU scope](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-assign-powershell) | P1 per AU administrator; Privileged Role Administrator | Only listed roles support AU scope; admin-target actions restricted |
| Portal role assignment | [Assign Microsoft Entra roles (portal)](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/manage-roles-portal) | Varies by role | — |
| Role-assignable groups | [Use Microsoft Entra groups to manage role assignments](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-concept) | P1 (PIM for groups: P2) | Dynamic groups cannot be role-assignable |
| Built-in role permissions | [Microsoft Entra built-in roles permissions reference](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference) | — | Custom-role permission strings defined here |
| Custom-role permission strings | [Enterprise application permissions for custom roles](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-enterprise-app-permissions) | Privileged Role Administrator to create | `auditLogs` and `signInReports` — not `signInLogs` |
| PIM licensing | [PIM license requirements](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/subscription-requirements) | P2 or Governance | Eligible users, approvers, and reviewers all need licenses |
| PIM assignments | [Assign Microsoft Entra roles in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-add-role-to-user) | Privileged Role Administrator | Eligible/active, permanent or time-bound |
| PIM role settings | [Configure Microsoft Entra role settings in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings) | Privileged Role Administrator | Activation max 1–24 h; MFA is once per session |
| PIM activation | [Activate a Microsoft Entra role in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-activate-role) | Eligible assignment | MFA once per session; scope selection recommended |
| PIM approvals | [Approve or deny requests for Microsoft Entra roles](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-approval-workflow) | Designated approver | 24-hour approval window (not configurable); no self-approval |
| PIM via Graph | [Update rules in PIM by using Microsoft Graph](https://learn.microsoft.com/en-us/graph/how-to-pim-update-rules) | `RoleManagementPolicy.ReadWrite.Directory` | Policy rule IDs per rule type |
| PIM eligible-assignment removal | [Create roleEligibilityScheduleRequest](https://learn.microsoft.com/en-us/graph/api/rbacapplication-post-roleeligibilityschedulerequests?view=graph-rest-1.0) | `RoleEligibilitySchedule.Remove.Directory` | `action: AdminRemove`; async. Lab procedure: portal (docs/07 step 3) |
| PIM active-assignment removal | [Manage Microsoft Entra role assignments using the PIM APIs](https://learn.microsoft.com/en-us/graph/api/resources/privilegedidentitymanagementv3-overview?view=graph-rest-1.0) | `RoleAssignmentSchedule.Remove.Directory` | `roleAssignmentScheduleRequests` with `AdminRemove`; async. Lab procedure: portal (docs/07 step 3) |
| App properties | [Properties of an enterprise application](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/application-properties) | — | GA bypasses assignment-required; visibility ≠ authorization |
| App assignment | [Manage users and groups assignment to an application](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/assign-user-or-group-access-portal) | `AppRoleAssignment.ReadWrite.All` | Group assignment requires P1 |
| Gallery test app | [Configure Microsoft Entra SAML Toolkit for single sign-on](https://learn.microsoft.com/en-us/entra/identity/saas-apps/saml-toolkit-tutorial) | Cloud Application Administrator to add | Assignment exercise works without SSO setup; sign-in validation requires it |
| App role assignment cmdlet | [New-MgUserAppRoleAssignment](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.applications/new-mguserapproleassignment?view=graph-powershell-1.0) | `AppRoleAssignment.ReadWrite.All` | Default app role ID is all-zeros when no roles declared |
| App role assignment removal | [Delete appRoleAssignment](https://learn.microsoft.com/en-us/graph/api/user-delete-approleassignments?view=graph-rest-1.0) | `AppRoleAssignment.ReadWrite.All` | User Administrator explicitly among supported least-privileged roles |
| Access management | [What is access management?](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/what-is-access-management) | — | Assignment-required applies to SAML/OIDC/OAuth2/WS-Fed/App Proxy |
| Access reviews overview | [What are access reviews?](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-overview) | Governance (some P2) | Reviewers and reviewed users both need licenses |
| Create access review | [Create an access review of groups and applications](https://learn.microsoft.com/en-us/entra/id-governance/create-access-review) | Identity Governance Administrator / User Administrator | Auto-apply warning when reviewers don't respond |
| Complete access review | [Complete an access review](https://learn.microsoft.com/en-us/entra/id-governance/complete-access-review) | — | Decisions don't change dynamic-group membership; removal takes minutes |
| App review preparation | [Preparing for an access review of users' access to an application](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-application-preparation) | P2 or Governance | Review assignments vs groups per app architecture |
| My Access reviews | [Self-review of access packages and resources](https://learn.microsoft.com/en-us/entra/id-governance/self-access-review) | — | Removal happens when the review ends, not immediately |
| Emergency access revocation | [Revoke user access in an emergency](https://learn.microsoft.com/en-us/entra/identity/users/users-revoke-access) | User Administrator | Documented order: disable first, then revoke sessions |
| Session revocation cmdlet | [Revoke-MgUserSignInSession](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users.actions/revoke-mgusersigninsession?view=graph-powershell-1.0) | `User.RevokeSessions.All` | Refresh tokens + cookies; minutes of delay; not app sessions |
| revokeSignInSessions API | [user: revokeSignInSessions](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0) | `User.RevokeSessions.All` | Access tokens may persist until expiry |
| Governance licensing | [Microsoft Entra ID Governance licensing fundamentals](https://learn.microsoft.com/en-us/entra/id-governance/licensing-fundamentals) | — | Governance products require AAD_PREMIUM/P2 prerequisite plans |

## Training Modules

- [Use dynamic group membership and filters in Microsoft Entra ID](https://learn.microsoft.com/training/modules/configure-entraid-device-management/06-dynamic-groups-filters)

## License-overview Sources

- [Microsoft Entra licensing](https://learn.microsoft.com/en-us/entra/fundamentals/licensing)

---

Back to: [README](../README.md)
