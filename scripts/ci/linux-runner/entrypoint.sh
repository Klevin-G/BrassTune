#!/usr/bin/env bash
set -euo pipefail

readonly runner_home=/opt/actions-runner
readonly runner_template=/opt/actions-runner-template

if [[ ! -x "${runner_home}/bin/Runner.Listener" ]]; then
  cp -a "${runner_template}/." "${runner_home}/"
fi

cd "${runner_home}"

if [[ ! -f .runner ]]; then
  IFS= read -r registration_token
  if [[ -z "${registration_token}" ]]; then
    printf '%s\n' "A one-time GitHub runner registration token is required on standard input." >&2
    exit 64
  fi

  ./config.sh \
    --unattended \
    --replace \
    --url "${RUNNER_REPOSITORY_URL:?RUNNER_REPOSITORY_URL is required}" \
    --token "${registration_token}" \
    --name "${RUNNER_NAME:?RUNNER_NAME is required}" \
    --labels "${RUNNER_LABELS:?RUNNER_LABELS is required}" \
    --work _work

  unset registration_token
fi

exec ./run.sh
