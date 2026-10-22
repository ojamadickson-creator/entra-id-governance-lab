<#
.SYNOPSIS
    Creates an administrative unit, populates it with users, and assigns a
    Helpdesk Administrator role scoped to that administrative unit.

.DESCRIPTION
    Demonstrates least-privilege delegated administration:

    1. Creates the 'Contractors AU' administrative unit (creating AUs requires only
       Microsoft Entra ID Free; AU-scoped role assignment requires a P1/P2 license
       for each administrative unit administrator).
    2. Adds the contractor users as members of the AU, using the documented
       -OdataId reference form (idempotent: existing members are skipped).
    3. Assigns the Helpdesk Administrator role scoped to the AU for the helpdesk
       staff. AU-scoped Helpdesk Administrators can reset passwords ONLY for
       non-administrator users inside that AU.

    IMPORTANT LIMITATION: only a specific list of built-in roles supports
    administrative unit scope. Security Reader, Security Administrator, and
    Cloud App Security Administrator are NOT AU-scopable and must be assigned at
    tenant scope. See docs/03-administrative-units.md.

.NOTES
    Required Graph permissions (delegated):
      AdministrativeUnit.ReadWrite.All, RoleManagement.ReadWrite.Directory,
      User.Read.All, Group.Read.All
    Operator role: Privileged Role Administrator
    Module: Microsoft.Graph (incl. Microsoft.Graph.Identity.DirectoryManagement)

    The users named in -HelpdeskPrincipals must already exist in the tenant
    (create them in Phase 1 or via the admin center).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [string]$AdminUnitName = 'Contractors AU',

    [string]$GroupDisplayName = 'Cyber Security Contractors',  # static group from Phase 1

    # FULL user principal names of the staff who receive the AU-scoped Helpdesk
    # Administrator role. The lookup is exact: a missing or ambiguous UPN fails the run.
    [string[]]$HelpdeskPrincipals = @(
        'rita.marques@beginningdimension.com',
        'bruno.alves@beginningdimension.com',
        'nadia.faro@beginningdimension.com')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[1/5] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId `
    -Scopes 'AdministrativeUnit.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', `
             'User.Read.All', 'Group.Read.All' `
    -NoWelcome

# --- 1. Create (or find) the administrative unit ---
Write-Host "[2/5] Creating administrative unit '$AdminUnitName'..." -ForegroundColor Cyan
$au = Get-MgDirectoryAdministrativeUnit -Filter "displayName eq '$AdminUnitName'" -Top 1
if (-not $au) {
    $au = New-MgDirectoryAdministrativeUnit -DisplayName $AdminUnitName `
        -Description 'Administrative boundary for the cyber security contractor cohort'
    Write-Host "  Created AU: $($au.DisplayName) ($($au.Id))" -ForegroundColor Green
} else {
    Write-Host "  AU already exists: $($au.DisplayName) ($($au.Id))" -ForegroundColor Yellow
}

# --- 2. Add contractor users to the AU (documented -OdataId reference form) ---
Write-Host "[3/5] Adding contractor users to the AU..." -ForegroundColor Cyan
$group = Get-MgGroup -Filter "displayName eq '$GroupDisplayName'" -Top 1
if (-not $group) { throw "Static group '$GroupDisplayName' not found. Run Phase 1 first." }

# Snapshot current AU members so re-runs are idempotent
$auMemberIds = @{}
Get-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -All |
    ForEach-Object { $auMemberIds[$_.Id] = $true }

$added = 0
foreach ($member in (Get-MgGroupMember -GroupId $group.Id -All)) {
    if ($auMemberIds.ContainsKey($member.Id)) { continue }
    $odataId = "https://graph.microsoft.com/v1.0/users/$($member.Id)"
    New-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $au.Id -OdataId $odataId
    $auMemberIds[$member.Id] = $true
    $added++
    Write-Host "  Added: $($member.AdditionalProperties.userPrincipalName)" -ForegroundColor Green
}
if ($added -eq 0) { Write-Host "  All cohort users already AU members." -ForegroundColor Gray }

# --- 3. Get the Helpdesk Administrator role definition ---
Write-Host "[4/5] Resolving Helpdesk Administrator role definition..." -ForegroundColor Cyan
$role = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq 'Helpdesk Administrator'" -Top 1
if (-not $role) { throw 'Helpdesk Administrator role definition not found.' }
Write-Host "  Role: $($role.DisplayName) ($($role.Id))" -ForegroundColor Green

# --- 4. Assign the role scoped to the AU ---
$directoryScope = '/administrativeUnits/' + $au.Id
Write-Host "[5/5] Assigning AU-scoped Helpdesk Administrator (scope: $directoryScope)..." -ForegroundColor Cyan
foreach ($upn in $HelpdeskPrincipals) {
    # Exact UPN resolution: a missing or duplicate match FAILS the run - privileged
    # assignments must never be made against a guessed identity.
    $user = @(Get-MgUser -Filter "userPrincipalName eq '$upn'")
    if ($user.Count -eq 0) { throw "User not found: $upn" }
    if ($user.Count -gt 1) { throw "Ambiguous UPN ($($user.Count) matches): $upn" }
    $user = $user[0]

    $existing = Get-MgRoleManagementDirectoryRoleAssignment -Filter `
        ("principalId eq '{0}' and roleDefinitionId eq '{1}' and directoryScopeId eq '{2}'" -f `
        $user.Id, $role.Id, $directoryScope) -Top 1
    if ($existing) {
        Write-Host "  SKIP (already assigned): $($user.UserPrincipalName)" -ForegroundColor Yellow
        continue
    }

    New-MgRoleManagementDirectoryRoleAssignment `
        -RoleDefinitionId $role.Id `
        -PrincipalId $user.Id `
        -DirectoryScopeId $directoryScope | Out-Null
    Write-Host "  Assigned: $($user.UserPrincipalName)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Validation reminder:" -ForegroundColor Cyan
Write-Host "  POSITIVE test: an AU-scoped helpdesk admin can reset the password of a" -ForegroundColor Gray
Write-Host "  non-admin contractor inside the AU."
Write-Host "  NEGATIVE test: the same admin CANNOT reset passwords of users outside the AU," -ForegroundColor Gray
Write-Host "  cannot manage admin accounts, and has no authority to modify tenant-wide"
Write-Host "  settings (what they can SEE is not the boundary - what they can CHANGE is)."

Disconnect-MgGraph | Out-Null
