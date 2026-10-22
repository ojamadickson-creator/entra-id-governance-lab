<#
.SYNOPSIS
    No-tenant test harness for the lab scripts.

.DESCRIPTION
    Runs all five scripts in this repository against in-memory mocks of the Microsoft
    Graph cmdlets. It validates control flow, idempotency (re-run safety), failure handling
    (missing principals, ambiguous service principals, declared-role enforcement), the
    documented offboarding order (disable first, revoke sessions early, app removal next),
    that the offboarding script is honest PARTIAL automation - it touches no role
    assignments and submits no PIM requests, and prints the manual role-cleanup notice -
    and -WhatIf mutation suppression - all without a live tenant. This is a logic test
    of the scripts, not a substitute for executing the lab in a tenant.

    Run: pwsh -NoProfile -File tests/Test-Scripts.WithMocks.ps1
    Exit code 0 = all assertions passed.
#>

$repo = Split-Path -Parent $PSScriptRoot
$tmp = if ($env:TEMP) { $env:TEMP } else { '/tmp' }   # TEMP is unset on some Linux pwsh hosts
$ErrorActionPreference = 'Stop'
$global:pass = 0; $global:fail = 0

function Assert($name, $condition) {
    if ($condition) { $global:pass++; Write-Host "  PASS: $name" -ForegroundColor Green }
    else { $global:fail++; Write-Host "  FAIL: $name" -ForegroundColor Red }
}

# ---------------- Mock Graph data stores ----------------
$global:mockUsers     = [System.Collections.Generic.List[object]]::new()
$global:mockGroups    = @{}          # displayName -> group
$global:mockGroupMembers = @{}      # groupId -> List of user objects
$global:mockAUs       = @{}          # displayName -> au
$global:mockAUMembers = @{}          # auId -> List of user objects
$global:mockSPs       = @{}          # spId -> sp object
$global:mockRoleAssignments = [System.Collections.Generic.List[object]]::new()
$global:mockEligible  = [System.Collections.Generic.List[object]]::new()
$global:mockActive    = [System.Collections.Generic.List[object]]::new()
$global:mockRequests  = [System.Collections.Generic.List[object]]::new()
$global:mockPasswordProfiles = [System.Collections.Generic.List[object]]::new()
$global:mockMutationLog = [System.Collections.Generic.List[string]]::new()
$global:mockMutations = 0
$global:mockAppAssignments = [System.Collections.Generic.List[object]]::new()  # submitted bodies

function Reset-Mocks {
    $global:mockUsers.Clear()
    $global:mockGroups.Clear(); $global:mockGroupMembers.Clear()
    $global:mockAUs.Clear(); $global:mockAUMembers.Clear()
    $global:mockSPs.Clear()
    $global:mockRoleAssignments.Clear(); $global:mockEligible.Clear()
    $global:mockActive.Clear(); $global:mockRequests.Clear()
    $global:mockPasswordProfiles.Clear(); $global:mockMutationLog.Clear()
    $global:mockAppAssignments.Clear()
    $global:mockMutations = 0
}

function Note-Mutation([string]$Label) {
    $global:mockMutations++
    $global:mockMutationLog.Add($Label)
}

# ---------------- Mock cmdlets ----------------
function Connect-MgGraph { param([string]$TenantId, [string[]]$Scopes, [switch]$NoWelcome) }
function Disconnect-MgGraph { }

function Get-MgUser {
    param([string]$Filter, [int]$Top = 100, [switch]$All)
    $users = @($global:mockUsers)
    if ($Filter -match "userPrincipalName eq '([^']+)'") {
        return @($users | Where-Object { $_.UserPrincipalName -eq $Matches[1] })
    }
    if ($Filter -match "department eq '([^']+)'") {
        return @($users | Where-Object { $_.Department -eq $Matches[1] })
    }
    return $users
}
function New-MgUser {
    param([string]$DisplayName, [string]$UserPrincipalName, [switch]$AccountEnabled,
          [string]$JobTitle, [string]$Department, [string]$CompanyName,
          [hashtable]$PasswordProfile)
    $u = [pscustomobject]@{
        Id = [guid]::NewGuid().ToString(); DisplayName = $DisplayName
        UserPrincipalName = $UserPrincipalName; AccountEnabled = [bool]$AccountEnabled
        JobTitle = $JobTitle; Department = $Department; CompanyName = $CompanyName
        AdditionalProperties = @{ userPrincipalName = $UserPrincipalName }
    }
    $global:mockUsers.Add($u)
    $global:mockPasswordProfiles.Add($PasswordProfile)
    Note-Mutation "create-user:$UserPrincipalName"
    $u
}
function Update-MgUser { param([string]$UserId, [switch]$AccountEnabled, [string]$JobTitle)
    $u = $global:mockUsers | Where-Object { $_.Id -eq $UserId }
    if ($null -ne $u) {
        if ($PSBoundParameters.ContainsKey('AccountEnabled')) { $u.AccountEnabled = [bool]$AccountEnabled }
        if ($PSBoundParameters.ContainsKey('JobTitle')) { $u.JobTitle = $JobTitle }
        Note-Mutation "update-user"
    }
}
function Remove-MgUser { param([string]$UserId)
    $u = $global:mockUsers | Where-Object { $_.Id -eq $UserId }
    if ($u) { $global:mockUsers.Remove($u) }
    Note-Mutation "delete-user"
}
function Get-MgGroup { param([string]$Filter, [int]$Top = 100, [string]$GroupId)
    if ($GroupId) { return $global:mockGroupMembers.Keys | ForEach-Object { } | Out-Null; return $null }
    if ($Filter -match "displayName eq '([^']+)'") { return $global:mockGroups[$Matches[1]] }
}
function New-MgGroup { param([string]$DisplayName, [string]$Description, [switch]$MailEnabled,
                             [string]$MailNickname, [switch]$SecurityEnabled, [string[]]$GroupTypes,
                             [string]$MembershipRule, [string]$MembershipRuleProcessingState)
    $g = [pscustomobject]@{ Id = [guid]::NewGuid().ToString(); DisplayName = $DisplayName
                            GroupTypes = $GroupTypes; MembershipRule = $MembershipRule
                            MembershipRuleProcessingState = $MembershipRuleProcessingState }
    $global:mockGroups[$DisplayName] = $g
    $global:mockGroupMembers[$g.Id] = [System.Collections.Generic.List[object]]::new()
    Note-Mutation "create-group:$DisplayName"
    $g
}
function Get-MgGroupMember { param([string]$GroupId, [switch]$All)
    if ($global:mockGroupMembers.ContainsKey($GroupId)) { return $global:mockGroupMembers[$GroupId] }
    return @()
}
function New-MgGroupMemberByRef { param([string]$GroupId, [hashtable]$BodyParameter)
    $ref = $BodyParameter['@odata.id']
    $id = $ref -replace '.*/', ''
    $u = $global:mockUsers | Where-Object { $_.Id -eq $id }
    if ($u) { $global:mockGroupMembers[$GroupId].Add($u); Note-Mutation "add-group-member" }
}
function Get-MgDirectoryAdministrativeUnit { param([string]$Filter, [int]$Top = 100)
    if ($Filter -match "displayName eq '([^']+)'") { return $global:mockAUs[$Matches[1]] }
}
function New-MgDirectoryAdministrativeUnit { param([string]$DisplayName, [string]$Description)
    $au = [pscustomobject]@{ Id = [guid]::NewGuid().ToString(); DisplayName = $DisplayName }
    $global:mockAUs[$DisplayName] = $au
    $global:mockAUMembers[$au.Id] = [System.Collections.Generic.List[object]]::new()
    Note-Mutation "create-au:$DisplayName"
    $au
}
function Get-MgDirectoryAdministrativeUnitMember { param([string]$AdministrativeUnitId, [switch]$All)
    if ($global:mockAUMembers.ContainsKey($AdministrativeUnitId)) { return $global:mockAUMembers[$AdministrativeUnitId] }
    return @()
}
function New-MgDirectoryAdministrativeUnitMemberByRef { param([string]$AdministrativeUnitId, [string]$OdataId)
    $id = $OdataId -replace '.*/', ''
    $u = $global:mockUsers | Where-Object { $_.Id -eq $id }
    if ($u) { $global:mockAUMembers[$AdministrativeUnitId].Add($u); Note-Mutation "add-au-member" }
}
function Get-MgRoleManagementDirectoryRoleDefinition { param([string]$Filter, [int]$Top = 100)
    [pscustomobject]@{ Id = 'helpdesk-role-def-id'; DisplayName = 'Helpdesk Administrator' }
}
function Get-MgRoleManagementDirectoryRoleAssignment { param([string]$Filter, [int]$Top = 100)
    return @($global:mockRoleAssignments | Where-Object { $Filter -match $_.PrincipalId })
}
function New-MgRoleManagementDirectoryRoleAssignment {
    param([string]$RoleDefinitionId, [string]$PrincipalId, [string]$DirectoryScopeId)
    $global:mockRoleAssignments.Add([pscustomobject]@{
        Id = [guid]::NewGuid().ToString(); RoleDefinitionId = $RoleDefinitionId
        PrincipalId = $PrincipalId; DirectoryScopeId = $DirectoryScopeId })
    Note-Mutation "assign-role"
}
function Remove-MgRoleManagementDirectoryRoleAssignment { param([string]$UnifiedRoleAssignmentId)
    $ra = $global:mockRoleAssignments | Where-Object { $_.Id -eq $UnifiedRoleAssignmentId }
    if ($ra) { $global:mockRoleAssignments.Remove($ra) }
    Note-Mutation "remove-role-assignment"
}
function Get-MgRoleManagementDirectoryRoleEligibilitySchedule { param([string]$Filter, [switch]$All)
    return @($global:mockEligible | Where-Object { $Filter -match $_.PrincipalId })
}
function Get-MgRoleManagementDirectoryRoleAssignmentSchedule { param([string]$Filter, [switch]$All)
    return @($global:mockActive | Where-Object { $Filter -match $_.PrincipalId })
}
function New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest { param([hashtable]$BodyParameter)
    $global:mockRequests.Add([pscustomobject]@{ Type = 'Eligibility'; Body = $BodyParameter })
    Note-Mutation "adminremove-eligible" }
function New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest { param([hashtable]$BodyParameter)
    $global:mockRequests.Add([pscustomobject]@{ Type = 'Assignment'; Body = $BodyParameter })
    Note-Mutation "adminremove-active" }
function Get-MgServicePrincipal { param([string]$Filter, [switch]$All, [string]$ServicePrincipalId)
    if ($ServicePrincipalId) { return $global:mockSPs[$ServicePrincipalId] }
    if ($Filter -match "displayName eq '([^']+)'") {
        return @($global:mockSPs.Values | Where-Object { $_.DisplayName -eq $Matches[1] })
    }
    return $global:mockSPs.Values
}
function New-MgUserAppRoleAssignment { param([string]$UserId, [hashtable]$BodyParameter)
    $u = $global:mockUsers | Where-Object { $_.Id -eq $UserId }
    if (-not $u) { throw "Request_ResourceNotFound: user $UserId" }
    if (-not $u.PSObject.Properties['AppRoleAssignments']) {
        $u | Add-Member -NotePropertyName AppRoleAssignments -NotePropertyValue ([System.Collections.Generic.List[string]]::new()) -Force
    }
    if ($u.AppRoleAssignments -contains $BodyParameter.ResourceId) {
        throw "One or more properties are invalid: assignment already exists"
    }
    $u.AppRoleAssignments.Add($BodyParameter.ResourceId)
    $global:mockAppAssignments.Add($BodyParameter)
    Note-Mutation "assign-app"
}
function Get-MgUserAppRoleAssignment { param([string]$UserId, [switch]$All)
    $u = $global:mockUsers | Where-Object { $_.Id -eq $UserId }
    if ($u -and $u.PSObject.Properties['AppRoleAssignments']) { return @($u.AppRoleAssignments | ForEach-Object { [pscustomobject]@{ Id = "app-$_"; ResourceDisplayName = $_ } }) }
    return @()
}
function Remove-MgUserAppRoleAssignment { param([string]$UserId, [string]$AppRoleAssignmentId)
    $u = $global:mockUsers | Where-Object { $_.Id -eq $UserId }
    if ($u -and $u.PSObject.Properties['AppRoleAssignments']) { $u.AppRoleAssignments.Clear() }
    Note-Mutation "remove-app-assignment"
}
function Revoke-MgUserSignInSession { param([string]$UserId) Note-Mutation "revoke-sessions" }
function Import-Module { param([string]$Name, [switch]$ErrorAction) }
function Get-MgUserMemberOf { param([string]$UserId, [switch]$All)
    # return the group objects of which the user is currently a member
    $groups = @()
    foreach ($gid in $global:mockGroupMembers.Keys) {
        if (@($global:mockGroupMembers[$gid] | Where-Object { $_.Id -eq $UserId }).Count -gt 0) {
            $g = $global:mockGroups.Values | Where-Object { $_.Id -eq $gid }
            if ($g) { $groups += $g }
        }
    }
    return $groups
}
function Invoke-MgGraphRequest {
    param([string]$Method, [string]$Uri)
    if ($Uri -match 'graph\.microsoft\.com/v1\.0/groups/(.+)/members/(.+)/\$ref$') {
        $gid, $uid = $Matches[1], $Matches[2]
        if (-not $global:mockGroupMembers.ContainsKey($gid)) { throw "Request_ResourceNotFound: group $gid" }
        $member = $global:mockGroupMembers[$gid] | Where-Object { $_.Id -eq $uid }
        if (-not $member) { throw "Request_ResourceNotFound: member reference does not exist" }
        $global:mockGroupMembers[$gid].Remove($member)
        Note-Mutation "remove-group-member"
        return
    }
    throw "Invoke-MgGraphRequest mock: unhandled URI $Uri"
}

# ---------------- Test data ----------------
$csvPath = Join-Path $tmp 'test-contractors.csv'
@"
FirstName,LastName,JobTitle,Specialty,Department,CompanyName
Rita,Marques,Helpdesk Support Engineer,Helpdesk,Cyber Security Contractors,Beginning Dimension
Bruno,Alves,Helpdesk Support Engineer,Helpdesk,Cyber Security Contractors,Beginning Dimension
Nadia,Faro,Helpdesk Support Engineer,Helpdesk,Cyber Security Contractors,Beginning Dimension
Marcus,Reyes,Identity and Access Management Engineer,IAM,Cyber Security Contractors,Beginning Dimension
Sofia,Santos,SOC Analyst,SOC,Cyber Security Contractors,Beginning Dimension
"@ | Set-Content -Path $csvPath

Push-Location $tmp   # scripts write relative-path reports; keep artifacts out of the repo

try {

# ---------------- TEST 0: Script 02 - dynamic groups ----------------
Write-Host "`nTEST 0: Script 02 (dynamic groups)" -ForegroundColor Cyan
Reset-Mocks
& "$repo/scripts/02-New-DynamicGroups.ps1" -TenantId 'tid' *> $null
$csc = $global:mockGroups['Cyber Security Contractors (Dynamic)']
$im  = $global:mockGroups['IM Staff']
Assert "dynamic contractor group created" ($null -ne $csc)
Assert "IM Staff group created"            ($null -ne $im)
Assert "contractor rule exact"  ($csc.MembershipRule -eq 'user.department -eq "Cyber Security Contractors"')
Assert "IM rule uses startsWith + department guard" ($im.MembershipRule -like '*department -eq "Cyber Security Contractors"*-and*startsWith "IM"*')
Assert "both rules processing On" ($csc.MembershipRuleProcessingState -eq 'On' -and $im.MembershipRuleProcessingState -eq 'On')
Assert "both marked DynamicMembership" ($csc.GroupTypes -contains 'DynamicMembership' -and $im.GroupTypes -contains 'DynamicMembership')

# ---------------- TEST 1: Script 01 - creation, idempotency, repair ----------------
Write-Host "`nTEST 1: Script 01 (onboarding)" -ForegroundColor Cyan
Reset-Mocks
& "$repo/scripts/01-Bulk-Create-Contractors.ps1" -TenantId 'tid' -PrimaryDomain 'lab.local' -CsvPath $csvPath *> $null
Assert "5 users created"                   ($global:mockUsers.Count -eq 5)
Assert "all password profiles force change at next sign-in" (@($global:mockPasswordProfiles | Where-Object { $_.ForceChangePasswordNextSignIn -eq $true }).Count -eq 5)
Assert "all generated passwords are 16 characters" ((@($global:mockPasswordProfiles | ForEach-Object { $_.Password.Length }) | Where-Object { $_ -eq 16 }).Count -eq 5)
$gid = $global:mockGroups['Cyber Security Contractors'].Id
Assert "parent group has 5 members"        ($global:mockGroupMembers[$gid].Count -eq 5)

& "$repo/scripts/01-Bulk-Create-Contractors.ps1" -TenantId 'tid' -PrimaryDomain 'lab.local' -CsvPath $csvPath *> $null
Assert "re-run creates no duplicates"     ($global:mockUsers.Count -eq 5)
Assert "re-run membership stable"         ($global:mockGroupMembers[$gid].Count -eq 5)

$global:mockGroupMembers[$gid].RemoveAt(0)
& "$repo/scripts/01-Bulk-Create-Contractors.ps1" -TenantId 'tid' -PrimaryDomain 'lab.local' -CsvPath $csvPath *> $null
Assert "re-run repairs missing membership" ($global:mockGroupMembers[$gid].Count -eq 5)

# ---------------- TEST 2: Script 03 - AU, role assignment, duplicates, missing ----------------
Write-Host "`nTEST 2: Script 03 (admin unit + scoped role)" -ForegroundColor Cyan
$helpdeskUpns = $global:mockUsers | Where-Object { $_.JobTitle -eq 'Helpdesk Support Engineer' } | ForEach-Object { $_.UserPrincipalName }
& "$repo/scripts/03-New-AdminUnitScopedRole.ps1" -TenantId 'tid' -HelpdeskPrincipals $helpdeskUpns *> $null
$au = $global:mockAUs['Contractors AU']
Assert "AU created"                 ($null -ne $au)
Assert "AU populated (5 members)"   ($global:mockAUMembers[$au.Id].Count -eq 5)
Assert "3 AU-scoped role assignments" ($global:mockRoleAssignments.Count -eq 3)
Assert "all assignments AU-scoped"  (@($global:mockRoleAssignments | Where-Object { $_.DirectoryScopeId -eq "/administrativeUnits/$($au.Id)" }).Count -eq 3)

& "$repo/scripts/03-New-AdminUnitScopedRole.ps1" -TenantId 'tid' -HelpdeskPrincipals $helpdeskUpns *> $null
Assert "re-run adds no duplicate assignments" ($global:mockRoleAssignments.Count -eq 3)
Assert "re-run adds no duplicate AU members"  ($global:mockAUMembers[$au.Id].Count -eq 5)

# missing principal now FAILS the run (privileged assignment must not guess)
$before = $global:mockRoleAssignments.Count
$threwMissing = $false
try { & "$repo/scripts/03-New-AdminUnitScopedRole.ps1" -TenantId 'tid' -HelpdeskPrincipals @('ghost.user@lab.local') *> $null }
catch { $threwMissing = $true }
Assert "missing UPN throws and assigns nothing" ($threwMissing -and $global:mockRoleAssignments.Count -eq $before)

# ambiguous UPN (two users with the same UPN in the directory) also fails the run
$dup = [pscustomobject]@{ Id = 'dup-id'; UserPrincipalName = 'rita.marques@lab.local'; AccountEnabled = $true }
$global:mockUsers.Add($dup)
$threwAmbiguous = $false
try { & "$repo/scripts/03-New-AdminUnitScopedRole.ps1" -TenantId 'tid' -HelpdeskPrincipals @('rita.marques@lab.local') *> $null }
catch { $threwAmbiguous = $true }
Assert "ambiguous UPN throws and assigns nothing" ($threwAmbiguous)
$global:mockUsers.Remove($dup)

# ---------------- TEST 3: Script 05 - app assignment, ambiguity, roles ----------------
Write-Host "`nTEST 3: Script 05 (app assignment)" -ForegroundColor Cyan
# SP with NO declared roles -> all-zeros default allowed
$sp1 = [pscustomobject]@{ Id = 'sp-toolkit'; DisplayName = 'Entra SAML Toolkit'; AppRoles = @() }
$global:mockSPs[$sp1.Id] = $sp1
$twoUsers = @('sofia.santos@lab.local','marcus.reyes@lab.local')
& "$repo/scripts/05-Assign-UsersToApp.ps1" -TenantId 'tid' -AppDisplayName 'Entra SAML Toolkit' -UserUpns $twoUsers *> $null
Assert "2 users assigned to app" (($global:mockUsers | Where-Object { $_.PSObject.Properties['AppRoleAssignments'] -and $_.AppRoleAssignments -contains 'sp-toolkit' }).Count -eq 2)
Assert "all-zeros app role used" (@($global:mockAppAssignments | Where-Object { $_.AppRoleId -eq '00000000-0000-0000-0000-000000000000' }).Count -eq 2)

& "$repo/scripts/05-Assign-UsersToApp.ps1" -TenantId 'tid' -AppDisplayName 'Entra SAML Toolkit' -UserUpns $twoUsers *> $null
Assert "re-run skips without duplicates" (($global:mockUsers | Where-Object { $_.PSObject.Properties['AppRoleAssignments'] -and $_.AppRoleAssignments -contains 'sp-toolkit' }).Count -eq 2)

# missing user: reported FAILED, run continues
$missingOut = Join-Path $tmp 't3-missing.txt'
& "$repo/scripts/05-Assign-UsersToApp.ps1" -TenantId 'tid' -AppDisplayName 'Entra SAML Toolkit' -UserUpns @('ghost@lab.local') *> $missingOut
Assert "missing user reported FAILED (not skipped)" ((Get-Content $missingOut -Raw) -match 'FAILED \(user not found\): ghost@lab\.local')

# ambiguous display name: throws
$global:mockSPs['sp-dup1'] = [pscustomobject]@{ Id = 'sp-dup1'; DisplayName = 'Ambiguous App'; AppRoles = @() }
$global:mockSPs['sp-dup2'] = [pscustomobject]@{ Id = 'sp-dup2'; DisplayName = 'Ambiguous App'; AppRoles = @() }
$threw = $false
try { & "$repo/scripts/05-Assign-UsersToApp.ps1" -TenantId 'tid' -AppDisplayName 'Ambiguous App' -UserUpns $twoUsers *> $null }
catch { $threw = $true }
Assert "ambiguous SP name fails loudly" ($threw)

# SP with a declared USER role: default all-zeros rejected, named role required
$roleSp = [pscustomobject]@{ Id = 'sp-roles'; DisplayName = 'Roles App'
    AppRoles = @([pscustomobject]@{ Id = 'role-1'; DisplayName = 'Reader'; IsEnabled = $true; AllowedMemberTypes = @('User') }) }
$global:mockSPs['sp-roles'] = $roleSp
$threw2 = $false
try { & "$repo/scripts/05-Assign-UsersToApp.ps1" -TenantId 'tid' -AppDisplayName 'Roles App' -UserUpns $twoUsers *> $null }
catch { $threw2 = $true }
Assert "declared roles without selection rejected" ($threw2)
$global:mockAppAssignments.Clear()
& "$repo/scripts/05-Assign-UsersToApp.ps1" -TenantId 'tid' -AppDisplayName 'Roles App' -AppRoleDisplayName 'Reader' -UserUpns $twoUsers *> $null
Assert "named app role assignment uses the role's ID" (@($global:mockAppAssignments | Where-Object { $_.AppRoleId -eq 'role-1' }).Count -eq 2)

# SP with DISABLED-only roles: all-zeros still rejected (roles are declared)
$disabledSp = [pscustomobject]@{ Id = 'sp-disabled'; DisplayName = 'Disabled App'
    AppRoles = @([pscustomobject]@{ Id = 'role-d'; DisplayName = 'Reader'; IsEnabled = $false; AllowedMemberTypes = @('User') }) }
$global:mockSPs['sp-disabled'] = $disabledSp
$threw3 = $false
try { & "$repo/scripts/05-Assign-UsersToApp.ps1" -TenantId 'tid' -AppDisplayName 'Disabled App' -UserUpns $twoUsers *> $null }
catch { $threw3 = $true }
Assert "disabled-only roles still reject all-zeros" ($threw3)

# SP with APPLICATION-only roles: all-zeros still rejected
$appOnlySp = [pscustomobject]@{ Id = 'sp-apponly'; DisplayName = 'AppOnly App'
    AppRoles = @([pscustomobject]@{ Id = 'role-a'; DisplayName = 'Daemon'; IsEnabled = $true; AllowedMemberTypes = @('Application') }) }
$global:mockSPs['sp-apponly'] = $appOnlySp
$threw4 = $false
try { & "$repo/scripts/05-Assign-UsersToApp.ps1" -TenantId 'tid' -AppDisplayName 'AppOnly App' -UserUpns $twoUsers *> $null }
catch { $threw4 = $true }
Assert "app-only roles still reject all-zeros" ($threw4)

# ---------------- TEST 4: Script 07 - offboarding order, PIM, -WhatIf ----------------
Write-Host "`nTEST 4: Script 07 (offboarding)" -ForegroundColor Cyan
$target = $global:mockUsers | Where-Object { $_.UserPrincipalName -eq 'nadia.faro@lab.local' }
# Role grants exist (standing + PIM schedules) - the script must NOT touch any of them:
# role cleanup is deliberately manual (partial automation), so these must survive the run.
$global:mockRoleAssignments.Add([pscustomobject]@{ Id = 'ra-1'; RoleDefinitionId = 'rd-1'; PrincipalId = $target.Id; DirectoryScopeId = '/' })
$global:mockEligible.Add([pscustomobject]@{ RoleDefinitionId = 'rd-2'; DirectoryScopeId = '/'; PrincipalId = $target.Id })
$global:mockActive.Add([pscustomobject]@{ RoleDefinitionId = 'rd-3'; DirectoryScopeId = '/'; PrincipalId = $target.Id })
$rolesBefore = $global:mockRoleAssignments.Count

# give nadia a direct app assignment so the app-removal step is exercised
$target | Add-Member -NotePropertyName AppRoleAssignments -NotePropertyValue ([System.Collections.Generic.List[string]]::new()) -Force
$target.AppRoleAssignments.Add('sp-toolkit')

# -WhatIf: nothing mutates
$beforeMutations = $global:mockMutations
$nadiaAssignmentsBefore = @($global:mockRoleAssignments | Where-Object { $_.PrincipalId -eq $target.Id }).Count
& "$repo/scripts/07-Offboard-User.ps1" -TenantId 'tid' -UserPrincipalName 'nadia.faro@lab.local' -WhatIf *> $null
Assert "-WhatIf performs no mutations" ($global:mockMutations -eq $beforeMutations)
Assert "-WhatIf leaves account enabled" ($target.AccountEnabled -eq $true)
Assert "-WhatIf leaves role assignments" (@($global:mockRoleAssignments | Where-Object { $_.PrincipalId -eq $target.Id }).Count -eq $nadiaAssignmentsBefore)
Assert "-WhatIf leaves PIM schedules" ($global:mockEligible.Count -eq 1 -and $global:mockActive.Count -eq 1)

# real run: order + full revocation
$global:mockMutationLog.Clear()
& "$repo/scripts/07-Offboard-User.ps1" -TenantId 'tid' -UserPrincipalName 'nadia.faro@lab.local' *> $null
Assert "account disabled"             ($target.AccountEnabled -eq $false)
$labels = @($global:mockMutationLog)
$disableIdx = [array]::IndexOf($labels, 'update-user')          # step 1 (disable)
$revokeIdx  = [array]::IndexOf($labels, 'revoke-sessions')       # step 2
$appIdx     = [array]::IndexOf($labels, 'remove-app-assignment') # step 3
$roleIdx    = [array]::IndexOf($labels, 'remove-role-assignment') # step 4
Assert "order: disable before revoke sessions" ($disableIdx -lt $revokeIdx -and $disableIdx -ge 0)
Assert "order: revoke sessions before app removal" ($revokeIdx -lt $appIdx -and $revokeIdx -ge 0)
Assert "script does NOT delete role assignments (manual step)" ($global:mockRoleAssignments.Count -eq $rolesBefore -and $roleIdx -lt 0)
Assert "script does NOT submit PIM AdminRemove requests" ($global:mockRequests.Count -eq 0)
Assert "PIM schedules untouched" ($global:mockEligible.Count -eq 1 -and $global:mockActive.Count -eq 1)
$noticeOut = Join-Path $tmp 't4-notice.txt'
& "$repo/scripts/07-Offboard-User.ps1" -TenantId 'tid' -UserPrincipalName 'nadia.faro@lab.local' *> $noticeOut
Assert "run prints the manual role-cleanup notice" ((Get-Content $noticeOut -Raw) -match 'ROLE CLEANUP NOT AUTOMATED')
Assert "app assignments stripped"       (-not ($target.PSObject.Properties['AppRoleAssignments'] -and $target.AppRoleAssignments -contains 'sp-toolkit'))
Assert "group membership removal invoked" ($labels -contains 'remove-group-member')
$gid2 = $global:mockGroups['Cyber Security Contractors'].Id
Assert "membership actually removed from the group store" ((@($global:mockGroupMembers[$gid2] | Where-Object { $_.Id -eq $target.Id })).Count -eq 0)
Assert "not deleted (no -DeleteUser)"   ($global:mockUsers.Contains($target))

# deletion only with explicit opt-in - and the repeat run must survive the already-removed
# membership (pre-check skips the DELETE instead of failing on the absent reference)
$secondRunThrew = $false
try { & "$repo/scripts/07-Offboard-User.ps1" -TenantId 'tid' -UserPrincipalName 'nadia.faro@lab.local' -DeleteUser *> $null }
catch { $secondRunThrew = $true }
Assert "repeat offboarding run succeeds despite absent membership" (-not $secondRunThrew)
Assert "-DeleteUser removes the account" (-not $global:mockUsers.Contains($target))

} finally {
    Pop-Location
}

# ---------------- Summary ----------------
Write-Host "`nRESULTS: $global:pass passed, $global:fail failed" -ForegroundColor Cyan
exit ($global:fail -gt 0 ? 1 : 0)
