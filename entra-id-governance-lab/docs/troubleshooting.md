# Troubleshooting — Anticipated Problems & Diagnostics

This lab is documentation-verified rather than tenant-executed, so this section records
**anticipated failure modes** for each phase — the problems you are most likely to hit when
running the lab, with their documented diagnostic paths. As you execute the lab, replace
these with your actual observed incidents (symptom → root cause → resolution).

---

## 1. `Connect-MgGraph` consent and scope failures

**Symptom:** API calls fail mid-execution with `403 Forbidden` (insufficient privileges) or the
cmdlet rejects a parameter.

**Diagnosis/fix:**

- Check `Get-MgContext` — verify the tenant, account, and **consented scopes** match the
  phase's required scopes.
- Request the exact scopes for the exercise (`-Scopes 'User.ReadWrite.All', ...`) rather than
  broad defaults; consent prompts appear when a scope is first requested.
- Remember the two layers: Graph **consent** (permissions of the session) and the operator's
  **Entra role** (directory authority). A fully consented session still fails if the operator
  lacks the role (e.g. Privileged Role Administrator for role assignments).

## 2. Bulk onboarding failures

**Symptom:** `New-MgUser` fails per user; or users are created but the loop reports red.

**Diagnosis/fix:**

- **UPN domain not verified** — the UPN suffix must be a verified domain in the tenant.
- **UPN collisions** — the script skips existing UPNs (yellow); on re-runs this is expected.
- **License/attribute errors** — check the error body: e.g. invalid `UsageLocation`, password
  policy violations (the generator emits compliant passwords), or directory quota.
- **429 throttling** — back off and retry with jitter; avoid tight read loops (see Phase 5
  caching).

## 3. Dynamic group membership is empty or stale

**Symptom:** the dynamic group has no members, or membership does not change after an
attribute update.

**Diagnosis/fix:**

- Membership processing is **asynchronous** — allow minutes, then re-check. The group's
  **Membership processing status** (portal) shows `Processing pending` while rules evaluate.
- Verify the rule references the correct property values (`user.department -eq "Cyber Security
  Contractors"` must match the CSV value — string comparisons in dynamic rules are
  case-insensitive, but spacing and spelling must match exactly).
- Confirm **P1 licensing** covers the unique users in dynamic groups — licensing is a
  documented compliance requirement for dynamic membership; verify license state as
  part of diagnosing any membership evaluation problem.
- Query the tenant **audit logs** for "Add member to group" to confirm the engine acted.

## 4. Administrative unit role assignment problems

**Symptom:** you cannot scope a role to an AU, or the scoped admin cannot act.

**Diagnosis/fix:**

- **Role not AU-scopable:** only a documented list of roles supports AU scope (Helpdesk,
  User, Groups Administrators, etc.). Security Reader/Security Administrator cannot be scoped —
  assign them at tenant scope instead.
- **Custom roles** must include at least one permission relevant to users/groups/devices to be
  AU-scopable, and are assigned *from inside the AU*, not from Roles & admins.
- **Admin-target restriction:** AU-scoped Helpdesk admins cannot reset passwords of users who
  hold administrator roles — test with a non-admin target.
- **Licensing:** AU-scoped role assignment requires P1 for each AU administrator.

## 5. PIM activation does not behave as expected

**Symptom:** no MFA prompt at activation; approval never arrives; the role does not expire.

**Diagnosis/fix:**

- **MFA is once per session** — a user who recently completed MFA may not be re-prompted.
  Conditional Access authentication context with Authentication Strengths is the
  stricter option, but it is not a guaranteed fresh prompt either: the effective sign-in
  frequency depends on your Conditional Access sign-in frequency configuration. Verify
  the behavior in your own tenant.
- **Approvals expire after 24 hours** (not configurable) — resubmit expired requests; check
  the designated approver exists and is active; approvers cannot approve their own requests.
- **Activation maximum duration** is 1–24 hours; the actual duration is chosen by the user at
  activation within that cap. Verify the role settings if 1 hour is intended.
- **License check:** PIM requires P2/Governance for eligible users, approvers, and reviewers.

## 6. App assignment failures

**Symptom:** `New-MgUserAppRoleAssignment` fails; or users cannot see/sign in to the app.

**Diagnosis/fix:**

- Verify all three identifiers (PrincipalId, ResourceId, AppRoleId) come from the service
  principal — not display names. Apps without declared roles use the default all-zeros app
  role ID.
- Check the app's **Properties**: sign-in blocked (Enabled for sign-in = No), or the user is
  not assigned while **Assignment required = Yes**. Global Administrators bypass
  assignment-required.
- **My Apps tile missing:** only assigned users see the app tile; visibility ≠ authorization.
- **429 throttling on bulk assignment:** caching removes redundant reads, but POSTs can still
  throttle — retry with backoff.

## 7. Access review decisions not applying

**Symptom:** denied users keep their access.

**Diagnosis/fix:**

- **Dynamic groups:** review decisions cannot change rule-driven membership — use a static
  group for removal exercises; verify dynamic rules separately.
- **Results not applied yet:** with auto-apply disabled, an administrator must select
  **Apply** after completion; removal takes effect within a few minutes.
- **Nested groups / synced groups:** members through nested groups are not removed from the
  nested group; on-premises-synced groups cannot be managed in Entra ID at all.

## 8. Session revocation is not instantaneous

**Symptom:** a "revoked" user still appears signed in.

**Diagnosis/fix:**

- `Revoke-MgUserSignInSession` invalidates refresh tokens and browser session cookies; already
  issued access tokens may remain valid until expiry, and application-controlled sessions are
  not terminated. Propagation can take a few minutes. For immediate lockout, ensure the
  account is **disabled** first (new authentication blocked at the identity provider).

---

## References

- [Get started with the Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/get-started)
- [Manage rules for dynamic membership groups](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-membership)
- [Assign Microsoft Entra roles with administrative unit scope](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-assign-powershell)
- [Configure Microsoft Entra role settings in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings)
- [Complete an access review of groups & applications](https://learn.microsoft.com/en-us/entra/id-governance/complete-access-review)
- [Revoke user access in an emergency](https://learn.microsoft.com/en-us/entra/identity/users/users-revoke-access)

Back to: [README](../README.md)
