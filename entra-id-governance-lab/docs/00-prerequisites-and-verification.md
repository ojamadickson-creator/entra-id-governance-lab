# Phase 0 — Prerequisites & Verification

> Phase series: [0](00-prerequisites-and-verification.md) · [1](01-automated-onboarding.md) · [2](02-dynamic-membership.md) · [3](03-administrative-units.md) · [4](04-pim-and-role-governance.md) · [5](05-enterprise-application-access.md) · [6](06-access-reviews.md) · [7](07-offboarding-and-cleanup.md)

## Objective & Scope

Prepare a dedicated lab tenant with the correct licensing, administrative roles, and tooling —
and understand the three separate authorization layers that gate every later phase: **Graph
permission consent**, the **operator's Microsoft Entra role**, and **feature licensing**.

**Scope:** tenant setup, licensing, PowerShell module installation, Graph authentication, and the
verification method used throughout this guide.

## Step-by-Step Execution

### 1. Create a dedicated lab tenant

Create a new Microsoft Entra tenant (or use an existing developer/test tenant) with a verified
domain. This lab is deliberately **cloud-only**: no directory synchronization, no on-premises
dependency. Placeholder values used throughout this guide:

| Placeholder | Meaning |
|---|---|
| `$TenantId` | Your tenant's ID (Entra admin center > Overview) |
| `beginningdimension.com` | Your verified primary domain |
| `*.onmicrosoft.com` | The tenant's initial domain |

> **Safety:** never run this lab against a production tenant. The offboarding and cleanup phases
> modify users, roles, and app assignments destructively.

### 2. Confirm licensing

The lab's features require premium licensing. Obtain a **Microsoft Entra ID P2 or Microsoft
Entra ID Governance trial** for the tenant, and confirm the feature-to-license mapping:

| Feature used in this lab | License |
|---|---|
| Dynamic membership groups | P1 per unique user in dynamic groups ([Microsoft Entra licensing](https://learn.microsoft.com/en-us/entra/fundamentals/licensing)) |
| Administrative unit-scoped role assignment | P1 for each AU administrator; creating AUs is Free ([Assign Microsoft Entra roles — AU scope](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-assign-powershell)) |
| PIM (eligible assignments, activation, approvals) | P2 or Governance ([PIM license requirements](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/subscription-requirements)) |
| Access reviews | Governance (some capabilities on P2) ([What are access reviews?](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-overview)) |
| Group-based app assignment | P1 ([Manage access to apps](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/what-is-access-management)) |

License-counting rules for governance features are strict (reviewers and reviewed users both
count): see [Entra ID Governance licensing fundamentals](https://learn.microsoft.com/en-us/entra/id-governance/licensing-fundamentals).

### 3. Confirm operator roles

Sign in with a lab Global Administrator (or create dedicated lab admins for realism). The
minimum-privileged operator role per phase:

| Phase | Operator role | Source |
|---|---|---|
| 1 (onboarding) | User Administrator | [Assign user roles](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/manage-roles-portal) |
| 3 (AU + role assignment) | Privileged Role Administrator | [Assign roles with AU scope](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-assign-powershell) |
| 4 (PIM settings, custom role) | Privileged Role Administrator | [PIM role settings](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings) |
| 5 (app assignment) | Cloud Application Administrator | [Assign users and groups to an application](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/assign-user-or-group-access-portal) |
| 6 (access reviews) | Identity Governance Administrator or User Administrator | [Manage user and guest user access with access reviews](https://learn.microsoft.com/en-us/entra/id-governance/manage-access-review) |

### 4. Install Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

Installation and update guidance: [Install the Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation).

### 5. Authenticate with Connect-MgGraph

```powershell
Connect-MgGraph -TenantId $TenantId -Scopes 'User.Read.All' -NoWelcome
```

Key behaviors to understand before running the phase scripts:

- `Connect-MgGraph -Scopes` requests **delegated permissions** that operate as the signed-in
  user. The consent prompt is for Graph permissions — it is separate from your Entra role.
- Request **only the scopes needed for the exercise** (each phase lists its scopes). Missing
  scopes cause `403 Forbidden` mid-execution; over-broad scopes violate least privilege.
- `Directory.ReadWrite.All` is **not** a blanket requirement — this guide avoids presenting it
  as the default. See [Get started with the Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/get-started).
  You may need to disable your security default in Entra to run the above script

### 6. Prepare the CSV source file

Copy `data/contractors.sample.csv` to `data/contractors.csv` and edit it for your tenant. The
file defines 20 identities with six columns:

| Column | Use |
|---|---|
| `FirstName`, `LastName` | Identity name and UPN construction (`first.last@domain`) |
| `JobTitle` | Written to the user object; drives dynamic group rules |
| `Specialty` | Script input for role mapping (Phase 3–4); not a standard Entra user property |
| `Department` | Written to the user object; drives the contractor dynamic group |
| `CompanyName` | Written to the user object |

### 7. Verify readiness

```powershell
Get-MgContext          # shows tenant, account, and consented scopes
```

- [ ] Trial tenant created; verified domain known.
- [ ] P2/Governance trial active.
- [ ] Operator account has the roles in step 3.
- [ ] Microsoft.Graph module installed.
- [ ] `Connect-MgGraph` succeeds and consent prompts were reviewed.
- [ ] `data/contractors.csv` reviewed — 20 rows, all six columns populated.

### 8. Prepare the interactive-test accounts

Several phases require other humans to sign in (the PIM approver, access reviewers, and the
AU-scoped helpdesk admin in the positive/negative tests). Before those phases:

- Create or designate those lab accounts, and reset their passwords as the administrator
  (portal: **Users > [user] > Reset password**, or `Update-MgUser -PasswordProfile @{ ... }`)
  — you control these accounts, so out-of-band delivery is a lab formality, not a gap.
- Have each participant complete first sign-in, the forced password change, and MFA
  registration (needed for the PIM activation step's MFA check).
- Confirm the approver and reviewer accounts hold active licenses and mailboxes where
  required by the exercise.

## Evidence to Capture

- Entra admin center tenant overview (tenant ID and license plan visible).
- `Get-MgContext` output in PowerShell (scopes visible, secrets redacted).

## References

- [Install the Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation)
- [Get started with the Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/get-started)
- [Microsoft Entra licensing](https://learn.microsoft.com/en-us/entra/fundamentals/licensing)
- [Microsoft Entra ID Governance licensing fundamentals](https://learn.microsoft.com/en-us/entra/id-governance/licensing-fundamentals)

Next: [Phase 1 — Automated Onboarding](01-automated-onboarding.md)
