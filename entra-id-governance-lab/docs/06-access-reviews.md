# Phase 6 — Continuous Compliance: Access Reviews

> Phase series: [0](00-prerequisites-and-verification.md) · [1](01-automated-onboarding.md) · [2](02-dynamic-membership.md) · [3](03-administrative-units.md) · [4](04-pim-and-role-governance.md) · [5](05-enterprise-application-access.md) · [6](06-access-reviews.md) · [7](07-offboarding-and-cleanup.md)

## Objective & Scope

Enforce continuous compliance: create recurring access reviews over group membership and
application assignments, use decision helpers and the My Access portal, and apply results —
including automatic removal of denied users.

**Scope:** group access review (static group), application access review, reviewer workflows,
decision helpers, completion and application of results.

## Prerequisites

- Phases 1–5 completed.
- Creator role: **Identity Governance Administrator** or **User Administrator**
  ([Manage user and guest user access with access reviews](https://learn.microsoft.com/en-us/entra/id-governance/manage-access-review)).
- **Licensing:** access reviews require Microsoft Entra ID Governance (some capabilities on
  P2) for all users in scope, reviewers included
  ([What are access reviews?](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-overview)).
- Reviewers must be active users with email addresses.

## Critical Limitation (correction to the source breakdown)

**Access review decisions do not change membership in dynamic groups.** Dynamic groups are
rule-driven, so denied users remain members as long as they match the rule
([Complete an access review](https://learn.microsoft.com/en-us/entra/id-governance/complete-access-review)).
The same applies to groups synced from on-premises directories and nested-group membership.

Consequences for this lab:

- The **removal exercise uses a static (assigned) group** — the Phase 1 parent group
  "Cyber Security Contractors" is ideal.
- The Phase 2 **dynamic groups remain the attribute-driven organization layer** — to "review"
  them, verify the *rules* (who matches, who should) rather than expect per-member removal.

## Step-by-Step Execution

### 1. Create a group access review (static parent group)

Portal: **Entra admin center > ID Governance > Access reviews > + New access review**
([Create an access review of groups and applications](https://learn.microsoft.com/en-us/entra/id-governance/create-access-review)).

Configure:

| Setting | Value |
|---|---|
| What to review | **Teams + Groups** > select "Cyber Security Contractors" (static) |
| Scope | All users |
| Reviewers | Selected reviewer(s) — e.g. Marcus Reyes — or **Group owners** |
| Duration | e.g. 7 days |
| Recurrence | Quarterly |
| Auto apply results to resource | **Enabled** |
| If reviewers don't respond | **Take recommendations** (or Remove access, per policy) |
| Action to apply on denied users | **Remove user's membership from the resource** |

Reviewers can also be the members themselves (self-review). Recurrence supports one-time,
weekly, monthly, quarterly, or semi-annually.

### 2. Create an application access review

Repeat for the Phase 5 lab application: **What to review > Applications** > the assigned app,
scope to assigned users, reviewer = a designated reviewer, with auto-apply enabled. Reviewing
app **assignments** (rather than group membership) lets denied users have their app role
assignments removed directly
([Preparing for an access review of users' access to an application](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-application-preparation)).

### 3. Reviewers evaluate in My Access

Reviewers open **My Access** (`myaccess.microsoft.com/access-reviews`), select the pending
review, and decide per user:

| Decision | Effect |
|---|---|
| **Approve** | Retains the membership/assignment |
| **Deny** | Flags the entitlement for removal when results are applied |
| **Accept recommendations** | Applies the system's helper recommendation (e.g. deny for users with no recent sign-in) |

Reviewers can also leave a reason with each decision, and the review's progress page shows
pending decisions until the review ends.

Decision helpers analyze telemetry (e.g. no sign-in within 30 days) and present
Approve/Deny recommendations in the review interface
([What are access reviews?](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-overview)).

### 4. Complete the review and apply results

When the review ends (or the reviewer stops it early), apply the results:

- With **auto-apply** enabled, denied users are removed automatically at completion.
- Otherwise, an administrator opens the completed review and selects **Apply**.

> **Accuracy note:** "Deny" is a *decision* — removal happens when the review completes and
> results are applied (automatically or manually), and removal is expected to take effect
> within a few minutes. Verify the exact nonresponse behavior you configured rather than
> assuming a universal default.

### 5. Verify removal

- The denied contractor no longer appears in the static group's member list.
- The denied user's app role assignment is gone (for the app-assignment review).
- The removal events appear in the tenant audit logs.

## Validation

- [ ] A group access review exists on the static contractor group with quarterly recurrence.
- [ ] An application access review exists on the lab app.
- [ ] Reviewers can see and decide both reviews in My Access.
- [ ] A denied user is removed after completion (auto-apply verified in audit logs).
- [ ] The dynamic groups' rules were verified (membership cannot be changed by review decisions).

## Evidence to Capture

- The access review configuration page (scope, reviewers, recurrence, auto-apply).
- The My Access reviewer interface with decision helpers visible.
- The completed review's results page and the removal events in audit logs.

## References

- [What are access reviews?](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-overview)
- [Create an access review of groups and applications](https://learn.microsoft.com/en-us/entra/id-governance/create-access-review)
- [Manage user and guest user access with access reviews](https://learn.microsoft.com/en-us/entra/id-governance/manage-access-review)
- [Complete an access review of groups & applications](https://learn.microsoft.com/en-us/entra/id-governance/complete-access-review)
- [Preparing for an access review of users' access to an application](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-application-preparation)
- [Self-review of access packages and resources](https://learn.microsoft.com/en-us/entra/id-governance/self-access-review)

Next: [Phase 7 — Offboarding & Cleanup](07-offboarding-and-cleanup.md)
