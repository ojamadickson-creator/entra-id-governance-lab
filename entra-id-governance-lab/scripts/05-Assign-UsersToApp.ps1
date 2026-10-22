<#
.SYNOPSIS
    Bulk-assigns users to an enterprise application using cached Graph lookups.

.DESCRIPTION
    Demonstrates the hash-table caching optimization for bulk app assignments:

    - Pre-resolves all service principals into $spCache (keyed by Id) - used to
      validate the target service principal and detect ambiguous display names
    - Pre-resolves all users into $userCache (keyed by UPN)
    - Executes New-MgUserAppRoleAssignment with cached Object IDs, avoiding redundant
      read queries inside the loop (which risks HTTP 429 throttling)

    If the application does not declare app roles (or none is requested), the default
    app role ID 00000000-0000-0000-0000-000000000000 is used, which signals assignment
    to the resource app without a specific app role. When an app role name IS
    requested, it must be enabled on the service principal and allow User members.

    To assign a GROUP instead of users, run with -GroupId; the body is constructed
    with the group's PrincipalId (New-MgGroupAppRoleAssignment).

    IMPORTANT: verify PrincipalId, ResourceId, and AppRoleId before assigning -
    assignments are built from stable object IDs, not display names. If more than one
    service principal matches the display name, the script fails instead of guessing.

.NOTES
    Required Graph permissions (delegated): AppRoleAssignment.ReadWrite.All,
    Application.Read.All, User.Read.All (and Group.Read.All for -GroupId)
    Operator role: Cloud Application Administrator (or Application Administrator)
    Module: Microsoft.Graph
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$AppDisplayName,                 # e.g. 'Microsoft Entra SAML Toolkit'

    [string]$AppRoleDisplayName,            # optional; empty = default app role (all zeros)

    [Parameter(Mandatory = $true, ParameterSetName = 'Users')]
    [string[]]$UserUpns,                    # users to assign

    [Parameter(Mandatory = $true, ParameterSetName = 'Group')]
    [string]$GroupId,                       # group to assign (P1 required)

    [Parameter(ParameterSetName = 'Users')]
    [Parameter(ParameterSetName = 'Group')]
    [string]$ServicePrincipalId             # optional: resolve the app by object ID
                                            # (use when display names are ambiguous)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[1/4] Connecting to Microsoft Graph..." -ForegroundColor Cyan
$scopes = @('AppRoleAssignment.ReadWrite.All', 'Application.Read.All')
if ($PSCmdlet.ParameterSetName -eq 'Users') { $scopes += 'User.Read.All' }
else { $scopes += 'Group.Read.All' }
Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome

# --- 1. Build in-memory caches (the optimization this script demonstrates) ---
Write-Host "[2/4] Building in-memory caches..." -ForegroundColor Cyan
$spCache = @{}
Get-MgServicePrincipal -All | ForEach-Object { $spCache[$_.Id] = $_.DisplayName }
Write-Host "  Cached $($spCache.Count) service principals" -ForegroundColor Gray

$userCache = @{}
if ($PSCmdlet.ParameterSetName -eq 'Users') {
    Get-MgUser -All | ForEach-Object { $userCache[$_.UserPrincipalName.ToLowerInvariant()] = $_.Id }
    Write-Host "  Cached $($userCache.Count) users" -ForegroundColor Gray
}

# --- 2. Resolve the target service principal (fail on ambiguity) ---
if ($ServicePrincipalId) {
    if (-not $spCache.ContainsKey($ServicePrincipalId)) {
        throw "Service principal not found by ID: $ServicePrincipalId"
    }
    $sp = Get-MgServicePrincipal -ServicePrincipalId $ServicePrincipalId
} else {
    $spMatches = @($spCache.GetEnumerator() | Where-Object { $_.Value -eq $AppDisplayName })
    if ($spMatches.Count -eq 0) { throw "Service principal not found: $AppDisplayName" }
    if ($spMatches.Count -gt 1) {
        throw ("Ambiguous display name '{0}' matches {1} service principals. Re-run with " -f $AppDisplayName, $spMatches.Count) +
              "-ServicePrincipalId <object-id> (list candidates with Get-MgServicePrincipal -Filter `"displayName eq '$AppDisplayName'`")"
    }
    $sp = Get-MgServicePrincipal -ServicePrincipalId $spMatches[0].Key
}
Write-Host "  Target: $($sp.DisplayName) ($($sp.Id))" -ForegroundColor Green

# --- 3. Resolve the app role ---
# The filtered list selects valid USER-assignable roles; the TOTAL AppRoles collection
# decides whether the default all-zeros role is allowed at all.
$totalRoles = @($sp.AppRoles)
$declaredRoles = @($totalRoles | Where-Object { $_.IsEnabled -and $_.AllowedMemberTypes -contains 'User' })

if ([string]::IsNullOrWhiteSpace($AppRoleDisplayName)) {
    # The default all-zeros app role is only valid when the app declares no app roles
    # of any kind (disabled or application-only roles still count as declared)
    if ($totalRoles.Count -gt 0) {
        throw ("'{0}' declares {1} app role(s); pass -AppRoleDisplayName " -f $sp.DisplayName, $totalRoles.Count) +
              "(user-assignable options: $(($declaredRoles | ForEach-Object DisplayName) -join ', '))"
    }
    $appRoleId = '00000000-0000-0000-0000-000000000000'   # default app role
    Write-Host "  Using default app role (app declares no app roles)" -ForegroundColor Gray
} else {
    $appRole = @($declaredRoles | Where-Object {
        $_.DisplayName -eq $AppRoleDisplayName -and $_.IsEnabled -and $_.AllowedMemberTypes -contains 'User'
    }) | Select-Object -First 1
    if (-not $appRole) {
        throw "App role '$AppRoleDisplayName' not found, disabled, or not assignable to users on '$($sp.DisplayName)'."
    }
    $appRoleId = $appRole.Id
    Write-Host "  App role: $AppRoleDisplayName ($appRoleId)" -ForegroundColor Gray
}

# --- 4. Assignment loop using cached IDs ---
Write-Host "[4/4] Assigning to '$AppDisplayName'..." -ForegroundColor Cyan
$assigned = 0; $skipped = 0; $failed = 0

if ($PSCmdlet.ParameterSetName -eq 'Users') {
    foreach ($upn in $UserUpns) {
        $key = $upn.ToLowerInvariant()
        if (-not $userCache.ContainsKey($key)) {
            Write-Host "  FAILED (user not found): $upn" -ForegroundColor Red
            $failed++
            continue
        }
        $userId = $userCache[$key]

        try {
            $params = @{ PrincipalId = $userId; ResourceId = $sp.Id; AppRoleId = $appRoleId }
            New-MgUserAppRoleAssignment -UserId $userId -BodyParameter $params | Out-Null
            Write-Host "  ASSIGNED: $upn" -ForegroundColor Green
            $assigned++
        }
        catch {
            if ($_.Exception.Message -match 'already exist|PermissionAlreadyAssigned') {
                Write-Host "  SKIP (already assigned): $upn" -ForegroundColor Yellow
                $skipped++
            } else {
                Write-Host "  FAILED: $upn - $($_.Exception.Message)" -ForegroundColor Red
                $failed++
            }
        }
    }
} else {
    # Group assignment: PrincipalId is the GROUP's object ID
    try {
        $params = @{ PrincipalId = $GroupId; ResourceId = $sp.Id; AppRoleId = $appRoleId }
        New-MgGroupAppRoleAssignment -GroupId $GroupId -BodyParameter $params | Out-Null
        Write-Host "  ASSIGNED: group $GroupId" -ForegroundColor Green
        $assigned++
    }
    catch {
        if ($_.Exception.Message -match 'already exist|PermissionAlreadyAssigned') {
            Write-Host "  SKIP (already assigned): group $GroupId" -ForegroundColor Yellow
            $skipped++
        } else {
            Write-Host "  FAILED: group $GroupId - $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }
}

Write-Host ""
Write-Host ("Summary: assigned {0}, skipped {1}, failed {2}" -f $assigned, $skipped, $failed)
Write-Host "Note: caching removes redundant READ queries; assignment POSTs can still" -ForegroundColor Gray
Write-Host "receive throttling (429) responses under load - implement retry with backoff" -ForegroundColor Gray
Write-Host "for production use."

Disconnect-MgGraph | Out-Null
