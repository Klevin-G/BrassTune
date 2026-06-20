# Render Keepalive

Status: best-effort closed-beta helper.

The keepalive workflow is a closed-beta reliability helper, not an uptime guarantee. For production or public beta, move the Render backend to a paid always-on instance.

## GitHub Actions Workflow

Workflow: `.github/workflows/render-keepalive.yml`

- Schedule: `*/10 * * * *`
- Manual trigger: `workflow_dispatch`
- Endpoint: `https://brasstune.onrender.com/api/health`
- Secrets: none required by default
- Data mutation: none
- Overlap protection: workflow concurrency group `render-keepalive`

The workflow prints only safe status information and fails if the health endpoint does not return successfully.

## Manual Verification

```bash
curl --fail --silent --show-error --max-time 20 https://brasstune.onrender.com/api/health
```

## Disable

Disable the workflow in GitHub Actions or remove the schedule block after moving Render to a paid always-on instance.

## Render Cron Alternative

Do not create a Render Cron Job without owner approval because Render Cron Jobs can have billing implications.

If approved, use:

```text
*/10 * * * *
```

with:

```bash
curl --fail --silent --show-error --max-time 20 https://brasstune.onrender.com/api/health
```

Render Free can still restart, spin down, or hit usage limits. Paid Render is the clean always-on solution.
