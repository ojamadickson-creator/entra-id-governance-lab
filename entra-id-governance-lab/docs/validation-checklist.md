# Validation Checklist

End-of-lab checklist for the Entra ID Governance lab. Run through it after completing
Phases 0–7; each item maps to a documented procedure in this repository.

## Prerequisites

- [ ] Dedicated trial tenant (not production) with a verified domain.
- [ ] P2 / Governance trial active; licensing understood per feature.
- [ ] Operator holds the minimum role for each phase.
- [ ] Microsoft.Graph module installed; `Connect-MgGraph` works with per-exercise scopes.

## Phase 1 — Onboarding

- [ ] 20 contractor users created from CSV with standardized attributes.
- [ ] Temporary passwords randomized and never logged; forced change at first sign-in.
- [ ] Parent security group contains the cohort; script summary is green/yellow as expected.

## Phase 2 — Dynamic membership

- [ ] "Cyber Security Contractors (Dynamic)" contains the cohort (async processing waited out).
- [ ] "IM Staff" contains exactly the IAM-titled users (scoped prefix rule).
- [ ] Job title changes add/remove membership; audit logs show engine activity.

## Phase 3 — Administrative units

- [ ] Contractors AU exists with the cohort as members.
- [ ] Helpdesk Administrator assigned at AU scope (scope column = This resource).
- [ ] Positive test: AU helpdesk resets a non-admin contractor password.
- [ ] Negative tests: out-of-AU targets and admin accounts are blocked.
- [ ] Security Reader assigned tenant-scoped to SOC/pen-test accounts.

## Phase 4 — PIM

- [ ] Privileged Role Administrator role settings: 1-hour max, MFA, justification, approval.
- [ ] Marcus Reyes holds a 6-month eligible assignment.
- [ ] Activation walked end-to-end: MFA + justification + approval + timed window + expiry.
- [ ] SOC Analyst Custom Role contains only the two log-read permission strings
      (`auditLogs` and `signInReports`).
- [ ] Tier-1 SOC account can read logs but modify nothing.

## Phase 5 — Enterprise apps

- [ ] Lab app properties: sign-in enabled, assignment required, visible to users.
- [ ] Bulk assignment completed with cached IDs; script summary recorded.
- [ ] Assigned users see the My Apps tile; unassigned users are blocked.

## Phase 6 — Access reviews

- [ ] Group review (static contractor group) and app review created with recurrence + auto-apply.
- [ ] Reviewers decided in My Access; decision helpers observed.
- [ ] Denied user removed after completion; removal visible in audit logs.
- [ ] Dynamic groups' rules verified (decisions cannot change their membership).

## Phase 7 — Offboarding

- [ ] Automated portion executed in the documented order (disable → revoke → strip apps → group membership).
- [ ] Role cleanup performed via the mandatory portal procedure — Active **and** Eligible lists
      verified in the PIM console (the script deliberately does not automate this step).
- [ ] No app assignments remain; no role assignments (standing, active, or eligible) remain.
- [ ] Sign-in sessions revoked (refresh tokens invalidated; minutes of propagation allowed).
- [ ] Audit logs record the full revocation sequence.

## Safety

- [ ] No passwords, tokens, or real tenant IDs in scripts, logs, or captured evidence.
- [ ] (If any account was deleted) deletion came after the verified manual role cleanup.
- [ ] Trial tenant scheduled for deletion or documented for reuse.

---

Related: [Troubleshooting](troubleshooting.md) · [References](references.md)

Back to: [README](../README.md)
