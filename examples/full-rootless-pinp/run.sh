#!/bin/sh
set -eu

container_name="github-runner-${GITHUB_JOB_ID}-${GITHUB_JOB_SHORT_HASH}"
podman exec -w /app/runner ${container_name} /app/runner/run.sh

echo "Runner execution complete"
