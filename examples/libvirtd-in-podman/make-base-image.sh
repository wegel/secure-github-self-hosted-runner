#!/bin/sh
set -eu

image_name=${IMAGE_NAME:-fedora-39-worker-base.qcow2}
root_password=${ROOT_PASSWORD:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c16)}
image_size=${IMAGE_SIZE:-8G} # we just need enough to install the packages; we resize when we create the VM

if [ -n "${VERBOSE:-}"]; then
	echo "root_password: ${root_password}"
fi

podman build . -t base-worker-image-builder-base:latest
podman build . -t base-worker-image-builder:latest -f - <<'EOF'
FROM base-worker-image-builder-base:latest
# install the ubuntu kernel, necessary for virt-builder/install to work 🤷
RUN apt update && apt install -y linux-image-generic
EOF

podman run -i --rm -e IMAGE_NAME=${image_name} -e IMAGE_SIZE=${image_size} -e ROOT_PASSWORD=${root_password} \
        -v ${IMAGES_DIR:-$(pwd)}:/images \
        base-worker-image-builder:latest bash -s <<'EOF'
set -euo pipefail

# note: we need github-runner to manage the cache and builds directories

cp /images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2 /images/${IMAGE_NAME}
# Uncomment for debugging libguestfs
# export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1
export LIBGUESTFS_BACKEND=direct
virt-customize -a /images/${IMAGE_NAME} \
		--memsize 4096 \
		--smp 4 \
    --network \
    --hostname github-worker \
		--run-command "sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config" \
    --install @buildsys-build,make,git,git-lfs,curl,skopeo,podman,wget \
    --run-command "git lfs install --skip-repo" \
    --run-command "curl -fsSL https://get.docker.com | sh" \
    --run-command "mkdir /home/github-runner && cd /home/github-runner" \
    --run-command "curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz" \
    --run-command "tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz && rm actions-runner-linux-*.tar.gz" \
    --root-password password:${ROOT_PASSWORD}
EOF
#    --run-command "echo 'shared /home/github-runner/shared virtiofs defaults,nofail 0 0' >> /etc/fstab" \
