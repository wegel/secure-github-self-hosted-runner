#!/bin/sh
set -eu

github_run_id=$(echo $GITHUB_RUN | jq -r '.id')
github_run_number=$(echo $GITHUB_RUN | jq -r '.run_number')
github_run_attempt=$(echo $GITHUB_RUN | jq -r '.run_attempt')
github_repository=$(echo $GITHUB_RUN | jq -r '.repository.full_name')
github_sha=$(echo $GITHUB_RUN | jq -r '.head_sha')
github_url=$(echo $GITHUB_RUN | jq -r '.repository.html_url')
github_branch=$(echo $GITHUB_RUN | jq -r '.head_branch')

github_job_id=$(echo $GITHUB_JOB | jq -r '.id')

runner_name="sghr-${github_job_id}-${github_run_attempt}"
container_name="github-runner-${github_job_id}-${github_run_attempt}"

podman rm --force ${container_name} || true >/dev/null

podman run -td -h nex-builder --security-opt label=disable \
  --device /dev/net/tun --device /dev/fuse \
  --user podman --name ${container_name} \
  -v $(pwd)/fake-docker:/usr/bin/docker \
     localhost/executors-full-rootless-pinp:latest tail -f /dev/null

podman wait --condition=running ${container_name} >/dev/null

echo "Obtaining registration token..."
runner_token=$(./get_runner_registration_token)
echo "Registration token obtained"

podman exec -it ${container_name} /app/runner/config.sh \
  --url ${github_url} --token ${runner_token} --name ${runner_name} --work /work --replace \
  --unattended --ephemeral \
  --labels lol/${github_repository}/refs/heads/${github_branch}/${github_sha}/${github_run_id}/${github_run_number}/${github_run_attempt}

echo "Container started and runner prepared"
