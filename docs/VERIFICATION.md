# Verification record

## Executed locally

- `npm ci` / dependency lockfile generated.
- `npm run build`: production Vite bundle compiled successfully.
- `npm audit --omit=dev --audit-level=high`: 0 reported production dependency vulnerabilities at verification time. This is not a security certification.
- `npm test`: 18 passing tests, 0 failures (including the database parent test).
- Database tests run the actual migration in embedded PostgreSQL (PGlite), with mock Supabase auth functions and the anon/authenticated/service_role roles.
- Tested: MFA enforcement, disabled account denial, anonymous denial, registration timestamp, integer amounts and invalid amount rejection, duplicate number, department isolation for list/history/mutations, blocked direct storage access, read-only consul, intake write restrictions, receipt/wait/resume/return, optimistic concurrency, rollback of a failed batch, audit preservation, administrator correction, minimal public projection, service-only lookup grant and persistent rate limit.
- API tests mock external Cloudflare/Supabase transport: normalization, integer cents, no-cache headers, response field allowlist, wrong HTTP method/origin, missing server configuration, challenge failure, rate limit failure and database failure.

## Not executed against live services

No customer Supabase project, Vercel deployment, domain, staff credentials or production dataset was supplied. Live TOTP onboarding, real Turnstile, Vercel routing, hosted Supabase permissions and end-to-end browser behavior therefore require acceptance testing after setup. No claim of browser/device visual QA, penetration testing, load testing, backup restoration or official security certification is made.

Run the manual acceptance steps in SETUP_AR.md with synthetic data before entering real mail. Keep staging and production credentials separate. Before upgrading dependencies, run the tests and build and repeat the affected acceptance flows.

## Separate-site update (2026-10-30)

Added production-build tests for both app modes. Verified citizen assets exclude signInWithPassword, challengeAndVerify, register_mail and a browser Supabase key sentinel; employee assets exclude the public API path and Turnstile widget. Verified legacy /staff redirect configuration, invalid-mode build failure, and staff API refusal without contacting services. Original database/API tests remain passing. Live deployments still require the acceptance checks in SEPARATE_SITES_AR.md.
