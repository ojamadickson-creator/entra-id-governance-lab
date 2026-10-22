# Phase 5 — Enterprise Application Governance & Access Provisioning

> Phase series: [0](00-prerequisites-and-verification.md) · [1](01-automated-onboarding.md) · [2](02-dynamic-membership.md) · [3](03-administrative-units.md) · [4](04-pim-and-role-governance.md) · [5](05-enterprise-application-access.md) · [6](06-access-reviews.md) · [7](07-offboarding-and-cleanup.md)

## Objective & Scope

Govern enterprise application access: configure the three foundational application properties,
bulk-assign the cohort with hash-table-cached Graph lookups, and validate the My Apps
experience.

**Scope:** application property configuration, app role assignments (PowerShell with caching),
and My Apps portal behavior.

## Prerequisites

- [Phase 1](01-automated-onboarding.md) completed; operator holds **Cloud Application
  Administrator** (or Application Administrator).
- Delegated Graph scopes: `AppRoleAssignment.ReadWrite.All`, `Application.Read.All`,
  `User.Read.All`.
- At least one enterprise application in the tenant. For a reproducible lab exercise, add the
  **Microsoft Entra SAML Toolkit** gallery app (**Enterprise apps > New application**), a
  sample SAML app Microsoft publishes specifically for testing SSO integration
  ([Configure Microsoft Entra SAML Toolkit for single sign-on](https://learn.microsoft.com/en-us/entra/identity/saas-apps/saml-toolkit-tutorial)).
  The assignment exercise (properties, app role assignment, My Apps tile) works without the
  app-side SSO configuration, but the sign-in *validation* in step 6 requires the SSO setup
  steps in section 5 below.

## The Three Foundational Properties

Configured on the application's **Properties** page
([Properties of an enterprise application](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/application-properties)):

| Property | Effect |
|---|---|
| **Enabled for users to sign in?** | Master kill-switch: `No` blocks all user sign-in and restricts service principals using application permissions — even for assigned users. Maps to the service principal's `accountEnabled`. |
| **Assignment required?** | When `Yes`, only assigned users/groups (and applications) can obtain access tokens. Applies to SAML/OIDC/OAuth 2.0/WS-Fed/App Proxy apps. Global Administrators bypass it. |
| **Visible to users?** | Controls tile rendering on the My Apps portal (`myapps.microsoft.com`). **Visibility is not authorization** — hiding a tile does not revoke access. |

For the lab app: set **Enabled for users to sign in = Yes**, **Assignment required = Yes**, and
**Visible to users = Yes**.

## Target Application Categories (scenario context)

| Function | Applications | Note |
|---|---|---|
| IAM | Entra ID Governance portal, My Apps | Governance console; end-user launchpad |
| SOC | Microsoft Sentinel, Defender for Endpoint | SIEM / EDR — their portals and licensing are separate from this exercise |
| GRC | Microsoft Purview, Compliance Manager | Compliance monitoring |
| Cloud security | Defender for Cloud, Defender for Cloud Apps | Posture management / CASB |

> These enterprise services are listed as the scenario's target categories. For the *lab
> exercise itself*, use a gallery/test application — the assignment mechanics
> (properties, app role assignment, My Apps) are identical and do not depend on owning the
> underlying service licenses.

## Step-by-Step Execution

### 1. Configure the application properties

Portal: **Entra ID > Enterprise apps > [your lab app] > Properties** — set the three toggles
per the table above and **Save**.

### 2. Resolve the identifiers (PrincipalId, ResourceId, AppRoleId)

An app role assignment needs three stable identifiers — never manufacture them from display
names alone:

```powershell
$sp = Get-MgServicePrincipal -Filter "displayName eq 'Microsoft Entra SAML Toolkit'" -Top 1
$sp.Id                      # ResourceId
$sp.AppRoles                # declared app roles, if any
```

If the application exposes no app roles, the **default app role ID**
`00000000-0000-0000-0000-000000000000` signals assignment to the resource app without a
specific role
([New-MgUserAppRoleAssignment](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.applications/new-mguserapproleassignment?view=graph-powershell-1.0)).

### 3. Bulk-assign with hash-table caching

Direct Graph lookups inside a loop add latency and risk HTTP 429 throttling. Pre-resolve
lookups into in-memory hash tables, then POST assignments with cached IDs:

```powershell
# Pre-resolve service principals and users into caches
$spCache   = @{}
Get-MgServicePrincipal -All | ForEach-Object { $spCache[$_.Id] = $_.DisplayName }

$userCache = @{}
Get-MgUser -All | ForEach-Object { $userCache[$_.UserPrincipalName.ToLowerInvariant()] = $_.Id }

# Assignment loop using cached Object IDs
$params = @{
    PrincipalId = $userCache['sofia.santos@beginningdimension.com']
    ResourceId  = $sp.Id
    AppRoleId   = '00000000-0000-0000-0000-000000000000'
}
New-MgUserAppRoleAssignment -UserId $userCache['sofia.santos@beginningdimension.com'] `
    -BodyParameter $params
```

The complete implementation (with skip/failure handling and summaries) is in
`scripts/05-Assign-UsersToApp.ps1`:

```powershell
.\scripts\05-Assign-UsersToApp.ps1 -TenantId $TenantId `
  -AppDisplayName 'Microsoft Entra SAML Toolkit' `
  -UserUpns @('sofia.santos@beginningdimension.com','marcus.reyes@beginningdimension.com')
```

Accuracy note: caching eliminates redundant **read** queries; the assignment POSTs can still be
throttled under load — production scripts should implement retry with backoff.

### 4. Group-based assignment alternative

Assigning a group (including the Phase 2 dynamic groups) to the application maps access for
every current member — this requires a **P1** license
([Manage access to apps](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/what-is-access-management)):

```powershell
$groupParams = @{
    PrincipalId = $groupId                 # the GROUP's object ID, not a user's
    ResourceId  = $sp.Id
    AppRoleId   = '00000000-0000-0000-0000-000000000000'
}
New-MgGroupAppRoleAssignment -GroupId $groupId -BodyParameter $groupParams
```

### 5. Configure SSO for the exercise (Microsoft Entra SAML Toolkit)

To actually prove sign-in behavior, complete the application-side configuration from the
official tutorial
([Configure Microsoft Entra SAML Toolkit for single sign-on](https://learn.microsoft.com/en-us/entra/identity/saas-apps/saml-toolkit-tutorial)):

1. On the app's **Single sign-on** page, select **SAML** and edit **Basic SAML Configuration**:
   Reply URL `https://samltoolkit.azurewebsites.net/SAML/Consume`, Sign on URL
   `https://samltoolkit.azurewebsites.net/`. (The **Identifier** is filled later from the
   toolkit's own configuration page.)
2. Under **SAML Signing Certificate**, download **Certificate (Raw)**. From **Set up
   Microsoft Entra SAML Toolkit**, copy the **Login URL**, **Microsoft Entra Identifier**,
   and **Logout URL**.
3. On the SAML Toolkit website (`samltoolkit.azurewebsites.net`): register (or sign in),
   select **SAML Configuration** > **Create**, paste the three values from step 2 into their
   textboxes, upload the raw certificate via **Choose File**, and select **Create**.
4. Copy the generated **Sign-on URL**, **Identifier**, and **ACS URL** from the SSO
   configuration page, paste them into the corresponding **Basic SAML Configuration**
   fields, and save.

Without these steps the assignment exercise still works, but sign-in tests cannot succeed —
the My Apps tile would only show an error after launch.

### 6. Validate the My Apps experience

Sign in to `myapps.microsoft.com` as an assigned contractor: the app tile appears (Visible to
users + assignment). Launching it completes the SAML sign-on flow configured above.

**Negative test:** an unassigned contractor attempts the app sign-in flow and is blocked,
because Assignment required = Yes. Note that a *missing tile* is only proof of the visibility
setting — it is not proof of denied authentication. Confirm the denial from the app sign-in
attempt or the Entra sign-in logs (the blocked event), not from tile absence.

## Validation

- [ ] The lab app's Properties page shows the three toggles configured per the table.
- [ ] Assigned users appear under the app's **Users and groups**.
- [ ] `Get-MgUserAppRoleAssignment -UserId <id>` returns the created assignments.
- [ ] An assigned user sees the app tile in My Apps and completes the SAML sign-in flow.
- [ ] An unassigned user's app sign-in attempt is blocked (Assignment required = Yes),
      confirmed via the sign-in attempt or sign-in logs — not tile absence.

## Evidence to Capture

- The application's Properties page (three toggles visible).
- The bulk-assignment script summary output.
- My Apps portal showing the tile for an assigned user.

## References

- [Properties of an enterprise application](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/application-properties)
- [Manage users and groups assignment to an application](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/assign-user-or-group-access-portal)
- [New-MgUserAppRoleAssignment (Microsoft.Graph.Applications)](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.applications/new-mguserapproleassignment?view=graph-powershell-1.0)
- [What is access management?](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/what-is-access-management)
- [Configure Microsoft Entra SAML Toolkit for single sign-on](https://learn.microsoft.com/en-us/entra/identity/saas-apps/saml-toolkit-tutorial)

Next: [Phase 6 — Access Reviews](06-access-reviews.md)
