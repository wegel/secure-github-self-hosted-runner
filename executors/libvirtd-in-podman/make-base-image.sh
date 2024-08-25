#!/bin/sh
set -eu

image_name=${IMAGE_NAME:-fedora-39-worker-base.qcow2}
root_password=${ROOT_PASSWORD:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c16)}
image_size=${IMAGE_SIZE:-6G} # we just need enough to install the packages; we resize when we create the VM

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
        -v ${IMAGES_DIR}:/images \
        base-worker-image-builder:latest bash -s <<'EOF'
set -euo pipefail

# rm -f /images/${IMAGE_NAME} || true
# truncate -r /images/noble-server-cloudimg-amd64.img /images/${IMAGE_NAME}
# truncate -s +5G /images/${IMAGE_NAME}
# PARTITION=$(virt-filesystems --long -h --all -a /images/noble-server-cloudimg-amd64.img | grep cloudimg-rootfs | awk '{print $1}')
# virt-resize --expand ${PARTITION} /images/noble-server-cloudimg-amd64.img /images/${IMAGE_NAME}
# virt-filesystems --long -h --all -a /images/${IMAGE_NAME} 

cp /images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2 /images/${IMAGE_NAME}
# Uncomment for debugging libguestfs
export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1
export LIBGUESTFS_BACKEND=direct
virt-customize -a /images/${IMAGE_NAME} \
		--memsize 4096 \
		--smp 4 \
    --network \
    --hostname secure-runner-vm \
		--run-command "sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config" \
    --install @buildsys-build,make,git,git-lfs,curl,skopeo,podman,wget,libicu \
    --run-command "git lfs install --skip-repo" \
    --run-command "curl -fsSL https://get.docker.com | sh" \
    --run-command 'useradd -m -s /bin/bash runner' \
    --run-command "mkdir -p /share && chown runner:runner /share && chmod 775 /share" \
    --run-command "echo 'share /share virtiofs defaults,nofail 0 0' >> /etc/fstab" \
    --run-command "curl -o /tmp/actions-runner-linux-x64-2.319.1.tar.gz -L https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-x64-2.319.1.tar.gz" \
    --run-command "tar xzf /tmp/actions-runner-linux-*.tar.gz -C /home/runner && rm /tmp/actions-runner-linux-*.tar.gz" \
    --run-command "chown -R runner:runner /home/runner" \
    --run-command "mkdir -p /work && chown -R runner:runner /work" \
    --run-command "systemctl enable docker.service && systemctl enable containerd.service" \
    --run-command "usermod -aG docker runner" \
    --root-password password:${ROOT_PASSWORD}
EOF

