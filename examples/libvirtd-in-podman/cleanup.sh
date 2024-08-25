#!/usr/bin/env bash
set -euo pipefail

github_run_attempt=$(echo $GITHUB_RUN | jq -r '.run_attempt')
github_job_id=$(echo $GITHUB_JOB | jq -r '.id')
container_name="github-runner-${github_job_id}-${github_run_attempt}"

podman exec ${container_name} virsh shutdown ${VM_ID:-runner-vm}
podman rm --force ${container_name}
