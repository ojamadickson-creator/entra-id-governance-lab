<#
@'
<#
.SYNOPSIS
    Bulk-creates contractor user accounts in Microsoft Entra ID from a CSV source file.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$PrimaryDomain = 'beginningdimension.onmicrosoft.com',

    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [string]$GroupName = 'Cyber Security Contractors'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedIdentityString ([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $normalized = $text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($char in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($char)
        }
    }
    return ($sb.ToString() -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
}

function New-TemporaryPassword {
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $digit = '23456789'
    $special = '!@#$%^&*-_'
    $all = $upper + $lower + $digit + $special

    # Cryptographically secure random generator without nested scope issues
    $passChars = [System.Collections.Generic.List[char]]::new()
    $passChars.Add($upper[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($upper.Length)])
    $passChars.Add($lower[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($lower.Length)])
    $passChars.Add($digit[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($digit.Length)])
    $passChars.Add($special[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($special.Length)])

    1..12 | ForEach-Object {
        $passChars.Add($all[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($all.Length)])
    }

    # Fisher-Yates shuffle
    for ($i = $passChars.Count - 1; $i -gt 0; $i--) {
        $j = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32($i + 1)
        $temp = $passChars[$i]
        $passChars[$i] = $passChars[$j]
        $passChars[$j] = $temp
    }

    return -join $passChars
}

# --- 1. Authenticate to Microsoft Graph ---
Write-Host "[1/4] Connecting to Microsoft Graph (tenant: $TenantId)..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All' -NoWelcome

# --- 2. Verify / create the parent security group ---
Write-Host "[2/4] Verifying group container '$GroupName'..." -ForegroundColor Cyan
$group = Get-MgGroup -Filter "displayName eq '$GroupName'" -Top 1
if (-not $group) {
    Write-Host "  Group not found - creating..." -ForegroundColor Yellow
    $group = New-MgGroup -DisplayName $GroupName `
        -Description 'Parent group for cyber security contractor cohort' `
        -MailEnabled:$false `
        -MailNickname 'csc-contractors' `
        -SecurityEnabled `
        -GroupTypes @()
    Write-Host "  Created group $($group.DisplayName) ($($group.Id))" -ForegroundColor Green
} else {
    Write-Host "  Group exists: $($group.DisplayName) ($($group.Id))" -ForegroundColor Green
}
$groupId = $group.Id

# --- 3. User creation loop ---
Write-Host "[3/4] Processing CSV: $CsvPath" -ForegroundColor Cyan
if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$rows = @(Import-Csv -Path $CsvPath)
$created = 0; $skipped = 0; $failed = 0; $repaired = 0
$results = [System.Collections.Generic.List[object]]::new()

$existingMemberIds = @{}
Get-MgGroupMember -GroupId $groupId -All | ForEach-Object { $existingMemberIds[$_.Id] = $true }

foreach ($row in $rows) {
    $givenName = $row.FirstName.Trim()
    $surname   = $row.LastName.Trim()
    
    $cleanGiven = Get-NormalizedIdentityString -text $givenName
    $cleanSur   = Get-NormalizedIdentityString -text $surname
    $mailNick   = "$cleanGiven.$cleanSur"
    $upn        = "$mailNick@$PrimaryDomain"
    $displayName = "$givenName $surname"

    try {
        $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -Top 1 -ErrorAction SilentlyContinue
        if ($existing) {
            if (-not $existingMemberIds.ContainsKey($existing.Id)) {
                $memberOdataId = "https://graph.microsoft.com/v1.0/directoryObjects/$($existing.Id)"
                New-MgGroupMemberByRef -GroupId $groupId -OdataId $memberOdataId | Out-Null
                $existingMemberIds[$existing.Id] = $true
                $repaired++
                $results.Add([pscustomobject]@{ UPN = $upn; Status = 'Repaired (membership)' })
                Write-Host "  REPAIRED (added to group): $upn" -ForegroundColor Yellow
            } else {
                $results.Add([pscustomobject]@{ UPN = $upn; Status = 'Skipped (exists)' })
                Write-Host "  SKIP (UPN collision): $upn" -ForegroundColor DarkGray
            }
            $skipped++
            continue
        }

        $password = New-TemporaryPassword
        $passwordProfile = @{
            Password                      = $password
            ForceChangePasswordNextSignIn = $true
        }

        $user = New-MgUser -DisplayName $displayName `
            -GivenName $givenName `
            -Surname $surname `
            -UserPrincipalName $upn `
            -AccountEnabled:$true `
            -JobTitle $row.JobTitle `
            -Department $row.Department `
            -CompanyName $row.CompanyName `
            -MailNickname $mailNick `
            -UsageLocation 'PT' `
            -PasswordProfile $passwordProfile

        $createdUserId = if ($user.Id) { $user.Id } else { (Get-MgUser -Filter "userPrincipalName eq '$upn'" -Top 1).Id }
        $memberOdataId = "https://graph.microsoft.com/v1.0/directoryObjects/$createdUserId"
        New-MgGroupMemberByRef -GroupId $groupId -OdataId $memberOdataId | Out-Null
        $existingMemberIds[$createdUserId] = $true

        Write-Host "  CREATED: $upn" -ForegroundColor Green
        $created++
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

$reportPath = ".\onboarding-report-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$results | Export-Csv -Path $reportPath -NoTypeInformation
Write-Host "  Status report written to $reportPath" -ForegroundColor Gray

Disconnect-MgGraph | Out-Null
'@ | Set-Content -Path './scripts/01-Bulk-Create-Contractors.ps1' -Encoding utf8
