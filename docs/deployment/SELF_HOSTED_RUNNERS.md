# BrassTune Self-Hosted GitHub Actions Runners

## Purpose

Use self-hosted runners when GitHub-hosted Actions minutes are blocked by billing or spending-limit issues. This keeps the Backend, Frontend, Security, and Swift PR checks real without bypassing branch protection or weakening the release gate.

Hosted runners remain the default. Move a job to self-hosted by registering the runner and setting the matching repository variable to a JSON `runs-on` value.

## Required Runner Types

| Workflow | Job name | Default runner | Self-hosted repository variable | Recommended value |
|---|---|---:|---|---|
| Backend | `pytest` | `ubuntu-latest` | `BRASSTUNE_BACKEND_RUNNER` | `["self-hosted","brasstune","linux"]` |
| Frontend | `test-build-audit` | `ubuntu-latest` | `BRASSTUNE_FRONTEND_RUNNER` | `["self-hosted","brasstune","linux"]` |
| Security | `dependency-and-secrets` | `ubuntu-latest` | `BRASSTUNE_SECURITY_RUNNER` | `["self-hosted","brasstune","linux"]` |
| Swift | `package-and-ios` | `macos-latest` | `BRASSTUNE_SWIFT_RUNNER` | `["self-hosted","brasstune","macos","xcode"]` |
| Production Smoke | `smoke` | `ubuntu-latest` | `BRASSTUNE_PRODUCTION_SMOKE_RUNNER` | `["self-hosted","brasstune","linux"]` |
| Render Keepalive | `ping` | `ubuntu-latest` | `BRASSTUNE_RENDER_KEEPALIVE_RUNNER` | `["self-hosted","brasstune","linux"]` |

If only one Mac is available, it can run all non-deploy jobs by using `["self-hosted","brasstune","macos","xcode"]` for each variable. Linux remains preferred for Backend, Frontend, Security, Production Smoke, and Render Keepalive because the dependency setup matches the current workflow assumptions.

## Labels

Create one macOS runner with:

```text
self-hosted
brasstune
macos
xcode
```

Create one Linux runner, when available, with:

```text
self-hosted
brasstune
linux
```

## Register A Runner

In GitHub:

1. Open repository Settings.
2. Open Actions, then Runners.
3. Select New self-hosted runner.
4. Follow GitHub's generated download, configure, and run commands for the target machine.
5. Add the labels above during configuration or from the runner settings page.
6. Set the repository variables listed in the table.
7. Rerun the failed PR checks.

Do not put tokens, deploy hooks, Supabase keys, Apple credentials, signing identities, or private recordings in runner labels, repository variables, or logs.

## Minimum Tooling

All runners:

- git
- curl
- bash
- Node 22
- npm
- Python 3.12 or the workflow-supported Python version
- pip-audit
- Bandit
- Gitleaks or the `gitleaks/gitleaks-action` runtime support

Frontend/security runners:

- Playwright browser dependencies
- Chromium, Firefox, and WebKit for local release journeys

Swift runner:

- Swift
- Xcode 26.x or the current project-supported Xcode
- iOS simulator runtime compatible with the app deployment target
- Ruby, because the Swift workflow uses Ruby to select an available simulator

## Helper Scripts

Use the scripts as preflight checks on runner machines:

```bash
scripts/ci/setup-self-hosted-macos.sh
scripts/ci/setup-self-hosted-linux.sh
```

They do not contain secrets and do not register the GitHub runner. Registration must use GitHub's short-lived runner token from the repository settings page.

## Security Model

Self-hosted runners execute workflow code from this repository. Treat runner machines as CI infrastructure:

- Do not use these runners for untrusted public fork pull requests.
- Keep repository and environment secrets minimal.
- Do not leave Apple signing credentials or provider admin credentials on general-purpose runners.
- Prefer ephemeral or dedicated machines for release-critical work.
- Keep the runner workspace clean between jobs when debugging local failures.
- Review workflow changes before rerunning PR checks that use secrets.

## PR #6 Recovery

After the macOS runner is registered and `BRASSTUNE_SWIFT_RUNNER` is set to `["self-hosted","brasstune","macos","xcode"]`, rerun PR #6's `package-and-ios` check.

After the Linux runner is registered and Backend, Frontend, and Security variables are set, rerun the remaining checks. If only the Mac runner exists, point those variables at the Mac labels temporarily and make sure Node, Python, Playwright, pip-audit, Bandit, and Gitleaks are installed there.

Only merge PR #6 after the required checks pass on self-hosted runners. After merge, rerun hosted production smoke from the repo:

```bash
cd frontend
BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app \
BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com \
BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com \
npm run smoke:hosted
```
