<#
.SYNOPSIS
    Creates the lab's dynamic membership groups in Microsoft Entra ID.

.DESCRIPTION
    Creates two dynamic membership groups:

    1. 'Cyber Security Contractors' (dynamic) - user.department -eq "Cyber Security Contractors"
       Note: this is the DYNAMIC membership variant used for attribute-driven organization.
       It is separate from the static parent group created in Phase 1.

    2. 'IM Staff' (dynamic) - scoped prefix matching on job titles, restricted to the
       contractor cohort so broad title prefixes cannot pull in unrelated users:
       (user.department -eq "Cyber Security Contractors") -and (
           (user.jobTitle -startsWith "IM") -or (user.jobTitle -startsWith "Identity"))

    Membership processing is asynchronous: allow a few minutes after creation before
    expecting members to appear. Verify via the group's membership and the tenant
    audit logs.

.NOTES
    Licensing: dynamic membership requires Microsoft Entra ID P1 (or Intune for Education)
    licenses to cover each unique user in dynamic groups. See
    https://learn.microsoft.com/en-us/entra/fundamentals/licensing

    Required Graph permissions (delegated): Group.ReadWrite.All
    Dynamic groups cannot be role-assignable groups.
    Module: Microsoft.Graph
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[1/3] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes 'Group.ReadWrite.All' -NoWelcome

# --- Group 1: dynamic contractor group ---
$contractorRule = 'user.department -eq "Cyber Security Contractors"'

Write-Host "[2/3] Creating dynamic group 'Cyber Security Contractors (Dynamic)'..." -ForegroundColor Cyan
$g1 = Get-MgGroup -Filter "displayName eq 'Cyber Security Contractors (Dynamic)'" -Top 1
if (-not $g1) {
    $g1 = New-MgGroup -DisplayName 'Cyber Security Contractors (Dynamic)' `
        -Description 'Dynamic membership: department = Cyber Security Contractors' `
        -MailEnabled:$false -MailNickname 'csc-dynamic' `
        -SecurityEnabled `
        -GroupTypes @('DynamicMembership') `
        -MembershipRule $contractorRule `
        -MembershipRuleProcessingState 'On'
    Write-Host "  Created: $($g1.DisplayName) ($($g1.Id))" -ForegroundColor Green
} else {
    Write-Host "  Already exists: $($g1.DisplayName) ($($g1.Id))" -ForegroundColor Yellow
}

# --- Group 2: IM Staff, prefix-matching rule scoped to the contractor cohort ---
$imRule = '(user.department -eq "Cyber Security Contractors") -and ((user.jobTitle -startsWith "IM") -or (user.jobTitle -startsWith "Identity"))'

Write-Host "[3/3] Creating dynamic group 'IM Staff'..." -ForegroundColor Cyan
$g2 = Get-MgGroup -Filter "displayName eq 'IM Staff'" -Top 1
if (-not $g2) {
    $g2 = New-MgGroup -DisplayName 'IM Staff' `
        -Description 'Dynamic membership: IAM job titles within the contractor cohort' `
        -MailEnabled:$false -MailNickname 'im-staff' `
        -SecurityEnabled `
        -GroupTypes @('DynamicMembership') `
        -MembershipRule $imRule `
        -MembershipRuleProcessingState 'On'
    Write-Host "  Created: $($g2.DisplayName) ($($g2.Id))" -ForegroundColor Green
} else {
    Write-Host "  Already exists: $($g2.DisplayName) ($($g2.Id))" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Membership rule - 'IM Staff':" -ForegroundColor Cyan
Write-Host "  $imRule"
Write-Host ""
Write-Host "Processing is asynchronous - allow a few minutes, then verify membership" -ForegroundColor Gray
Write-Host "in the Microsoft Entra admin center (Groups > All groups > IM Staff > Members)." -ForegroundColor Gray

Disconnect-MgGraph | Out-Null
