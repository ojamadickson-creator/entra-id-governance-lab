<#
.SYNOPSIS
    Bulk-creates contractor user accounts in Microsoft Entra ID from a CSV source file.

.DESCRIPTION
    Reads a CSV file (FirstName, LastName, JobTitle, Specialty, Department, CompanyName),
    creates each user with a randomized temporary password that must be changed at first
    sign-in, and reports a color-coded summary (created / skipped / failed).

    The 'Specialty' column is consumed by the role-mapping logic in later phases; it is
    not written to a standard Microsoft Entra ID user property.

    Before running: review the Microsoft documentation referenced in
    docs/01-automated-onboarding.md. Verify licensing, UPN domain, and CSV contents.

.NOTES
    Required Graph permissions (delegated): User.ReadWrite.All, Group.ReadWrite.All
    Operator role: User Administrator (or Global Administrator)
    Module: Microsoft.Graph (Install-Module Microsoft.Graph)
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,                       # e.g. 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

    [Parameter(Mandatory = $true)]
    [string]$PrimaryDomain,                  # verified domain, e.g. 'beginningdimension.com'

    [Parameter(Mandatory = $true)]
    [string]$CsvPath,                        # e.g. '.\data\contractors.csv'

    [string]$GroupName = 'Cyber Security Contractors'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-TemporaryPassword {
    # 16-char password meeting Entra ID default complexity requirements.
    # Uses a cryptographic RNG (System.Random is NOT suitable for secrets).
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lower = 'abcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $digit = '23456789'.ToCharArray()
    $special = '!@#$%^&*-_'.ToCharArray()
    $all = $upper + $lower + $digit + $special

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    function Get-RandomIndex([int]$max) {
        # rejection sampling for a uniform, unbiased index in [0, max)
        $bytes = New-Object byte[] 4
        $limit = [uint32]([uint32]::MaxValue - ([uint32]::MaxValue % $max))
        while ($true) {
            $rng.GetBytes($bytes)
            $value = [BitConverter]::ToUInt32($bytes, 0)
            if ($value -lt $limit) { return [int]($value % $max) }
        }
    }

    $chars = @(
        $upper[(Get-RandomIndex $upper.Length)]
        $lower[(Get-RandomIndex $lower.Length)]
        $digit[(Get-RandomIndex $digit.Length)]
        $special[(Get-RandomIndex $special.Length)]
    )
    1..12 | ForEach-Object { $chars += $all[(Get-RandomIndex $all.Length)] }
    # Fisher-Yates shuffle
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = Get-RandomIndex ($i + 1)
        $chars[$i], $chars[$j] = $chars[$j], $chars[$i]
    }
    -join $chars
}

# --- 1. Authenticate to Microsoft Graph (least-privilege scopes for this exercise) ---
Write-Host "[1/4] Connecting to Microsoft Graph (tenant: $TenantId)..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All' -NoWelcome

# --- 2. Verify / create the parent security group (static, assigned membership) ---
Write-Host "[2/4] Verifying group container '$GroupName'..." -ForegroundColor Cyan
$group = Get-MgGroup -Filter "displayName eq '$GroupName'" -Top 1
if (-not $group) {
    Write-Host "  Group not found - creating..." -ForegroundColor Yellow
    $group = New-MgGroup -DisplayName $GroupName `
        -Description 'Parent group for cyber security contractor cohort' `
        -MailEnabled:$false -MailNickname 'csc-contractors' `
        -SecurityEnabled -GroupTypes @()
    Write-Host "  Created group $($group.DisplayName) ($($group.Id))" -ForegroundColor Green
} else {
    Write-Host "  Group exists: $($group.DisplayName) ($($group.Id))" -ForegroundColor Green
}
$groupId = $group.Id

# --- 3. User creation loop ---
Write-Host "[3/4] Processing CSV: $CsvPath" -ForegroundColor Cyan
$rows = Import-Csv -Path $CsvPath
$created = 0; $skipped = 0; $failed = 0; $repaired = 0
$results = [System.Collections.Generic.List[object]]::new()

# Snapshot current group members so re-runs repair missing memberships
$existingMemberIds = @{}
Get-MgGroupMember -GroupId $groupId -All | ForEach-Object { $existingMemberIds[$_.Id] = $true }

foreach ($row in $rows) {
    $givenName = $row.FirstName.Trim()
    $surname   = $row.LastName.Trim()
    $upn         = ("{0}.{1}@{2}" -f $givenName.ToLowerInvariant(), $surname.ToLowerInvariant(), $PrimaryDomain)
    $displayName = "$givenName $surname"

    try {
        $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -Top 1 -ErrorAction SilentlyContinue
        if ($existing) {
            # Idempotent repair: existing user gets its parent-group membership verified
            if (-not $existingMemberIds.ContainsKey($existing.Id)) {
                $ref = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($existing.Id)" }
                New-MgGroupMemberByRef -GroupId $groupId -BodyParameter $ref | Out-Null
                $existingMemberIds[$existing.Id] = $true
                $repaired++
                $results.Add([pscustomobject]@{ UPN = $upn; Status = 'Repaired (membership)' })
            } else {
                $results.Add([pscustomobject]@{ UPN = $upn; Status = 'Skipped (exists)' })
            }
            $skipped++
            Write-Host "  SKIP (UPN collision): $upn" -ForegroundColor Yellow
            continue
        }

        $password = New-TemporaryPassword
        $passwordProfile = @{
            Password                      = $password
            ForceChangePasswordNextSignIn = $true
        }

        $user = New-MgUser -DisplayName $displayName `
            -GivenName $givenName -Surname $surname `
            -UserPrincipalName $upn `
            -AccountEnabled:$true `
            -JobTitle $row.JobTitle `
            -Department $row.Department `
            -CompanyName $row.CompanyName `
            -MailNickname ($upn -split '@')[0] `
            -UsageLocation 'PT' `
            -PasswordProfile $passwordProfile

        # Add to the parent security group (documented @odata.id reference form)
        $ref = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)" }
        New-MgGroupMemberByRef -GroupId $groupId -BodyParameter $ref | Out-Null

        Write-Host "  CREATED: $upn" -ForegroundColor Green
        $created++
        # NOTE: the temporary password is deliberately NOT written to the log or results
        # file. Communicate initial credentials through a secure out-of-band channel.
        $results.Add([pscustomobject]@{ UPN = $upn; Status = 'Created' })
    }
    catch {
        Write-Host "  FAILED: $upn - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
        $results.Add([pscustomobject]@{ UPN = $upn; Status = "Failed: $($_.Exception.Message)" })
    }
}

# --- 4. Summary report ---
Write-Host "[4/4] Execution summary" -ForegroundColor Cyan
Write-Host ("  Created: {0}   Skipped: {1}   Failed: {2}   Repaired memberships: {3}   Total rows: {4}" -f $created, $skipped, $failed, $repaired, $rows.Count)
$results | Export-Csv -Path ".\onboarding-report-$(Get-Date -Format 'yyyyMMdd-HHmm').csv" -NoTypeInformation
Write-Host "  Status report written to .\onboarding-report-<timestamp>.csv (no passwords included)" -ForegroundColor Gray

Disconnect-MgGraph | Out-Null
