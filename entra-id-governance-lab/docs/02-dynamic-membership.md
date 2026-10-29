# Phase 2 — Dynamic Membership Groups

> Phase series: [0](00-prerequisites-and-verification.md) · [1](01-automated-onboarding.md) · [2](02-dynamic-membership.md) · [3](03-administrative-units.md) · [4](04-pim-and-role-governance.md) · [5](05-enterprise-application-access.md) · [6](06-access-reviews.md) · [7](07-offboarding-and-cleanup.md)

## Objective & Scope

Organize the contractor cohort with attribute-driven dynamic membership: create the dynamic
contractor group and the "IM Staff" group, refactor explicit equality chains into scalable
prefix matching, and verify rule evaluation through membership and audit logs.

**Scope:** dynamic group creation, rule syntax design, async processing behavior, verification.

## Prerequisites

- [Phase 1](01-automated-onboarding.md) completed — the 20 users exist with `Department` and
  `JobTitle` populated.
- **Licensing:** dynamic membership requires a Microsoft Entra ID P1 (or Intune for Education)
  license for each unique user in dynamic groups — you need enough licenses to cover all
  dynamic-group members ([Manage rules for dynamic membership groups](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-membership)).
- Delegated Graph scopes: `Group.ReadWrite.All` for group creation and membership checks;
  the step 5 attribute tests also call `Update-MgUser`, so reconnect with
  `User.ReadWrite.All` included before those tests.

## Rule Syntax

The dynamic evaluation engine compares user profile attributes against rule expressions.
The two operators used in this lab:

| Operator | Behavior |
|---|---|
| `-eq` | Exact string equality against a designated value |
| `-startsWith` | Prefix string matching |

Full operator reference (including `-ne`, `-not`, `-in`, and advanced rules):
[Manage rules for dynamic membership groups](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-membership).

## Step-by-Step Execution

### 1. Create the dynamic contractor group

Portal path: **Entra admin center > Groups > All groups > New group**, with
**Membership type = Dynamic User**, then enter the rule in the rule builder.

Graph PowerShell equivalent (also in `scripts/02-New-DynamicGroups.ps1`):

```powershell
$groupName = 'Cyber Security Contractors (Dynamic)'
$rule      = '(user.department -eq "Cyber Security Contractors")'

$existing = Get-MgGroup -Filter "displayName eq '$groupName'" -Top 1

if (-not $existing) {
    $dynGroup = New-MgGroup -DisplayName $groupName `
        -Description 'Dynamic security group for cyber security contractors' `
        -MailEnabled:$false `
        -MailNickname 'csc-dynamic' `
        -SecurityEnabled:$true `
        -GroupTypes @('DynamicMembership') `
        -MembershipRule $rule `
        -MembershipRuleProcessingState 'On'

    Write-Host "Created dynamic group: $($dynGroup.DisplayName) (Id: $($dynGroup.Id))" -ForegroundColor Green
} else {
    Write-Host "Dynamic group already exists: $($existing.DisplayName) (Id: $($existing.Id))" -ForegroundColor Yellow
}
```

Dynamic membership requires the `DynamicMembership` value in `groupTypes`, and the rule can be
paused/resumed via `membershipRuleProcessingState`
([Manage groups in Microsoft Graph](https://learn.microsoft.com/en-us/graph/api/resources/groups-overview?view=graph-rest-1.0)).

### 2. Build the IM Staff rule — explicit equality chain

The first iteration consolidates IAM personnel using explicit `-eq` chains joined by `-or`:

```text
(user.jobTitle -eq "Identity and Access Management Engineer") -or
(user.jobTitle -eq "IM Solutions Architect") -or
(user.jobTitle -eq "Identity Governance Analyst")
```

This works, but scales poorly: every new title requires editing the rule.

### 3. Refactor to prefix matching — scoped to the cohort

The refactored rule uses `-startsWith`:

```text
(user.department -eq "Cyber Security Contractors") -and (
    (user.jobTitle -startsWith "IM") -or
    (user.jobTitle -startsWith "Identity"))
```

This captures present and future titles ("IM Specialist", "IM Engineer", "Identity Architect",
"Identity Governance Analyst") without editing the rule. The `department` guard is important
in a real tenant: an unscoped `(user.jobTitle -startsWith "Identity")` would pull in every
matching user in the directory, not just the contractor cohort.

### 4. Wait for asynchronous processing, then verify membership

Dynamic engine processing runs in the background — attribute updates do not reflect
instantaneously. Allow a few minutes, then:

```powershell
$g = Get-MgGroup -Filter "displayName eq 'IM Staff'" -Top 1
Get-MgGroupMember -GroupId $g.Id -All
```

Expected: the four IAM identities (Marcus Reyes, Aisha Khan, Luis Ferreira, Ines Machado).

### 5. Test rule-driven add and remove

- **Attribute trigger:** update a user's `JobTitle` to a matching value — the background
  engine adds them to IM Staff.
- **Attribute removal:** change Marcus Reyes' `JobTitle` to "SOC Analyst" — the rule
  re-evaluates and the engine removes him from IM Staff.

```powershell
Update-MgUser -UserId marcus.reyes@beginningdimension.com -JobTitle 'SOC Analyst'
```

### 5b. Restore the test attribute

After the removal test, restore Marcus's IAM job title so the dynamic group returns to its
expected state for later phases:

```powershell
Update-MgUser -UserId marcus.reyes@beginningdimension.com -JobTitle 'Identity and Access Management Engineer'
```

### 6. Verify rule execution in audit logs

Confirm dynamic additions by checking the tenant audit logs (Entra admin center >
Entra ID > Audit logs) and filtering for the **Add member to group** activity. Dynamic
membership changes are recorded like any other membership change.

## Validation

- [ ] "Cyber Security Contractors (Dynamic)" contains all 20 contractors.
- [ ] "IM Staff" contains exactly the IAM-titled contractors.
- [ ] Changing a `JobTitle` adds/removes membership after async processing.
- [ ] Audit logs show "Add member to group" entries for the dynamic engine's changes.
- [ ] (Reminder) dynamic groups cannot be role-assignable groups
  ([Use Microsoft Entra groups to manage role assignments](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-concept)).

## Evidence to Capture

- Group Overview page showing **Membership type: Dynamic User** and the rule.
- IM Staff Members list showing the IAM subset.
- Audit log filtered to "Add member to group".

## References

- [Manage rules for dynamic membership groups in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-membership)
- [Manage groups in Microsoft Graph](https://learn.microsoft.com/en-us/graph/api/resources/groups-overview?view=graph-rest-1.0)
- [Use Microsoft Entra groups to manage role assignments](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-concept)
- [Training: Use dynamic group membership and filters](https://learn.microsoft.com/training/modules/configure-entraid-device-management/06-dynamic-groups-filters)

Next: [Phase 3 — Administrative Units](03-administrative-units.md)
