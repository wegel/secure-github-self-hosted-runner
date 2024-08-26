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

runner_name="shghr-${github_job_id}-${github_run_attempt}"
container_name="github-runner-${github_job_id}-${github_run_attempt}"
container_image_name=localhost/executors-libvirtd-in-podman:latest

libvirt_dir=${LIBVIRT_DIR:-$(pwd)}

podman rm --force ${container_name} || true >/dev/null
podman run -di --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
	-v ${libvirt_dir}:/data \
	--name ${container_name} ${container_image_name}

podman wait --condition=running ${container_name} >/dev/null

echo "Obtaining registration token..."
runner_token=$(../../bin/get_runner_registration_token)
echo "Registration token obtained"

podman exec -it -e VM_BASE_IMAGE_PATH=/data/fedora-39-worker-base.qcow2  ${container_name} /app/vm_prepare.sh
vm_ip=$(podman exec ${container_name} cat /tmp/vm_data/ip | tr -d '\r')

podman exec -i ${container_name} \
  ssh -i /tmp/vm_data/id_ed25519 -o LogLevel=error -o ServerAliveInterval=60 -o ServerAliveCountMax=10 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    runner@${vm_ip} /home/runner/config.sh \
      --url ${github_url} --token ${runner_token} --name ${runner_name} --work /work --replace \
      --unattended --ephemeral \
      --labels shghr/${github_repository}/refs/heads/${github_branch}/${github_sha}/${github_run_id}/${github_run_number}/${github_run_attempt}

echo "Container started and runner prepared"
