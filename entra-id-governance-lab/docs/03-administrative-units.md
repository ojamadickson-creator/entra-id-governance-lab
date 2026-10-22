# Phase 3 — Delegated Administration: Administrative Units vs. Global Roles

> Phase series: [0](00-prerequisites-and-verification.md) · [1](01-automated-onboarding.md) · [2](02-dynamic-membership.md) · [3](03-administrative-units.md) · [4](04-pim-and-role-governance.md) · [5](05-enterprise-application-access.md) · [6](06-access-reviews.md) · [7](07-offboarding-and-cleanup.md)

## Objective & Scope

Apply the Principle of Least Privilege to delegated administration: create the "Contractors AU"
administrative unit, scope a Helpdesk Administrator role to it, and map the enterprise
role-to-job-title matrix with correct scoping — tenant-wide where the role does not support
administrative unit scope.

**Scope:** administrative unit creation and population, AU-scoped role assignment (portal and
PowerShell), the role mapping matrix, and positive/negative validation tests.

## Prerequisites

- [Phase 1](01-automated-onboarding.md) completed.
- Operator role: **Privileged Role Administrator** for role assignment.
- Delegated Graph scopes: `AdministrativeUnit.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`,
  `User.Read.All`, `Group.Read.All` (the script reads the parent group and its members).
- **Licensing:** creating AUs requires only Entra ID Free; assigning roles at AU scope requires
  a **P1/P2 license for each administrative unit administrator**
  ([Assign Microsoft Entra roles — AU scope](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-assign-powershell)).

## Key Concepts

### What an administrative unit is — and is not

An AU is a **delegation boundary**: a role assigned at AU scope applies only when managing
members of that unit, and never to tenant-wide settings. It is not an authorization boundary
against tenant-level administrators — a Global Administrator still supersedes it. Adding a
*group* to an AU does not make every group member an AU-managed user; membership is per-object.

### Which roles support AU scope (correction to the source breakdown)

Only a defined list of built-in roles can be assigned with administrative unit scope —
including **Helpdesk Administrator, User Administrator, Groups Administrator, License
Administrator, Password Administrator, Authentication Administrator**, plus any custom role
whose permissions target users, groups, or devices
([Assign Microsoft Entra roles — roles that can be assigned with AU scope](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-assign-powershell)).

**Security Reader, Security Administrator, and Cloud App Security Administrator are NOT on that
list** — they must be assigned at tenant scope. The role matrix below reflects that reality.

### AU restriction on admin targets

AU-scoped Helpdesk Administrators can reset passwords only for users in the AU **who do not
have administrator roles** — password resets and similar sensitive actions against
administrators are restricted
([Assign Microsoft Entra roles — AU scope](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-assign-powershell)).

## Role Mapping & Governance Matrix (corrected scoping)

| Job role / specialty | Assigned Entra ID role | Scope | Least-privilege rationale |
|---|---|---|---|
| Helpdesk Support Engineer | Helpdesk Administrator | **Contractors AU** | Non-admin user management and password resets inside the AU only |
| SOC Analyst / Security Reader | Security Reader | Tenant | Read-only access to security telemetry, sign-in and audit logs; no write rights |
| Penetration Tester | Security Reader | Tenant | Elevated roles on assessment accounts create unearned pathways and invalidate tests |
| Security Operations Lead | Security Administrator | Tenant (make it PIM-eligible in Phase 4) | Full authority to configure security policies and respond to alerts |
| Cloud Security Engineer | Cloud App Security Administrator | Tenant (PIM-eligible in Phase 4) | Scoped to cloud app discovery, app security policies, and shadow-IT governance |

## Step-by-Step Execution

### 1. Create the administrative unit

Portal: **Entra admin center > Entra ID > Roles & admins > Admin units > Add administrative
unit** — name it `Contractors AU`.

```powershell
$au = New-MgDirectoryAdministrativeUnit -DisplayName 'Contractors AU' `
    -Description 'Administrative boundary for the cyber security contractor cohort'
```

### 2. Populate the AU with the contractor users

Add the 20 users as AU members (portal: open the AU > **Users** > **Add**; or):

```powershell
foreach ($member in (Get-MgGroupMember -GroupId $group.Id -All)) {
    $odataId = "https://graph.microsoft.com/v1.0/users/$($member.Id)"
    New-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $au.Id -OdataId $odataId
}
```

The documented `-OdataId` reference form is shown in
[Add users, groups, or devices to an administrative unit](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/admin-units-members-add).

The full sequence is automated in `scripts/03-New-AdminUnitScopedRole.ps1` (it now takes
FULL UPNs for the helpdesk staff, and the run fails if a name is missing or ambiguous).

### 2b. Create the out-of-scope test user

For the negative test, provision one small test account that is deliberately **not** an AU
member (portal: **Users > New user > Create user**, e.g. `outsider.test@<domain>`, or via
`New-MgUser`). It holds no roles and no app assignments — it exists purely to prove the
AU boundary blocks out-of-scope administration.

### 3. Assign Helpdesk Administrator scoped to the AU

Portal: **Roles & admins > Admin units > Contractors AU > Roles and administrators > Helpdesk
Administrator > Add assignments** — then add Rita Marques, Bruno Alves, and Nadia Faro.
Assignments made from inside the AU automatically carry the AU scope.

PowerShell equivalent:

```powershell
$role = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq 'Helpdesk Administrator'" -Top 1
$directoryScope = '/administrativeUnits/' + $au.Id

New-MgRoleManagementDirectoryRoleAssignment `
    -RoleDefinitionId $role.Id `
    -PrincipalId $user.Id `
    -DirectoryScopeId $directoryScope
```

### 4. Assign the tenant-scoped baseline roles

Assign Security Reader to the SOC analysts and penetration testers at tenant scope
(**Roles & admins > Security Reader > Add assignments**) — remember this role cannot be
AU-scoped. Security Operations Leads and Cloud Security Engineers receive their roles as
**PIM-eligible assignments in Phase 4** rather than standing active assignments.

### 5. Validate with positive and negative tests

- **Positive:** sign in as Rita Marques (helpdesk) — she can reset the password of a
  non-admin contractor inside Contractors AU.
- **Negative:** the same admin cannot reset passwords of users outside the AU (create a
  small test user that is *not* an AU member for this), cannot manage
  administrator accounts, and has no authority to modify tenant-wide settings (what
  they can *see* is not the boundary — what they can *change* is).

## Validation

- [ ] Contractors AU exists and contains the 20 cohort users.
- [ ] Helpdesk Administrator assignments appear under the AU with "This resource" scope
  (verify under **Roles & admins > Admin units > Contractors AU > Roles and administrators**).
- [ ] Positive test passes; negative tests are blocked with access-denied.
- [ ] Security Reader assigned to SOC/pen-test accounts at tenant scope.
- [ ] No contractor holds Global Administrator or other unscoped privileged roles.

## Evidence to Capture

- Admin unit Overview page showing membership count.
- The AU-scoped Helpdesk Administrator assignment (scope column visible).
- An access-denied result from the negative test (sanitized).

## References

- [Assign Microsoft Entra roles with administrative unit scope](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-assign-powershell)
- [Assign Microsoft Entra roles (portal)](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/manage-roles-portal)
- [Administrative units in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/administrative-units)
- [Restricted management administrative units](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/admin-units-restricted-management)

Next: [Phase 4 — PIM & Role Governance](04-pim-and-role-governance.md)
