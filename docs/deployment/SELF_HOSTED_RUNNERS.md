# Self-Hosted GitHub Runners

Date: 2026-06-28

This runbook is for recovering BrassTune CI when GitHub-hosted Actions are blocked by billing, spending-limit, quota, or hosted-runner capacity state.

GitHub documents that GitHub Actions usage is free for self-hosted runners, while private repositories use plan-specific hosted-runner minutes and storage quotas. GitHub also warns that self-hosted runners are not guaranteed clean ephemeral virtual machines and can be persistently compromised by untrusted workflow code. Treat self-hosted runner setup as a controlled operational workaround, not a weaker release gate.

References:

- https://docs.github.com/en/actions/concepts/billing-and-usage
- https://docs.github.com/en/actions/hosting-your-own-runners
- https://docs.github.com/en/actions/reference/security/secure-use

## Required Runner Labels

Linux web/backend runner:

```json
["self-hosted","brasstune","linux"]
```

macOS native runner:

```json
["self-hosted","brasstune","macos","xcode"]
```

## Repository Variables

Set only the variables for runners that are registered and online. Values must be valid JSON for `runs-on`.

```text
BRASSTUNE_BACKEND_RUNNER=["self-hosted","brasstune","linux"]
BRASSTUNE_FRONTEND_RUNNER=["self-hosted","brasstune","linux"]
BRASSTUNE_SECURITY_RUNNER=["self-hosted","brasstune","linux"]
BRASSTUNE_POSTGRES_RUNNER=["self-hosted","brasstune","linux"]
BRASSTUNE_PRODUCTION_SMOKE_RUNNER=["self-hosted","brasstune","linux"]
BRASSTUNE_RENDER_KEEPALIVE_RUNNER=["self-hosted","brasstune","linux"]
BRASSTUNE_DEPLOY_RUNNER=["self-hosted","brasstune","linux"]
BRASSTUNE_ACCOUNT_DELETION_RETRY_RUNNER=["self-hosted","brasstune","linux"]
BRASSTUNE_DEVICE_SIMULATION_RUNNER=["self-hosted","brasstune","linux"]
BRASSTUNE_SWIFT_RUNNER=["self-hosted","brasstune","macos","xcode"]
```

Every workflow must keep a hosted default so contributors without these variables still run on `ubuntu-latest` or `macos-latest`.

## Security Rules

- Prefer repository-scoped runner access for `aryasalem09/BrassTune` only.
- Do not run untrusted fork pull requests on self-hosted runners.
- Do not place production deploy secrets in normal PR check jobs.
- Use protected GitHub Environments for deploy and production smoke jobs.
- Keep the runner workspace clean between jobs.
- Remove emergency runner registrations after recovery unless the owner intentionally keeps them.
- Never store runner registration tokens in Git, docs, workflow output, screenshots, or shell history.

## Tooling Checklist

Linux runner:

- `git`
- Node 24 and npm
- Python 3.11 or 3.12
- `pip`
- Docker or an equivalent PostgreSQL 16 service path
- Playwright Chromium dependencies
- `gitleaks` action compatibility
- `bandit`
- `pip-audit`

macOS runner:

- Xcode 26-compatible SDK for the guarded Liquid Glass API path
- Swift 6
- Available iPhone simulator
- Node 24 if browser/device workflows are intentionally routed there

## Recovery Sequence

1. Confirm the precise Actions blocker from check-run annotations.
2. Register only the minimum runner required to start the blocked BrassTune jobs.
3. Set the matching repository variable with valid JSON labels.
4. Rerun PR checks and confirm jobs have nonzero steps and an assigned runner.
5. Do not remove required checks or bypass branch rules to make the PR green.
6. Remove or disable temporary runners after hosted capacity or billing is repaired unless the owner elects to keep them.

## Fallback CI Mirrors

CircleCI and GitLab can provide additional external evidence, but they should not replace GitHub required checks unless branch protection, secrets, exact-SHA artifacts, and deployment identity are deliberately migrated.

As of 2026-06-28, CircleCI advertises a Free plan with build-minute/credit limits, and GitLab has historically documented a much smaller Free compute-minute allowance. Re-check official pricing pages before relying on either for release gates:

- https://circleci.com/pricing/
- https://about.gitlab.com/pricing/
