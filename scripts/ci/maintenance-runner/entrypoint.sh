#!/usr/bin/env bash
set -euo pipefail

readonly runner_home=/opt/actions-runner
readonly runner_template=/opt/actions-runner-template
readonly runner_repository_url=https://github.com/Klevin-G/BrassTune
readonly runner_label=brasstune-production-maintenance

if [[ ! -x "${runner_home}/bin/Runner.Listener" ]]; then
  cp -a "${runner_template}/." "${runner_home}/"
fi

cd "${runner_home}"

if [[ ! -f .runner ]]; then
  if ! IFS= read -r registration_token; then
    registration_token=
  fi
  if [[ -z "${registration_token}" ]]; then
    printf '%s\n' "A one-time GitHub runner registration token is required on standard input." >&2
    exit 64
  fi

  ./config.sh \
    --unattended \
    --disableupdate \
    --no-default-labels \
    --url "${runner_repository_url}" \
    --token "${registration_token}" \
    --name "${RUNNER_NAME:?RUNNER_NAME is required}" \
    --labels "${runner_label}" \
    --work _work

  unset registration_token
fi

exec ./run.sh
