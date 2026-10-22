# Phase 7 — Offboarding & Cleanup

> Phase series: [0](00-prerequisites-and-verification.md) · [1](01-automated-onboarding.md) · [2](02-dynamic-membership.md) · [3](03-administrative-units.md) · [4](04-pim-and-role-governance.md) · [5](05-enterprise-application-access.md) · [6](06-access-reviews.md) · [7](07-offboarding-and-cleanup.md)

## Objective & Scope

Deprovision a contractor identity safely when the engagement ends: block authentication
immediately, strip entitlements, and optionally delete the account — following Microsoft's
documented revocation sequence.

**Scope:** the offboarding sequence (portal and PowerShell), its accuracy limits, and lab
cleanup.

## Prerequisites

- Phases 1–6 completed (the cohort has group memberships, AU membership, role assignments,
  and app assignments to remove).
- Operator role: **User Administrator** for the automated portion — the Graph API reference
  for [Delete appRoleAssignment](https://learn.microsoft.com/en-us/graph/api/user-delete-approleassignments?view=graph-rest-1.0)
  explicitly lists User Administrator among the least-privileged roles supported for that
  operation; the manual role-cleanup step requires **Privileged Role Administrator** (or a
  role allowed to manage the assignments in question).
- Delegated Graph scopes (matching the partial-automation script): `User.ReadWrite.All`,
  `AppRoleAssignment.ReadWrite.All`, and `Group.ReadWrite.All` for the parent-group
  membership removal.

## The Documented Sequence (correction to the source breakdown)

Microsoft's emergency access-revocation guidance disables the account and revokes sessions
**early** — before finishing entitlement removal — so that new authentication is blocked while
cleanup proceeds ([Revoke user access in an emergency](https://learn.microsoft.com/en-us/entra/identity/users/users-revoke-access)):

```text
[1. Disable account (AccountEnabled = $false)]   <- blocks new authentication FIRST
[2. Revoke sessions (refresh tokens + cookies)]  <- kills existing sessions EARLY
[3. Strip app assignments]
[3b. Remove group memberships (group-derived access)]
[4. Revoke directory roles - MANUAL portal procedure: standing, PIM-active, PIM-eligible]
[5. Delete the account (OPTIONAL - after retention checks AND step 4 verified)]
```

The offboarding script (`scripts/07-Offboard-User.ps1`) is **partial automation**: it performs
steps 1, 2, 3, and 3b, prints a notice for step 4, and only deletes the account when you
opt in with `-DeleteUser`. Role cleanup is deliberately not automated (see step 3 below).

Two accuracy notes that correct the source breakdown:

- **`Revoke-MgUserSignInSession` is not an instant global sign-out.** It invalidates all
  refresh tokens issued to applications and browser session cookies by resetting
  `signInSessionsValidFromDateTime`. Already-issued **access tokens may remain valid until
  they expire**, and application-controlled sessions are not terminated by this operation.
  Propagation can take a few minutes
  ([user: revokeSignInSessions](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0)).
- **Account deletion is the last, optional step** — deleted users are recoverable for 30 days
  by default, but deletion belongs after retention checks, not as the first action.

## Step-by-Step Execution

### Steps 1–2. Disable the account and revoke sessions

Portal: **Entra ID > Users > [user] > Account status > Edit > clear Account enabled > Save**,
then **Overview > Revoke sessions**.

PowerShell (Microsoft's documented order):

```powershell
$User = Get-MgUser -Filter "userPrincipalName eq 'nadia.faro@beginningdimension.com'"
Update-MgUser -UserId $User.Id -AccountEnabled:$false

Import-Module Microsoft.Graph.Users.Actions
Revoke-MgUserSignInSession -UserId $User.Id
```

`Revoke-MgUserSignInSession` lives in the **Microsoft.Graph.Users.Actions** module; its
least-privileged delegated permission is `User.RevokeSessions.All`
([Revoke-MgUserSignInSession](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users.actions/revoke-mgusersigninsession?view=graph-powershell-1.0)).

### Step 3. Strip application assignments

```powershell
$assignments = Get-MgUserAppRoleAssignment -UserId $User.Id -All
foreach ($a in $assignments) {
    Remove-MgUserAppRoleAssignment -UserId $User.Id -AppRoleAssignmentId $a.Id
}
```

### Step 4. Revoke administrative roles (MANUAL portal procedure — mandatory)

Remove three kinds of grants: **standing assignments**, **PIM-managed active** assignments, and
**PIM-eligible** assignments. This step is deliberately NOT automated in the offboarding
script, and you should not attempt it with plain `Remove-MgRoleManagementDirectoryRoleAssignment`
deletes either:

> **Why not automate:** this implementation has not verified a reliable discriminator between
> PIM-managed and standing assignments in the plain role-assignment list, and a destructive
> delete must not depend on a heuristic. (Graph `AdminRemove` schedule requests exist as the
> documented API path for PIM grants — see
> [Manage Microsoft Entra role assignments using the PIM APIs](https://learn.microsoft.com/en-us/graph/api/resources/privilegedidentitymanagementv3-overview?view=graph-rest-1.0) —
> but this lab's procedure is the portal path below, which covers both assignment types and
> gives you a visual confirmation.)

Perform the removal in the PIM console — cover **both** assignment tabs
([Update or remove an existing role assignment](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-add-role-to-user)):

1. **ID Governance > Privileged Identity Management > Microsoft Entra roles > Roles >**
   select each role the user holds, find the user's assignment on the **Active roles** tab,
   and select **Remove**.
2. Repeat on the **Eligible roles** tab for the same roles.
3. For **standing** (non-PIM) tenant-scoped assignments, remove them per
   [Remove Microsoft Entra role assignments](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-remove-assignment):
   **Entra ID > Roles & admins** > select the role name > check the user > **Remove
   assignment** > confirm **Yes**. (With P2/PIM the experience may route you into the PIM
   flow instead — that page notes this.)
4. For the **AU-scoped** Helpdesk Administrator created in Phase 3, remove it where it was
   assigned — under **Entra ID > Roles & admins > Admin units > Contractors AU > Roles and
   administrators > Helpdesk Administrator** (the documented admin-unit role-management
   location, [Assign Microsoft Entra roles](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/manage-roles-portal)).
5. **Confirm:** re-check the PIM **Active roles** and **Eligible roles** tabs for each role,
   the role's assignment list under Roles & admins, and the AU's role list — the user must be
   absent from all of them before account deletion below.

Account deletion (step 5 below) comes **after** this manual role-cleanup step is complete and
verified.

### Step 3b. Remove group memberships (group-derived access)

The steps above remove **direct** grants. Access derived from group membership (group-assigned
apps, role-assignable groups) persists until the memberships are removed.

```powershell
# Pre-check membership (the reference may already be gone), then the documented REST form:
# DELETE /groups/{id}/members/{directoryObjectId}/$ref
$group = Get-MgGroup -Filter "displayName eq 'Cyber Security Contractors'" -Top 1
$isMember = @(Get-MgUserMemberOf -UserId $User.Id -All | Where-Object { $_.Id -eq $group.Id }).Count -gt 0
if ($isMember) {
    Invoke-MgGraphRequest -Method Delete -Uri "https://graph.microsoft.com/v1.0/groups/$($group.Id)/members/$($User.Id)/`$ref"
}
```

Audit any other memberships with `Get-MgUserMemberOf -UserId $User.Id -All` and remove or
leave them per your retention policy.

> **Dynamic-group caveat:** removing the static parent-group membership does not remove
> the user from the Phase 2 *dynamic* groups — a disabled user still matches the unchanged
> department rule. If the user was granted app access through a dynamic group, also change
> the membership-driving attribute (for example set `Department` to "Former Contractor")
> and wait for the rule to re-evaluate before expecting that access to disappear.

### Step 5. (Optional) Delete the directory account

Only after retention checks **and after the manual role-cleanup step above is complete and
verified in the PIM console** — the deleted user is recoverable for 30 days by default:

```powershell
Remove-MgUser -UserId $User.Id
```

### 5. Run the offboarding script (partial automation)

Work the offboarding as a **two-pass workflow**:

1. **First pass — automated portion, no deletion:** run the script WITHOUT `-DeleteUser`.
   It automates steps 1, 2, 3, and 3b and prints the manual notice for step 4.
2. **Manual cleanup:** perform step 4 (role removal) via the portal procedure above and
   verify the user is absent from every assignment list.
3. **Second pass — optional deletion:** only then run with `-DeleteUser` (the script warns
   that the manual role cleanup must be complete and verified first). The script cannot
   enforce that prerequisite — the verification is on you:

```powershell
.\scripts\07-Offboard-User.ps1 -TenantId $TenantId `
  -UserPrincipalName 'nadia.faro@beginningdimension.com'
```

### 6. Lab cleanup (end of project)

When retiring the whole lab: offboard the cohort (or delete the trial tenant outright).
Prefer tenant deletion for a throwaway trial — it is faster and leaves no residue.

## Validation

- [ ] The user shows **Sign-in blocked** / Account enabled = No.
- [ ] `Revoke-MgUserSignInSession` returned success (refresh tokens invalidated).
- [ ] No app role assignments remain for the user.
- [ ] Role cleanup performed via the mandatory portal procedure — Active **and** Eligible
      assignment lists checked and the user absent from both (verified in the PIM console).
- [ ] Lab parent-group membership removed; other memberships audited.
- [ ] Audit logs record the disable, revoke-sessions, and removal activities.
- [ ] (If deleted) deletion came after the verified role cleanup; the user appears in
      **Deleted users**, recoverable for 30 days.

## Evidence to Capture

- The user's profile showing Account enabled = No and the Revoke sessions action.
- The script's step-by-step output (no secrets).
- Audit log entries for the revocation sequence.

## References

- [Revoke user access in an emergency](https://learn.microsoft.com/en-us/entra/identity/users/users-revoke-access)
- [Revoke-MgUserSignInSession (Microsoft.Graph.Users.Actions)](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users.actions/revoke-mgusersigninsession?view=graph-powershell-1.0)
- [user: revokeSignInSessions (Microsoft Graph v1.0)](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0)

Next: [Troubleshooting](troubleshooting.md) · [Validation Checklist](validation-checklist.md)
