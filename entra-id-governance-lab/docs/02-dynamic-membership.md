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
Get-MgGroupMember -GroupId $g.Id -All | ForEach-Object {
    Get-MgUser -UserId $_.Id -Property "displayName,jobTitle,userPrincipalName"
} | Select-Object DisplayName, JobTitle, UserPrincipalName | Format-Table -AutoSize
```

Expected: the four IAM identities (Marcus Reyes, Aisha Khan, Luis Ferreira, Ines Machado).

### 5. Test rule-driven add and remove

- **Attribute trigger:** update a user's `JobTitle` to a matching value — the background
  engine adds them to IM Staff.
- **Attribute removal:** change Marcus Reyes' `JobTitle` to "SOC Analyst" — the rule
  re-evaluates and the engine removes him from IM Staff.

```powershell
$targetUpn = 'marcus.reyes@beginningdimension.onmicrosoft.com'
Update-MgUser -UserId $targetUpn -JobTitle 'SOC Analyst'
Write-Host "Updated JobTitle to 'SOC Analyst' for $targetUpn. Waiting for dynamic rule re-evaluation..." -ForegroundColor Yellow
```
### Verify Removal (Allow 2–5 minutes)
Check that Marcus is no longer a member of IM Staff
```powershell
$group = Get-MgGroup -Filter "displayName eq 'IM Staff'" -Top 1
$isMember = @(Get-MgGroupMember -GroupId $group.Id -All | Where-Object {
    $u = Get-MgUser -UserId $_.Id
    $u.UserPrincipalName -eq $targetUpn
}).Count -gt 0

if (-not $isMember) {
    Write-Host "SUCCESS: Marcus Reyes was removed from 'IM Staff' by dynamic evaluation!" -ForegroundColor Green
} else {
    Write-Host "PENDING: Marcus is still listed. Background evaluation has not finished yet." -ForegroundColor Gray
}
```

### 5b. Restore the test attribute

After the removal test, restore Marcus's IAM job title so the dynamic group returns to its
expected state for later phases:

```powershell
Update-MgUser -UserId $targetUpn -JobTitle 'Identity and Access Management Engineer'
Write-Host "Restored JobTitle to 'Identity and Access Management Engineer'. Marcus will re-appear in 'IM Staff' shortly." -ForegroundColor Green
```

Automated Test Script (Test-DynamicGroupEvaluation.ps1)
If you want a single script to test the removal, monitor the background rule engine, and restore the attribute automatically:
```powershell
[CmdletBinding()]
param(
    [string]$TargetUpn = 'marcus.reyes@beginningdimension.onmicrosoft.com',
    [string]$GroupName = 'IM Staff'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$group = Get-MgGroup -Filter "displayName eq '$GroupName'" -Top 1
if (-not $group) {
    throw "Dynamic group '$GroupName' not found."
}

# 1. Change title to trigger removal
Write-Host "[1/3] Changing JobTitle to 'SOC Analyst' (triggering removal from $GroupName)..." -ForegroundColor Cyan
Update-MgUser -UserId $TargetUpn -JobTitle 'SOC Analyst'

Write-Host "Waiting for background rule evaluation..." -ForegroundColor Gray
$removed = $false
for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 30
    $memberCount = @(Get-MgGroupMember -GroupId $group.Id -All | Where-Object {
        (Get-MgUser -UserId $_.Id).UserPrincipalName -eq $TargetUpn
    }).Count

    if ($memberCount -eq 0) {
        Write-Host "  Confirmed: User successfully removed after $($i * 30) seconds." -ForegroundColor Green
        $removed = $true
        break
    } else {
        Write-Host "  Check $i: Still evaluating in Entra ID queue..." -ForegroundColor Gray
    }
}

if (-not $removed) {
    Write-Host "  Evaluation still queued; proceeding with attribute restoration." -ForegroundColor Yellow
}

# 2. Restore attribute
Write-Host "[2/3] Restoring JobTitle to 'Identity and Access Management Engineer'..." -ForegroundColor Cyan
Update-MgUser -UserId $TargetUpn -JobTitle 'Identity and Access Management Engineer'
Write-Host "  Marcus Reyes attribute restored." -ForegroundColor Green

# 3. Final summary
Write-Host "[3/3] Dynamic membership test sequence complete." -ForegroundColor Cyan
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
