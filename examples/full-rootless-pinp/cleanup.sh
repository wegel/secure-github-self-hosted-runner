#!/bin/sh
set -eu

github_job_id=$(echo $GITHUB_JOB | jq -r '.id')
github_run_attempt=$(echo $GITHUB_RUN | jq -r '.run_attempt')

container_name="github-runner-${github_job_id}-${github_run_attempt}"
podman stop -t 0 ${container_name}
podman rm ${container_name}

echo "Cleanup complete"
