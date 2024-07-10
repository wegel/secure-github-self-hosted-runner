#!/bin/sh
set -eu

container_name="github-runner-${GITHUB_JOB_ID}-${GITHUB_JOB_SHORT_HASH}"

podman rm --force ${container_name} || true >/dev/null

podman run -d  --device /dev/net/tun --security-opt label=disable --user podman --name ${container_name} \
  -v $(pwd)/fake-docker:/usr/bin/docker \
     localhost/examples-full-rootless-pinp:latest tail -f /dev/null

podman wait --condition=running ${container_name} >/dev/null

echo "Obtaining registration token..."
export runner_token=$(./get_runner_registration_token)
echo "Registration token obtained"

podman exec -it ${container_name} /app/runner/config.sh \
  --url ${GITHUB_URL} --token ${runner_token} --name ${RUNNER_NAME} --work /work --replace \
  --unattended --ephemeral \
  --labels lol/${GITHUB_REPOSITORY}/refs/heads/${GITHUB_BRANCH}/${GITHUB_SHA}/${GITHUB_RUN_ID}/${GITHUB_RUN_NUMBER}/${GITHUB_RUN_ATTEMPT}

echo "Container started and runner prepared"
