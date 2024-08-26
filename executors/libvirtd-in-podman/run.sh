#!/usr/bin/env bash
set -euo pipefail

currentDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
#source ${currentDir}/env.sh # Get variables from base script.

github_run_id=$(echo $GITHUB_RUN | jq -r '.id')
github_run_number=$(echo $GITHUB_RUN | jq -r '.run_number')
github_run_attempt=$(echo $GITHUB_RUN | jq -r '.run_attempt')
github_repository=$(echo $GITHUB_RUN | jq -r '.repository.full_name')
github_sha=$(echo $GITHUB_RUN | jq -r '.head_sha')
github_url=$(echo $GITHUB_RUN | jq -r '.repository.html_url')
github_branch=$(echo $GITHUB_RUN | jq -r '.head_branch')

github_job_id=$(echo $GITHUB_JOB | jq -r '.id')

runner_name="shghr-${github_job_id}-${github_run_attempt}"
container_name="github-runner-${github_job_id}-${github_run_attempt}"

VM_IP=$(podman exec -it -e VM_ID=${github_job_id}-${github_run_attempt} -e VM_IMAGE=fedora-39-worker-base.qcow2  ${container_name} cat /tmp/vm_data/ip | tr -d '\r')

podman exec -it -e VM_ID=${github_job_id}-${github_run_attempt} -e VM_IMAGE=fedora-39-worker-base.qcow2  ${container_name} \
  ssh -i /tmp/vm_data/id_ed25519 -o LogLevel=error -o ServerAliveInterval=60 -o ServerAliveCountMax=10 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  runner@$VM_IP \
  /home/runner/run.sh

echo "Runner execution complete"
