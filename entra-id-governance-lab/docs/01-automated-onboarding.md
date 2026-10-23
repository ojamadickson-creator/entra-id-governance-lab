# Phase 1 — Automated Onboarding (PowerShell + Microsoft Graph)

> Phase series: [0](00-prerequisites-and-verification.md) · [1](01-automated-onboarding.md) · [2](02-dynamic-membership.md) · [3](03-administrative-units.md) · [4](04-pim-and-role-governance.md) · [5](05-enterprise-application-access.md) · [6](06-access-reviews.md) · [7](07-offboarding-and-cleanup.md)

## Objective & Scope

Provision the 20-contractor identity cohort from a structured CSV using Microsoft Graph
PowerShell — with standardized attributes, randomized temporary passwords that must be changed
at first sign-in, and color-coded execution telemetry.

**Scope:** scope selection and consent, parent group verification, bulk user creation loop,
status logging. Role assignment happens in Phases 3–4.

## Prerequisites

- [Phase 0](00-prerequisites-and-verification.md) completed.
- Operator role: **User Administrator** (or Global Administrator in the lab tenant).
- Delegated Graph scopes for this exercise: `User.ReadWrite.All`, `Group.ReadWrite.All`.
- `data/contractors.csv` prepared and reviewed.



## Step-by-Step Execution

### 1. Authenticate with the required scopes

```powershell
Connect-MgGraph -TenantId $TenantId `
  -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All' -NoWelcome
```

During interactive sign-in, Microsoft Entra ID prompts the operator to consent to the requested
**delegated permissions**. If scopes are omitted, API authorization calls fail mid-execution
with `403 Forbidden` when the script writes directory objects.

### 2. Verify (or create) the parent group

```powershell
$group = Get-MgGroup -Filter "displayName eq 'Cyber Security Contractors'" -Top 1
if (-not $group) {
    $group = New-MgGroup -DisplayName 'Cyber Security Contractors' `
        -Description 'Parent group for cyber security contractor cohort' `
        -MailEnabled:$false -MailNickname 'csc-contractors' `
        -SecurityEnabled -GroupTypes @()
}
```

The script checks for the target group and for existing UPNs before the creation loop, so
re-runs are safe and **repair missing group memberships** for users created earlier.

> **Note:** group members are added with the documented `@odata.id` reference body
> (`New-MgGroupMemberByRef -GroupId <id> -BodyParameter @{ '@odata.id' =
> 'https://graph.microsoft.com/v1.0/directoryObjects/<object-id>' }`), per
> [Add members (Microsoft Graph)](https://learn.microsoft.com/en-us/graph/api/group-post-members?view=graph-rest-1.0).

### How to prepare the script in Azure
Azure Cloud Shell includes a built-in Upload button and a file system, so you don't need any complex setup.

Step 1: Upload the CSV File to Azure Cloud Shell
On your local computer, create or save your contractors.csv file using Notepad or Excel.

In your browser where Azure Cloud Shell is open, look at the top toolbar.

Click the Upload/Download icon (it looks like an arrow pointing up and down).

Click Upload.

Select contractors.csv from your local machine.

By default, the uploaded file will land in your root user folder inside Cloud Shell (/home/yourusername or C:\Users\CloudUser).
The run these commands and move the file to match the path below in step three
Step 1: Create the data folder
```powershell
New-Item -ItemType Directory -Path '.\data' -Force
```
Step 2: Move and Rename the uploaded file(make sure you use the path created during your upload)
```powershell
Move-Item -Path '/home/akpoga/contractors.sample.csv' -Destination '.\data\contractors.csv' -Force
```
```powershell
Test-Path '.\data\contractors.csv'
```
Create the scripts folder:
```powershell
New-Item -ItemType Directory -Path './scripts' -Force
```
Paste the script code directly using the built-in Editor
Run this command to open the Azure Cloud Shell editor:
```powershell
code ./scripts/01-Bulk-Create-Contractors.ps1
```
A code editor window will pop up at the top. Paste your script code into the editor.

Press Ctrl + S to save, then Ctrl + Q to close the editor window.
Do the same for the rest
```powershell
code ./scripts/02-New-DynamicGroups.ps1
```
```powershell
code ./scripts/03-New-AdminUnitScopedRole.ps1
```
```powershell
code ./scripts/05-Assign-UsersToApp.ps1
```
```powershell
code ./scripts/07-Offboard-User.ps1
```

### 3. Run the bulk creation loop

Run the prepared script:

```powershell
.\scripts\01-Bulk-Create-Contractors.ps1 `
  -TenantId $TenantId `
  -PrimaryDomain 'beginningdimension.com' `
  -CsvPath '.\data\contractors.csv'
```

What each iteration does (see the script for the full source):

1. Builds the UPN (`first.last@domain`) and checks for collisions — existing UPNs are
   **skipped** (yellow), not overwritten.
2. Generates a randomized 16-character temporary password.
3. Creates the user with the CSV attributes:

```powershell
$passwordProfile = @{
    Password                      = $password
    ForceChangePasswordNextSignIn = $true
}

New-MgUser -DisplayName "$givenName $surname" `
    -GivenName $givenName -Surname $surname `
    -UserPrincipalName $upn `
    -AccountEnabled:$true `
    -JobTitle $row.JobTitle `
    -Department $row.Department `
    -CompanyName $row.CompanyName `
    -MailNickname ($upn -split '@')[0] `
    -UsageLocation 'PT' `
    -PasswordProfile $passwordProfile
```

4. Adds the user to the parent group (`New-MgGroupMemberByRef`).
5. Emits color-coded telemetry — green for created, yellow for skipped (UPN collision),
   red for failed — and writes a status CSV report (no passwords).

### 4. Deliver initial credentials securely

Communicate temporary passwords through a secure out-of-band channel. When each contractor
first signs in (for example at `myapps.microsoft.com`), Entra ID intercepts the session and
mandates a password change before access is granted.

> **Operational note:** the script deliberately does not retain the generated passwords —
> you cannot "look them up later." If a temporary password is lost before first sign-in,
> reset it as the administrator (portal: **Users > [user] > Reset password**, or
> `Update-MgUser -PasswordProfile`).

## Validation

- [ ] The summary reports `Created: 20` (or expected skip/repair counts on re-run).
- [ ] `Get-MgUser -Filter "department eq 'Cyber Security Contractors'"` returns 20 users.
- [ ] Each user shows `JobTitle`, `Department`, `CompanyName` matching the CSV.
- [ ] The parent group contains 20 members.
- [ ] A test sign-in forces the password change (do not publish the password anywhere).

## Evidence to Capture

- The script's color-coded console summary (passwords never visible).
- Entra admin center user list filtered to the contractor department.
- One user's profile page showing attributes (redact any sensitive values).

## References

- [New-MgUser (Microsoft.Graph.Users)](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users/new-mguser?view=graph-powershell-1.0)
- [Get started with the Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/get-started)
- [Assign users and groups to an application](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/assign-user-or-group-access-portal)

Next: [Phase 2 — Dynamic Membership](02-dynamic-membership.md)
