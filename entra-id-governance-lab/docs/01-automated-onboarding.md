# Phase 1 — Automated Onboarding (PowerShell + Microsoft Graph)

> Phase series: [0](00-prerequisites-and-verification.md) · [1](01-automated-onboarding.md) · [2](02-dynamic-membership.md) · [3](03-administrative-units.md) · [4](04-pim-and-role-governance.md) · [5](05-enterprise-application-access.md) · [6](06-access-reviews.md) · [7](07-offboarding-and-cleanup.md)

## Objective & Scope

Provision the 20-contractor identity cohort from a structured CSV using Microsoft Graph
PowerShell — with standardized attributes, randomized temporary passwords that must be changed
at first sign-in, and color-coded execution telemetry.

**Scope:** scope selection and consent, parent group verification, bulk user creation loop,
status logging. Role assignment happens in Phases 3–4.

## Prerequisites

- [Phase 0](00-prerequisites-and-verification.md) completed.
- Operator role: **User Administrator** (or Global Administrator in the lab tenant).
- Delegated Graph scopes for this exercise: `User.ReadWrite.All`, `Group.ReadWrite.All`.
- `data/contractors.csv` prepared and reviewed.

## Design Decisions (and corrections to the source breakdown)

| Decision | Rationale |
|---|---|
| Scopes requested per exercise | `Directory.ReadWrite.All` is not minimum privilege for user creation; missing scopes fail with HTTP 403 mid-run |
| Delegated permissions via `Connect-MgGraph -Scopes` | Operates as the signed-in operator; consent is separate from your Entra role |
| `ForceChangePasswordNextSignIn = $true` | Entra ID intercepts the first sign-in and mandates a password change |
| Temporary passwords never logged | The script's report contains UPNs and status only — no secrets |
| `Specialty` stays CSV-only | There is no standard Entra user property for it; it feeds the role-mapping logic later |
| Static parent group, not dynamic | A dynamic group is not a container that prevents orphan users; the static group gives explicit, reviewable membership |

## Step-by-Step Execution

### 1. Authenticate with the required scopes

```powershell
Connect-MgGraph -TenantId $TenantId `
  -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All' -NoWelcome
```

During interactive sign-in, Microsoft Entra ID prompts the operator to consent to the requested
**delegated permissions**. If scopes are omitted, API authorization calls fail mid-execution
with `403 Forbidden` when the script writes directory objects.

### 2. Verify (or create) the parent group

```powershell
$group = Get-MgGroup -Filter "displayName eq 'Cyber Security Contractors'" -Top 1
if (-not $group) {
    $group = New-MgGroup -DisplayName 'Cyber Security Contractors' `
        -Description 'Parent group for cyber security contractor cohort' `
        -MailEnabled:$false -MailNickname 'csc-contractors' `
        -SecurityEnabled -GroupTypes @()
}
```

The script checks for the target group and for existing UPNs before the creation loop, so
re-runs are safe and **repair missing group memberships** for users created earlier.

> **Note:** group members are added with the documented `@odata.id` reference body
> (`New-MgGroupMemberByRef -GroupId <id> -BodyParameter @{ '@odata.id' =
> 'https://graph.microsoft.com/v1.0/directoryObjects/<object-id>' }`), per
> [Add members (Microsoft Graph)](https://learn.microsoft.com/en-us/graph/api/group-post-members?view=graph-rest-1.0).

### 3. Run the bulk creation loop

Run the prepared script:

```powershell
.\scripts\01-Bulk-Create-Contractors.ps1 `
  -TenantId $TenantId `
  -PrimaryDomain 'beginningdimension.com' `
  -CsvPath '.\data\contractors.csv'
```

What each iteration does (see the script for the full source):

1. Builds the UPN (`first.last@domain`) and checks for collisions — existing UPNs are
   **skipped** (yellow), not overwritten.
2. Generates a randomized 16-character temporary password.
3. Creates the user with the CSV attributes:

```powershell
$passwordProfile = @{
    Password                      = $password
    ForceChangePasswordNextSignIn = $true
}

New-MgUser -DisplayName "$givenName $surname" `
    -GivenName $givenName -Surname $surname `
    -UserPrincipalName $upn `
    -AccountEnabled:$true `
    -JobTitle $row.JobTitle `
    -Department $row.Department `
    -CompanyName $row.CompanyName `
    -MailNickname ($upn -split '@')[0] `
    -UsageLocation 'PT' `
    -PasswordProfile $passwordProfile
```

4. Adds the user to the parent group (`New-MgGroupMemberByRef`).
5. Emits color-coded telemetry — green for created, yellow for skipped (UPN collision),
   red for failed — and writes a status CSV report (no passwords).

### 4. Deliver initial credentials securely

Communicate temporary passwords through a secure out-of-band channel. When each contractor
first signs in (for example at `myapps.microsoft.com`), Entra ID intercepts the session and
mandates a password change before access is granted.

> **Operational note:** the script deliberately does not retain the generated passwords —
> you cannot "look them up later." If a temporary password is lost before first sign-in,
> reset it as the administrator (portal: **Users > [user] > Reset password**, or
> `Update-MgUser -PasswordProfile`).

## Validation

- [ ] The summary reports `Created: 20` (or expected skip/repair counts on re-run).
- [ ] `Get-MgUser -Filter "department eq 'Cyber Security Contractors'"` returns 20 users.
- [ ] Each user shows `JobTitle`, `Department`, `CompanyName` matching the CSV.
- [ ] The parent group contains 20 members.
- [ ] A test sign-in forces the password change (do not publish the password anywhere).

## Evidence to Capture

- The script's color-coded console summary (passwords never visible).
- Entra admin center user list filtered to the contractor department.
- One user's profile page showing attributes (redact any sensitive values).

## References

- [New-MgUser (Microsoft.Graph.Users)](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users/new-mguser?view=graph-powershell-1.0)
- [Get started with the Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/get-started)
- [Assign users and groups to an application](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/assign-user-or-group-access-portal)

Next: [Phase 2 — Dynamic Membership](02-dynamic-membership.md)
