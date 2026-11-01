<#
.SYNOPSIS
    Bulk-assigns targeted users from your local CSV to the Microsoft Entra SAML Toolkit using cached Graph lookups.
#>

# 1. Configuration Parameters
$csvPath        = "C:\Users\Ojama\Downloads\users_10_31_2026 11_33_41 PM.csv"
$appDisplayName = "Microsoft Entra SAML Toolkit"
$appRoleName    = "msiam_access"

# Define the target job titles or filter rules from your lab instructions
$targetTitles   = @("SOC Analyst", "Tier 1 SOC Analyst", "Penetration Tester")

# 2. Connect to Microsoft Graph with required scopes
Write-Host "[1/4] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All", "Application.Read.All", "User.Read.All" -NoWelcome

# 3. Build In-Memory Caches to avoid throttling and N+1 queries
Write-Host "[2/4] Building in-memory caches..." -ForegroundColor Cyan
$spCache = @{}
Get-MgServicePrincipal -All | ForEach-Object { $spCache[$_.Id] = $_.DisplayName }

$userCache = @{}
Get-MgUser -All | ForEach-Object { $userCache[$_.UserPrincipalName.ToLowerInvariant()] = $_.Id }

# 4. Resolve Service Principal and App Role ID
Write-Host "[3/4] Resolving app and role IDs..." -ForegroundColor Cyan
$spMatches = @($spCache.GetEnumerator() | Where-Object { $_.Value -eq $appDisplayName })
if ($spMatches.Count -eq 0) { throw "Service principal not found: $appDisplayName" }
$spId = $spMatches[0].Key
$sp = Get-MgServicePrincipal -ServicePrincipalId $spId

# Find the specific role ID for 'msiam_access'
$appRole = $sp.AppRoles | Where-Object { $_.DisplayName -eq $appRoleName -and $_.IsEnabled } | Select-Object -First 1
if (-not $appRole) { throw "App role '$appRoleName' not found on '$appDisplayName'." }
$appRoleId = $appRole.Id

Write-Host "  Target App: $appDisplayName ($spId)" -ForegroundColor Green
Write-Host "  App Role:   $appRoleName ($appRoleId)" -ForegroundColor Green

# 5. Import CSV and Filter Target Users by Job Title
if (-Not (Test-Path $csvPath)) { throw "CSV file not found at path: $csvPath" }
$csvData = Import-Csv -Path $csvPath
$targetUsers = $csvData | Where-Object { $_.'Title' -in $targetTitles }

Write-Host "[4/4] Processing bulk assignments for $($targetUsers.Count) users..." -ForegroundColor Cyan
$assigned = 0; $skipped = 0; $failed = 0

foreach ($row in $targetUsers) {
    $upn = $row.'User principal name'
    $key = $upn.ToLowerInvariant()
    
    if (-not $userCache.ContainsKey($key)) {
        Write-Host "  FAILED (User not found in tenant): $upn" -ForegroundColor Red
        $failed++
        continue
    }

    $userId = $userCache[$key]

    try {
        $params = @{
            PrincipalId = $userId
            ResourceId  = $spId
            AppRoleId   = $appRoleId
        }
        
        New-MgUserAppRoleAssignment -UserId $userId -BodyParameter $params | Out-Null
        Write-Host "  ASSIGNED: $($row.'Display name') ($upn)" -ForegroundColor Green
        $assigned++
    }
    catch {
        if ($_.Exception.Message -match 'already exist|PermissionAlreadyAssigned') {
            Write-Host "  SKIP (Already assigned): $upn" -ForegroundColor Yellow
            $skipped++
        } else {
            Write-Host "  FAILED: $upn - $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }
}

Write-Host ""
Write-Host ("Summary: Assigned {0}, Skipped {1}, Failed {2}" -f $assigned, $skipped, $failed) -ForegroundColor Cyan

# Disconnect session cleanly when done
Disconnect-MgGraph | Out-Null
