<#
.SYNOPSIS
    Executes the documented offboarding sequence for a user in Microsoft Entra ID.

.DESCRIPTION
    PARTIAL OFFBOARDING AUTOMATION. Executes the machine-safe parts of Microsoft's
    documented order for revoking access ("Revoke user access in an emergency" -
    learn.microsoft.com/entra/identity/users/users-revoke-access):

        1. Disable the account (AccountEnabled = $false)     <- blocks new auth FIRST
        2. Revoke active sign-in sessions / refresh tokens   <- kills sessions EARLY
        3. Strip application assignments (app role assignments)
        3b. Remove the lab parent-group membership
        4. MANUAL (not automated) - role cleanup via the documented portal
           procedure: see docs/07-offboarding-and-cleanup.md step 3, covering BOTH
           Active and Eligible assignments
        5. Delete the directory account (OPTIONAL, destructive - opt-in)

    The order matters: Microsoft's guidance disables the account and revokes
    sessions early in the sequence so new authentication is blocked immediately,
    then entitlements are removed.

    ROLE CLEANUP IS DELIBERATELY NOT AUTOMATED. This implementation has not
    verified a reliable discriminator between PIM-managed and standing
    assignments in the plain role-assignment list, and destructive deletes must
    not depend on a heuristic. Perform step 4 manually via the documented
    portal procedure and verify it there - do not pass -DeleteUser until that
    step is complete.

    LIMITATIONS (documented by Microsoft - do not overstate):
    - Revoke-MgUserSignInSession invalidates refresh tokens and browser session
      cookies by resetting signInSessionsValidFromDateTime. Already-issued access
      tokens may remain valid until they expire, and application-controlled
      sessions are not terminated by this operation.
    - Revocation can take a few minutes to propagate.
    - The script removes direct app assignments and the lab parent-group
      membership; other group memberships must be audited separately -
      group-derived app and role access persists until memberships are removed.

    The script never deletes the user unless -DeleteUser is explicitly passed.
    Review the plan output first; deleted users are recoverable for 30 days by default.

.NOTES
    Required Graph permissions (delegated):
      User.ReadWrite.All, AppRoleAssignment.ReadWrite.All,
      Group.ReadWrite.All (parent-group membership removal)
    Operator role: User Administrator
    Modules: Microsoft.Graph (incl. Microsoft.Graph.Users.Actions)
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$UserPrincipalName,

    [switch]$DeleteUser   # explicit opt-in for step 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[0/5] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId `
    -Scopes 'User.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'Group.ReadWrite.All' `
    -NoWelcome

$user = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'" -Top 1
if (-not $user) { throw "User not found: $UserPrincipalName" }
$userId = $user.Id
Write-Host "Offboarding: $($user.DisplayName) ($UserPrincipalName)" -ForegroundColor Cyan
Write-Host "Run with -WhatIf to review the plan without making changes." -ForegroundColor Gray

# --- Step 1: disable the account (blocks new authentication) ---
if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Disable account')) {
    Write-Host "[1/5] Disabling the account..." -ForegroundColor Cyan
    Update-MgUser -UserId $userId -AccountEnabled:$false
    Write-Host "  AccountEnabled = false" -ForegroundColor Green
}

# --- Step 2: revoke active sessions / refresh tokens ---
if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Revoke sign-in sessions')) {
    Write-Host "[2/5] Revoking sign-in sessions (refresh tokens + browser session cookies)..." -ForegroundColor Cyan
    Import-Module Microsoft.Graph.Users.Actions -ErrorAction SilentlyContinue
    Revoke-MgUserSignInSession -UserId $userId | Out-Null
    Write-Host "  signInSessionsValidFromDateTime reset to now (propagation may take a few minutes)" -ForegroundColor Green
}

# --- Step 3: strip enterprise application assignments ---
if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Remove app assignments')) {
    Write-Host "[3/5] Removing app role assignments..." -ForegroundColor Cyan
    $assignments = Get-MgUserAppRoleAssignment -UserId $userId -All
    foreach ($a in $assignments) {
        Remove-MgUserAppRoleAssignment -UserId $userId -AppRoleAssignmentId $a.Id
        Write-Host "  Removed app assignment: $($a.ResourceDisplayName)" -ForegroundColor Green
    }
    if (-not $assignments) { Write-Host "  No app assignments found." -ForegroundColor Gray }
}

# --- Step 3b: remove the lab parent-group membership (group-derived access) ---
if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Remove lab parent-group membership')) {
    Write-Host "  Removing lab parent-group membership (group-derived access)..." -ForegroundColor Cyan
    $group = Get-MgGroup -Filter "displayName eq 'Cyber Security Contractors'" -Top 1
    if ($group) {
        # Pre-check membership: the reference may already be gone (a previous offboarding
        # run, or Phase 6's review already removed the user from the group).
        $isMember = @(Get-MgUserMemberOf -UserId $userId -All | Where-Object { $_.Id -eq $group.Id }).Count -gt 0
        if ($isMember) {
            # Fully qualified Graph v1.0 URI: DELETE /groups/{id}/members/{directoryObjectId}/$ref
            $uri = "https://graph.microsoft.com/v1.0/groups/$($group.Id)/members/$userId/`$ref"
            Invoke-MgGraphRequest -Method Delete -Uri $uri | Out-Null
            Write-Host "  Removed from group: $($group.DisplayName)" -ForegroundColor Green
        } else {
            Write-Host "  Not a member of '$($group.DisplayName)' - skipping (already removed)." -ForegroundColor Gray
        }
    } else {
        Write-Host "  Lab parent group not found - skipping group cleanup." -ForegroundColor Gray
    }
    Write-Host "  Audit any OTHER group memberships separately (portal or Get-MgUserMemberOf)" -ForegroundColor Gray
    Write-Host "  - group-derived app and role access persists until memberships are removed." -ForegroundColor Gray
}

# --- Step 4 (MANUAL - not automated): role cleanup ---
Write-Host "[4/5] ROLE CLEANUP NOT AUTOMATED - perform it manually via the documented portal" -ForegroundColor Yellow
Write-Host "     procedure (docs/07-offboarding-and-cleanup.md, step 3), covering BOTH Active and" -ForegroundColor Yellow
Write-Host "     Eligible assignments, and verify it there before any account deletion." -ForegroundColor Yellow

# --- Step 5 (optional): delete the directory account ---
if ($DeleteUser) {
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'DELETE user object')) {
        Write-Host "[5/5] Deleting the user object (recoverable for 30 days)..." -ForegroundColor Yellow
        Write-Host "      Confirm step 4 (manual role cleanup) is complete and verified first." -ForegroundColor Yellow
        Remove-MgUser -UserId $userId
        Write-Host "  User deleted." -ForegroundColor Yellow
    }
} else {
    Write-Host "[5/5] Account deletion SKIPPED (pass -DeleteUser to include it after retention checks" -ForegroundColor Gray
    Write-Host "     AND after the manual role-cleanup step is verified)." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Automated portion complete. Verify before declaring the offboarding done:" -ForegroundColor Cyan
Write-Host "  - user shows 'Sign-in blocked' in the admin center" -ForegroundColor Gray
Write-Host "  - audit logs record 'Disable account' and 'Revoke sessions' activities" -ForegroundColor Gray
Write-Host "  - no app assignments and no lab parent-group membership remain" -ForegroundColor Gray
Write-Host "  - role cleanup (manual step 4) performed and verified via the portal" -ForegroundColor Gray

Disconnect-MgGraph | Out-Null
