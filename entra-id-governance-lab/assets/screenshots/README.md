# Screenshots — `assets/screenshots/`

This folder holds your evidence captures as you execute the lab. Each phase document lists
suggested captures under "Evidence to Capture" — no screenshot numbers are pre-assigned, so
name files as you go and update the evidence list with your actual results.

## Naming Convention

- File name: `phase-NN-short-description.png` (e.g. `phase-02-im-staff-members.png`).
- Reference from documentation: `assets/screenshots/<file name>`.

## Sanitization Rules

Before committing any capture:

- No passwords, temporary credentials, MFA codes, or tokens — ever.
- No real tenant IDs, real domain names you own in production, or personal data beyond lab
  accounts. Redact where needed.
- Trial-tenant values only; blur credential prompts where a password field is visible.
- Do not capture `Get-LapsADPassword`-style secrets (not applicable here, but the same rule:
  if a command outputs a secret, it is not evidence).

## Status

- [ ] Evidence captures added per phase.
- [ ] Each capture reviewed for sanitization before publishing.
- [ ] Validation checklist completed and reflected in captures.

This lab guide is documentation-verified against Microsoft Learn; your screenshots turn it
into executed, portfolio-ready evidence.
