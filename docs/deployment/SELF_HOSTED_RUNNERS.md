# Self-Hosted GitHub Runners

Date: 2026-07-24

This runbook is for recovering BrassTune CI when GitHub-hosted Actions are blocked by billing, spending-limit, quota, or hosted-runner capacity state.

GitHub documents that GitHub Actions usage is free for self-hosted runners, while private repositories use plan-specific hosted-runner minutes and storage quotas. GitHub also warns that self-hosted runners are not guaranteed clean ephemeral virtual machines and can be persistently compromised by untrusted workflow code. Treat self-hosted runner setup as a controlled operational workaround, not a weaker release gate.

References:

- https://docs.github.com/en/actions/concepts/billing-and-usage
- https://docs.github.com/en/actions/hosting-your-own-runners
- https://docs.github.com/en/actions/reference/security/secure-use

## Required Runner Labels

Linux web/backend runner:

```json
["self-hosted","brasstune","linux","ci"]
```

macOS native runner:

```json
["self-hosted","brasstune","macos","xcode"]
```

## Repository Variables

Set only the variables for runners that are registered and online. Values must be valid JSON for `runs-on`.

```text
BRASSTUNE_BACKEND_RUNNER=["self-hosted","brasstune","linux","ci"]
BRASSTUNE_FRONTEND_RUNNER=["self-hosted","brasstune","linux","ci"]
BRASSTUNE_SECURITY_RUNNER=["self-hosted","brasstune","linux","ci"]
BRASSTUNE_POSTGRES_RUNNER=["self-hosted","brasstune","linux","ci"]
BRASSTUNE_DEVICE_SIMULATION_RUNNER=["self-hosted","brasstune","linux","ci"]
BRASSTUNE_SWIFT_RUNNER=["self-hosted","brasstune","macos","xcode"]
```

General build and test workflows keep hosted defaults so contributors without
runner variables can use `ubuntu-latest` or `macos-latest`. Production deployment
and smoke selectors remain unassigned to persistent self-hosted runners and are
executed through reviewed provider tooling. Account-deletion retry maintenance is
scheduled inside Supabase with pg_cron and pg_net, not on any GitHub runner.

## Security Rules

- Prefer repository-scoped runner access for `Klevin-G/BrassTune` only.
- Do not run any pull-request event on these persistent self-hosted runners.
- Keep Backend, Frontend, Security, and Swift self-hosted checks limited to trusted
  pushes to `main`. Validate pull requests locally, merge only an exact reviewed
  SHA, then require the matching post-merge checks before deploy.
- Never invoke checkout-controlled provisioning through `sudo`, `apt-get`, Docker
  socket access, or another host-elevation path. Pre-provision runner images; pinned
  setup actions select the job's Node and Python toolchains.
- Do not place production deploy secrets in normal PR check jobs.
- Do not route account-deletion maintenance credentials to GitHub runners. The
  Supabase-only schedule is documented in `ACCOUNT_DELETION_MAINTENANCE.md`.
- Use protected GitHub Environments for deploy and production smoke jobs.
- Keep the runner workspace clean between jobs.
- Remove emergency runner registrations after recovery unless the owner intentionally keeps them.
- Never store runner registration tokens in Git, docs, workflow output, screenshots, or shell history.

## Tooling Checklist

Linux runner:

- `git`
- `libsqlite3.so.0` for the action-selected Python runtime
- PostgreSQL server/client binaries for an unprivileged per-job cluster
- Playwright Chromium dependencies
- Pinned setup actions can install Node and Python without host package mutation

macOS runner:

- Xcode 26-compatible SDK for the guarded Liquid Glass API path
- Swift 6
- Available iPhone simulator
- Node 24 if browser/device workflows are intentionally routed there

## Reproducible Linux Runner Image

The reviewed Linux image definition is in `scripts/ci/linux-runner/`. Build a
new immutable tag, verify it before replacement, and retain the registration
volume so the one-time token is never placed in a command or log:

```bash
docker build \
  --tag brasstune-actions-runner-linux-arm64:2.336.0-r4 \
  scripts/ci/linux-runner

docker run --rm --entrypoint bash \
  brasstune-actions-runner-linux-arm64:2.336.0-r4 \
  -lc 'test ! -x /usr/bin/sudo && test ! -x /usr/bin/docker && python3.12 -c "import sqlite3; print(sqlite3.sqlite_version)" && pg_config --version'
```

The runtime container uses a repository-scoped registration, runs as the
unprivileged `runner` user, and does not mount the Docker socket. PostgreSQL is
started as a temporary, unprivileged process inside each matching main-branch
job. Production credentials never run on this persistent CI pool.

## Retired Account-Deletion Maintenance Runner

The dedicated curl-only runner and `.github/workflows/account-deletion-retry.yml`
were retired on 2026-07-24. The retry endpoint is now triggered by a private,
zero-argument Supabase function scheduled with pg_cron. It consumes no GitHub
Actions minutes and never routes its HMAC credentials through a runner.

After the first scheduled request returned `204`, the retired repository runner
registration, isolated container, volume, and maintenance image tags were removed.
The general Linux and macOS CI runners were intentionally preserved.
The historical image under `scripts/ci/maintenance-runner/` is not an active
production path and must not be started for account-deletion maintenance.

## Recovery Sequence

1. Confirm the precise Actions blocker from check-run annotations.
2. Register only the minimum runner required to start the blocked BrassTune jobs.
3. Confirm each CI workflow selector matches its registered runner labels.
   Account-deletion retry maintenance is intentionally absent from GitHub Actions.
4. Complete the documented local release matrix on the exact candidate SHA.
5. Merge that reviewed SHA, then confirm the post-merge Backend, Frontend, Security,
   and Swift jobs have nonzero steps, use the intended runner, and pass on the exact
   merged SHA before deployment.
6. Do not expose these runners to pull-request events merely to recreate a PR check.
7. Remove or disable temporary runners after hosted capacity or billing is repaired unless the owner elects to keep them.

## Fallback CI Mirrors

CircleCI and GitLab can provide additional external evidence, but they should not replace GitHub required checks unless branch protection, secrets, exact-SHA artifacts, and deployment identity are deliberately migrated.

As of 2026-06-28, CircleCI advertises a Free plan with build-minute/credit limits, and GitLab has historically documented a much smaller Free compute-minute allowance. Re-check official pricing pages before relying on either for release gates:

- https://circleci.com/pricing/
- https://about.gitlab.com/pricing/
