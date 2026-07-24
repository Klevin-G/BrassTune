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

Production account-deletion maintenance runner:

```json
["brasstune-production-maintenance"]
```

The maintenance runner is registered with `--no-default-labels`. Its single
composite label does not overlap with the Linux CI or macOS Xcode pools.

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
runner variables can use `ubuntu-latest` or `macos-latest`. The production
account-deletion retry workflow is different: its runner label is hard-coded to
the dedicated maintenance runner so a repository-variable change cannot route
the secret elsewhere, exhausted hosted minutes cannot silently skip the job,
and the secret cannot reach the general CI pool. Production deployment and smoke
selectors remain unassigned to persistent self-hosted runners and are executed
through reviewed provider tooling.

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
- Route the account-deletion maintenance secret only to the dedicated
  `brasstune-production-maintenance` label. Keep the workflow checkout-free and
  scope the secret to its curl step.
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

## Dedicated Production Maintenance Runner

The reviewed curl-only image is in `scripts/ci/maintenance-runner/`. It pins the
Actions Runner archive and checksum, runs as UID 1001, disables runner
self-updates, and omits `git`, system `node`, Python, PostgreSQL, Docker, and
`sudo`. The Actions Runner distribution contains its own internal runtime, but
no `node` executable is exposed on `PATH` to workflow steps.

Build and verify the image before registration:

```bash
docker build \
  --tag brasstune-actions-runner-maintenance-arm64:2.336.0-r1 \
  scripts/ci/maintenance-runner

docker run --rm --entrypoint bash \
  brasstune-actions-runner-maintenance-arm64:2.336.0-r1 \
  -lc 'test "$(id -u)" = 1001 && command -v curl >/dev/null && for binary in docker git node npm psql python python3 sudo; do ! command -v "${binary}"; done && /opt/actions-runner-template/bin/Runner.Listener --version'
```

Register it without placing the one-time token in a host argument, environment
variable, file, log, or shell history. A short-lived registration container
reads the token from standard input, writes only the runner registration to the
dedicated volume, and exits. `config.sh` necessarily receives the token inside
that isolated container process:

```bash
gh api --method POST \
  repos/Klevin-G/BrassTune/actions/runners/registration-token \
  --jq .token |
docker run --rm --interactive \
  --name brasstune-actions-runner-production-maintenance-register \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --pids-limit 128 \
  --memory 256m \
  --cpus 0.5 \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=32m \
  --mount source=brasstune-actions-runner-production-maintenance,target=/opt/actions-runner \
  --env RUNNER_NAME=brasstune-linux-arm64-production-maintenance \
  --entrypoint bash \
  brasstune-actions-runner-maintenance-arm64:2.336.0-r1 \
  -lc 'set -euo pipefail; cd /opt/actions-runner; test ! -f .runner; if [ ! -x ./config.sh ]; then cp -a /opt/actions-runner-template/. .; fi; IFS= read -r registration_token; test -n "${registration_token}"; ./config.sh --unattended --disableupdate --no-default-labels --url https://github.com/Klevin-G/BrassTune --token "${registration_token}" --name "${RUNNER_NAME}" --labels brasstune-production-maintenance --work _work; unset registration_token'

docker run --detach \
  --name brasstune-actions-runner-production-maintenance \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --pids-limit 128 \
  --memory 256m \
  --cpus 0.5 \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=32m \
  --mount source=brasstune-actions-runner-production-maintenance,target=/opt/actions-runner \
  --label com.brasstune.purpose=github-actions-production-maintenance-runner \
  --env RUNNER_NAME=brasstune-linux-arm64-production-maintenance \
  brasstune-actions-runner-maintenance-arm64:2.336.0-r1
```

Do not mount host paths or `/var/run/docker.sock`. After registration, confirm
that the runner is repository-scoped, online, and has only the
`brasstune-production-maintenance` label:

```bash
gh api repos/Klevin-G/BrassTune/actions/runners \
  --jq '.runners[] | select(.name == "brasstune-linux-arm64-production-maintenance") | {name,status,labels:[.labels[].name]}'
```

Verify with one `workflow_dispatch` on `main`, then inspect the job through the
Actions API. It must show the dedicated runner name, at least one executed step,
and a successful conclusion. Confirm the following scheduled run also succeeds.
Never print the maintenance secret or the registration token while gathering
evidence.

Rollback is fail-closed: stop the container first so no new job can start,
remove its repository runner registration, preserve any required diagnostics,
and delete its named volume. Revert the hard-coded workflow selector only after
hosted billing is restored. Rotate the maintenance endpoint secret if compromise
or unintended exposure is suspected.

## Recovery Sequence

1. Confirm the precise Actions blocker from check-run annotations.
2. Register only the minimum runner required to start the blocked BrassTune jobs.
3. Confirm each workflow selector matches its registered runner labels. General
   CI pools use repository variables; the production maintenance label is
   hard-coded.
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
