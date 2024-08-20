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
container_image_name=localhost/examples-libvirtd-in-podman:latest

#libvirt_dir=${LIBVIRT_DIR:-~/.local/containers/gitlab-runner/libvirt}
libvirt_dir=${LIBVIRT_DIR:-$(pwd)}
gitlab_runner_config_file=${GITLAB_RUNNER_CONFIG_FILE:-~/.local/containers/gitlab-runner/config.toml}
storage_conf=${STORAGE_CONF:-~/.local/containers/gitlab-runner/storage.conf}

podman rm --force ${container_name} || true >/dev/null
podman run -d --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
	-v ${gitlab_runner_config_file}:/etc/gitlab-runner/config.toml \
	-v ${libvirt_dir}:/var/lib/libvirt/images \
	-v ${storage_conf}:/etc/containers/storage.conf \
	--name ${container_name} ${container_image_name}

podman wait --condition=running ${container_name} >/dev/null

echo "Obtaining registration token..."
runner_token=$(../../bin/get_runner_registration_token)
echo "Registration token obtained"

podman exec -it -e VM_ID=${github_job_id}-${github_run_attempt} -e VM_IMAGE=fedora-39-worker-base.qcow2 ${container_name} /app/vm_prepare.sh \
  --url ${github_url} --token ${runner_token} --name ${runner_name} --work /work --replace \
  --unattended --ephemeral \
  --labels lol/${github_repository}/refs/heads/${github_branch}/${github_sha}/${github_run_id}/${github_run_number}/${github_run_attempt}

echo "Container started and runner prepared"
