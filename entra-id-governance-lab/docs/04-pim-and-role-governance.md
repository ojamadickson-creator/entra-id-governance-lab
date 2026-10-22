# Phase 4 — Privileged Identity Management (PIM) and Just-In-Time Access

> Phase series: [0](00-prerequisites-and-verification.md) · [1](01-automated-onboarding.md) · [2](02-dynamic-membership.md) · [3](03-administrative-units.md) · [4](04-pim-and-role-governance.md) · [5](05-enterprise-application-access.md) · [6](06-access-reviews.md) · [7](07-offboarding-and-cleanup.md)

## Objective & Scope

Eliminate standing privileged access: configure Just-In-Time (JIT) elevation for the IAM
engineer, create a custom SOC log-reader role, and walk the full activation lifecycle —
request, MFA, justification, approval, timed access, and automated expiration.

**Scope:** PIM role settings, eligible assignments, the Marcus Reyes activation scenario, the
SOC Analyst custom role, and expiration behavior.

## Prerequisites

- [Phase 3](03-administrative-units.md) completed.
- Operator role: **Privileged Role Administrator** (manages PIM assignments and role settings).
- **Licensing:** PIM requires Microsoft Entra ID P2 or Entra ID Governance for users with
  eligible/time-bound assignments, approvers, and reviewers
  ([PIM license requirements](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/subscription-requirements)).

## Key Concepts

### Eligible vs. active assignments

| Assignment type | Behavior |
|---|---|
| **Eligible** | The user must perform an action (MFA check, justification, approval request) to *use* the role; until activated, the assignment grants no active permissions from it |
| **Active** | The role is active continuously without activation steps — the default for service and emergency "break-glass" accounts, though it can also be a time-bound human assignment |

Both types can be permanent or time-bound (start/end dates), and both can be extended or
renewed near expiry
([Plan a PIM deployment](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-deployment-plan)).

Two accuracy notes that correct the source breakdown:

- **Eligibility is not the absence of privileges.** An eligible assignment grants no *active*
  permissions from that assignment, but the user may hold other privileges — check the whole
  account, not one assignment.
- **Privileged Role Administrator is a highly privileged role**, not merely "one level below
  Global Administrator" — it controls role assignments, activation policies, and governance
  across Entra roles.

## Step-by-Step Execution

### 1. Configure role settings for Privileged Role Administrator

Portal: **Entra admin center > ID Governance > Privileged Identity Management > Microsoft
Entra roles > Roles > Privileged Role Administrator > Role settings > Edit**. Configure:

| Setting | Value |
|---|---|
| Activation maximum duration | **1 hour** |
| On activation, require MFA | **On** |
| On activation, require justification | **On** |
| Require approval to activate | **On** — approver: the Security Operations Lead (e.g. Elena Petrova) |
| Assignment type: eligible duration | 6 months (for the Marcus Reyes assignment) |

The activation maximum duration slider accepts **1–24 hours**
([Configure Microsoft Entra role settings in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings)).

> **MFA accuracy note:** users might not be prompted for MFA if they authenticated with strong
> credentials or completed MFA earlier in the session — MFA on activation is enforced **once
> per session**. For stricter enforcement, PIM supports *On activation, require Microsoft
> Entra Conditional Access authentication context* with Authentication Strengths
> ([PIM role settings](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings))
> — but do not treat it as a guaranteed fresh prompt either: the effective sign-in frequency
> depends on your Conditional Access sign-in frequency configuration. Verify the behavior in
> your own tenant.

### 2. Give Marcus Reyes an eligible assignment (6 months)

Portal: **ID Governance > Privileged Identity Management > Microsoft Entra roles > Roles >
Privileged Role Administrator > Add assignments**. On **Membership settings**, choose
**Assignment type: Eligible**, with start/end dates spanning six months, then **Assign**
([Assign Microsoft Entra roles in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-add-role-to-user)).

### 3. Marcus activates the role (JIT lifecycle)

Walk the documented activation flow as Marcus:

1. Sign in to the Microsoft Entra admin center and browse to
   **ID Governance > Privileged Identity Management > My roles > Microsoft Entra roles**.
2. Find **Privileged Role Administrator** under Eligible assignments and select **Activate**.
3. Complete the **Additional verification required** MFA challenge.
4. Enter the business justification (e.g. "Executing scheduled quarterly access review policy
   update for SOC contractor cohort").
5. Select the activation duration (bounded by the 1-hour maximum) and **Activate**.
6. The request is marked **pending approval**.

Full steps: [Activate a Microsoft Entra role in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-activate-role).

### 4. The approver grants authorization

As Elena Petrova (Security Operations Lead): **ID Governance > Privileged Identity Management
> Approve requests**, find the pending request, enter a justification, and **Approve**
([Approve or deny requests for Microsoft Entra roles in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-approval-workflow)).

Approval-behavior notes worth documenting:

- Approvers have **24 hours** to respond; expired requests must be resubmitted. The window is
  not configurable.
- Approvers cannot approve their own activation requests.
- With no specific approver configured, active Privileged Role Administrators and Global
  Administrators become the default approvers.

### 5. Timed access and automated expiration

On approval, Marcus's assignment shows **Active** with an expiration ~1 hour out. When the
window ends, PIM automatically revokes the active assignment and returns the account to
eligible-only state; the activation and its end are recorded in the audit logs. Just-in-time
discipline: deactivate manually when the task is done rather than holding the window.

### 6. Create the SOC Analyst custom role

When built-in roles grant too much, create a custom role containing only the required
permission strings:

1. As Privileged Role Administrator, browse to **Entra ID > Roles & admins > Roles & admins >
   New custom role**.
2. Name it **SOC Analyst Custom Role**, and select the permissions:
   - `microsoft.directory/auditLogs/allProperties/read` — inspect system audit telemetry
   - `microsoft.directory/signInReports/allProperties/read` — inspect sign-in activity and risk reports

> **Correction to the source breakdown:** the valid custom-role permission string is
> `microsoft.directory/signInReports/allProperties/read` — not `signInLogs`. The custom-role
> permission lists publish `auditLogs` and `signInReports` (see the
> [enterprise app permissions for custom roles](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-enterprise-app-permissions));
> `signInLogs` is not a valid custom-role permission string.
3. Create the role, then assign it **as an eligible assignment via PIM** to a Tier-1 SOC
   test account. Isolation note: use a test account that does **not** already hold
   Security Reader (from Phase 3) — otherwise successful log reads prove nothing about the
   custom role. Keep the Security Reader accounts and the custom-role test account separate
   throughout the lab.

Permission strings for custom roles are documented in
[Built-in roles permissions reference](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference);
creating custom roles requires at least Privileged Role Administrator.

### 7. Optional — configure role settings via Graph

PIM role settings are `unifiedRoleManagementPolicy` rules, updatable via Graph with the
`RoleManagementPolicy.ReadWrite.Directory` delegated permission
([Update rules in PIM by using Microsoft Graph](https://learn.microsoft.com/en-us/graph/how-to-pim-update-rules)) —
for example, setting the activation maximum duration to `PT1H`.

## Validation

- [ ] Marcus shows an **Eligible** Privileged Role Administrator assignment with a 6-month window.
- [ ] Role settings show 1-hour max activation, MFA, justification, and approval required.
- [ ] Activation requires MFA + justification and stays pending until approved.
- [ ] The active assignment expires (or is deactivated) and returns to eligible-only.
- [ ] The custom SOC role contains exactly the two log-read permission strings
      (`auditLogs` and `signInReports`).
- [ ] A Tier-1 SOC account can read audit/sign-in logs but cannot modify anything.

## Evidence to Capture

- PIM role settings page for Privileged Role Administrator.
- Marcus's eligible assignment (assignment type and duration visible).
- The pending-approval state, and the active assignment with expiration time.
- The custom role definition with its permission list.

## References

- [What is Privileged Identity Management?](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-configure)
- [Plan a Privileged Identity Management deployment](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-deployment-plan)
- [Assign Microsoft Entra roles in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-add-role-to-user)
- [Configure Microsoft Entra role settings in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings)
- [Activate a Microsoft Entra role in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-activate-role)
- [Approve or deny requests for Microsoft Entra roles in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-approval-workflow)
- [Microsoft Entra built-in roles permissions reference](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference)
- [Enterprise application permissions for custom roles](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-enterprise-app-permissions)

Next: [Phase 5 — Enterprise Application Access](05-enterprise-application-access.md)
