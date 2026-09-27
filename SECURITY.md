# Security Policy

AfriCinemas handles customer data and M-Pesa payments, so security reports are taken seriously.

## Reporting a vulnerability

**Please don't open a public issue.** Report privately through GitHub's
[private vulnerability reporting](https://github.com/dennisovich254/africinemas/security/advisories/new)
(Security → Advisories → "Report a vulnerability").

Please include what you found, steps to reproduce, and the impact you believe it has. Don't
include real customer data or real payment credentials; use the Daraja **sandbox**.

We aim to acknowledge reports within 3 working days and to agree a fix and disclosure timeline with you.

## Scope

In scope: this repository's code, CI configuration and deployment configuration, especially
tenant isolation (one cinema reaching another's data), authentication, payments and tickets.
Out of scope: third-party services themselves (Safaricom Daraja, Google Gemini, GitHub).

## Supported versions

Only the latest `main` is supported during the hackathon.

## Our safeguards

- Secrets live in `.env` (git-ignored) and GitHub Actions secrets, never in the repo.
- Every commit is scanned by gitleaks locally, and CI scans the full history; GitHub secret
  scanning with push protection is enabled.
- GitHub Actions are pinned to commit SHAs, and toolchain binaries are checksum-verified.
- Design-level security requirements: `docs/architecture.md` (for example §4 tenant isolation and §138 production config).
