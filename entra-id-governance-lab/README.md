# Microsoft Entra ID Governance Lab — Identity Lifecycle, PIM, and Access Reviews

<p align="center">
  <strong>Cloud IAM Portfolio Project — Windows-free, cloud-only tenant lab</strong><br>
  Automated onboarding · Dynamic membership · Administrative Units · Privileged Identity Management ·<br>
  Enterprise app access · Access Reviews · Offboarding<br>
  <em>Portfolio Project for IT Administrator Job Applications</em>
</p>

---

## Executive Summary

This project is a hands-on, documentation-verified lab guide for **Microsoft Entra ID** identity
governance. It covers the full identity lifecycle for a cohort of **20 cybersecurity
contractors** — automated onboarding from CSV via PowerShell and Microsoft Graph, attribute-driven
dynamic group membership, least-privilege delegated administration through Administrative
Units, Just-In-Time privileged access with Privileged Identity Management (PIM), enterprise
application access provisioning, continuous compliance with access reviews, and a documented
offboarding sequence.

The lab scenario models a small enterprise identity function: an IAM engineer (Marcus Reyes),
SOC analysts, penetration testers, cloud security engineers, and helpdesk staff — each with a
role mapped by least privilege rather than blanket admin rights. Every procedure in this guide
was checked against official Microsoft Learn documentation before being written down, and each
phase cites the sources that support it.

> **Honesty note:** every step in this repository is **documentation-verified** against
> Microsoft Learn, but the guide is written to be *executed* by you in your own (trial) tenant.
> Nothing here claims to be a record of an already-completed run — capture your own evidence
> using the guidance in each phase and in `assets/screenshots/README.md`.

## Lab Architecture

Cloud-only Microsoft Entra ID tenant (no on-premises sync — deliberately independent from the
companion Active Directory lab):

```text
+--------------------------------------------------------------+
|                    Microsoft Entra ID tenant                  |
|                                                              |
|  data/contractors.csv                                        |
|        |                                                    |
|        v                                                    |
|  [Phase 1] Bulk onboarding (Graph PowerShell)                |
|        |  20 users, temp passwords, forced reset             |
|        v                                                    |
|  [Phase 2] Dynamic groups: "Cyber Security Contractors",      |
|            "IM Staff" (department / jobTitle rules)          |
|        |                                                    |
|        v                                                    |
|  [Phase 3] "Contractors AU" administrative unit              |
|            Helpdesk Administrator scoped to the AU           |
|        |                                                    |
|        v                                                    |
|  [Phase 4] PIM: eligible assignments, JIT activation,        |
|            custom "SOC Analyst" role                         |
|        |                                                    |
|        v                                                    |
|  [Phase 5] Enterprise apps: assignment-required,             |
|            hash-table cached bulk assignment, My Apps       |
|        |                                                    |
|        v                                                    |
|  [Phase 6] Access reviews (groups + apps), My Access        |
|        |                                                    |
|        v                                                    |
|  [Phase 7] Offboarding: disable -> revoke sessions ->       |
|            strip assignments -> (optional) delete           |
+--------------------------------------------------------------+
```

**Scenario roles:** Marcus Reyes (IAM Engineer) is the PIM subject; helpdesk staff receive the
AU-scoped role; SOC analysts receive the custom log-reader role; the remaining contractors stay
non-privileged by design.

## Licensing Prerequisites

| Feature | License required | Verified against |
|---|---|---|
| Dynamic membership groups | Microsoft Entra ID P1 per unique dynamic-group user | [Microsoft Entra licensing](https://learn.microsoft.com/en-us/entra/fundamentals/licensing) |
| Administrative unit-scoped roles | P1 for each AU administrator (creating AUs is Free) | [Assign Microsoft Entra roles — AU scope](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-assign-powershell) |
| PIM | Entra ID P2 or Entra ID Governance | [PIM license requirements](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/subscription-requirements) |
| Access reviews | Entra ID Governance (some capabilities on P2) | [What are access reviews?](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-overview) |
| Group-based app assignment | P1 | [Manage access to apps](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/what-is-access-management) |

A **Microsoft Entra ID P2 or Governance trial** in a throwaway developer tenant is the
recommended lab path. Full detail: [Phase 0 — Prerequisites](docs/00-prerequisites-and-verification.md).

## Key Skills Demonstrated

| Area | Skills |
|---|---|
| Graph automation | `Connect-MgGraph`, delegated scopes and consent, `New-MgUser`, `New-MgGroup`, bulk CSV processing, throttling awareness |
| Identity lifecycle | Onboarding, licensing gates, forced password reset, offboarding and revocation |
| Access organization | Dynamic membership rules (`-eq`, `-startsWith`, `-and`, `-or`), async processing, audit-log verification |
| Least privilege | Administrative units, AU-scoped role assignment, role-to-jobtitle mapping, custom directory roles |
| PIM / JIT | Eligible vs active assignments, role settings (MFA, justification, approval, max duration), activation workflow, approvers |
| App governance | `Enabled for sign-in` / `Assignment required` / `Visible to users`, `New-MgUserAppRoleAssignment`, My Apps |
| Continuous compliance | Access reviews (group + app scopes), decision helpers, My Access portal, auto-apply results |
| Operational safety | Documentation-verified steps, positive/negative validation tests, no secrets in scripts or logs |

## Repository Structure

```text
entra-id-governance-lab/
├── README.md                                  # This file
├── docs/
│   ├── 00-prerequisites-and-verification.md   # Tenant, licensing, tooling, verification ledger
│   ├── 01-automated-onboarding.md             # CSV -> Graph bulk user creation
│   ├── 02-dynamic-membership.md               # Dynamic group rules and verification
│   ├── 03-administrative-units.md             # AU-scoped delegated administration
│   ├── 04-pim-and-role-governance.md         # PIM, JIT activation, custom SOC role
│   ├── 05-enterprise-application-access.md    # App properties, cached bulk assignment, My Apps
│   ├── 06-access-reviews.md                  # Group + app reviews, decisions, auto-apply
│   ├── 07-offboarding-and-cleanup.md         # Documented revocation sequence
│   ├── troubleshooting.md                     # Anticipated problems and diagnostics
│   ├── validation-checklist.md               # End-of-lab checklist
│   └── references.md                          # Full bibliography + verification ledger
├── scripts/
│   ├── 01-Bulk-Create-Contractors.ps1
│   ├── 02-New-DynamicGroups.ps1
│   ├── 03-New-AdminUnitScopedRole.ps1
│   ├── 05-Assign-UsersToApp.ps1
│   └── 07-Offboard-User.ps1
├── tests/
│   └── Test-Scripts.WithMocks.ps1         # No-tenant logic tests (47 assertions)
├── data/
│   └── contractors.sample.csv                 # 20-identity sample cohort
└── assets/
    └── screenshots/                           # Your evidence captures (see README inside)
```

## Phase Guide

| Phase | Document | Focus |
|---|---|---|
| 0 | [Prerequisites & Verification](docs/00-prerequisites-and-verification.md) | Tenant, licenses, PowerShell, Graph scopes |
| 1 | [Automated Onboarding](docs/01-automated-onboarding.md) | CSV-driven bulk user creation |
| 2 | [Dynamic Membership](docs/02-dynamic-membership.md) | Rule syntax, refactoring, verification |
| 3 | [Administrative Units](docs/03-administrative-units.md) | Scoped delegation, positive/negative tests |
| 4 | [PIM & Role Governance](docs/04-pim-and-role-governance.md) | Eligible assignments, JIT, custom role |
| 5 | [Enterprise App Access](docs/05-enterprise-application-access.md) | App properties, cached assignments, My Apps |
| 6 | [Access Reviews](docs/06-access-reviews.md) | Review creation, decisions, auto-apply |
| 7 | [Offboarding & Cleanup](docs/07-offboarding-and-cleanup.md) | Documented revocation sequence |

Supporting documents: [Troubleshooting](docs/troubleshooting.md) ·
[Validation Checklist](docs/validation-checklist.md) ·
[References & Verification Ledger](docs/references.md)

## Corrections Applied to the Source Breakdown

The educational breakdown this guide was built from contained several claims that conflict with
Microsoft's documented behavior. Each is corrected once, in the relevant phase:

1. **Dynamic groups are not access-control containers** — a dynamic group does not prevent
   "orphan" users, and access reviews **cannot remove members from dynamic groups** (decisions
   don't change rule-driven membership). Phase 6 uses a static group for the removal exercise.
2. **Security roles cannot be AU-scoped** — only a specific list of roles (Helpdesk, User, Groups
   Administrators, etc.) supports administrative unit scope. Phase 3 keeps the security-role
   examples tenant-scoped and explains the restriction.
3. **MFA on PIM activation is once per session**, not a guaranteed fresh prompt at every
   activation. Phase 4 documents the Conditional Access authentication-context option for
   strict enforcement.
4. **Offboarding order** — Microsoft's documented emergency sequence disables the account and
   revokes sessions *early* (before/with entitlement removal), and `Revoke-MgUserSignInSession`
   does not instantly terminate every application session. Phase 7 follows the documented order.
5. **`ForceChangePasswordNextSignIn`** is the correct password-profile property name, and
   temporary passwords must never be written to logs or screenshots.
6. **The custom SOC-role permission is `signInReports`**, not `signInLogs` — the custom-role
   permission lists publish `microsoft.directory/signInReports/allProperties/read`.
7. **`Directory.ReadWrite.All` is not minimum privilege** for onboarding — scopes are requested
   per exercise, and the guide separates Graph consent from the operator's Entra role.

## Script Quality Assurance

All five scripts are syntax-checked with the PowerShell AST parser and exercised by a
**no-tenant mock test suite** (`tests/Test-Scripts.WithMocks.ps1`, 47 assertions) that runs
them against in-memory mocks of the Graph cmdlets. The suite checks selected control-flow
paths — it is NOT a substitute for executing the lab in a tenant, and the mocks do not
validate actual SDK parameter schemas or tenant authorization. What it does verify:
dynamic-group rules and processing state; forced password change and 16-character
generation on every created profile; idempotent re-runs; membership repair on re-run;
exact-UPN privileged assignment that **fails the run** on missing or ambiguous names;
app-assignment duplicate/missing/ambiguity handling; declared-role enforcement (the
all-zeros default is rejected whenever the app declares any roles — enabled, disabled, or
application-only); the documented offboarding order (disable first, revoke sessions early,
app removal next); that the offboarding script is honest partial automation — it touches
**no** role assignments and submits **no** PIM requests (role cleanup is a mandatory manual
portal step, and the run prints that notice); group-membership removal that actually mutates
the membership store and survives a repeat run; and `-WhatIf` mutation suppression. Run it with:

```powershell
pwsh -NoProfile -File tests/Test-Scripts.WithMocks.ps1
```

The suite exits 0 only when every assertion passes, so it works as a CI gate: run it on every
commit alongside your own tenant execution evidence.

## Safety & Sanitization Notice

- Run this lab only in a **dedicated trial tenant** — never a production directory.
- No passwords, temporary credentials, tokens, or real tenant IDs belong in scripts, logs, or
  published screenshots. The sample scripts deliberately exclude secrets from their reports.
- Replace all placeholder values (`$TenantId`, domains, UPNs) with your own lab values.

---

Full reference list and the procedure-by-procedure verification ledger:
[References](docs/references.md).
