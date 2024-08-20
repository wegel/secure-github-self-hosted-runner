#!/usr/bin/env bash
set -euxo pipefail

_get_vm_ip() {
	virsh -q domifaddr "$VM_ID" | awk '{print $4}' | sed -E 's|/([0-9]+)?$||'
}

#currentDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
#source ${currentDir}/env.sh # Get variables from base script.

# trap any error, and mark it as a system failure.
#trap "exit $SYSTEM_FAILURE_EXIT_CODE" ERR

# generate a unique keypair for the VM
DATA_DIR="/tmp/${VM_ID}"
mkdir -p "$DATA_DIR"

rm -f ${DATA_DIR}/id_ed25519 ${DATA_DIR}/id_ed25519.pub
ssh-keygen -t ed25519 -f ${DATA_DIR}/id_ed25519 -N "" >/dev/null 2>&1

# Create a cloud-init config file using a heredoc and the cat command that outputs a yaml file
cat >"${DATA_DIR}/cloud-init.yaml" <<EOF
#cloud-config
password: lalol1
chpasswd: { expire: False }
ssh_pwauth: True
users:
  - name: root
    ssh-authorized-keys:
      - $(cat ${DATA_DIR}/id_ed25519.pub)
  - name: github-runner
    ssh-authorized-keys:
      - $(cat ${DATA_DIR}/id_ed25519.pub)
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
EOF

mkdir -p /var/lib/libvirt/boot
mkdir -p /var/lib/libvirt/images

# Install the VM
virt-install \
	--name "$VM_ID" \
	--os-variant fedora38 \
	--disk=path=/tmp/lol.qcow2,size=32,backing_store=/var/lib/libvirt/images/ubuntu-24.04-worker-base.qcow2 \
	--memorybacking=source.type=memfd,access.mode=shared \
	--osinfo=fedora38 \
	--cloud-init user-data=${DATA_DIR}/cloud-init.yaml,disable=on \
	--import \
	--vcpus=$(nproc --ignore=4) \
	--ram=16384 \
	--network default \
	--graphics none \
	--noautoconsole \
	--quiet
	
	#--filesystem=/home/gitlab-runner/cache,cache-shared,driver.type=virtiofs \
	#--filesystem=/home/gitlab-runner/builds,ro-builds-shared,driver.type=virtiofs \

# Wait for VM to get IP
echo 'Waiting for VM to get IP'
for i in $(seq 1 30); do
	VM_IP=$(_get_vm_ip)

	if [ -n "$VM_IP" ]; then
		echo "VM got IP: $VM_IP"
		break
	fi

	if [ "$i" == "30" ]; then
		echo 'Waited 30 seconds for VM to start, exiting...'
		exit 10
	fi

	sleep 1s
done

# Wait for ssh to become available
echo "Waiting for sshd to be available"
for i in $(seq 1 30); do
	if ssh -i ${DATA_DIR}/id_ed25519 -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@"$VM_IP" "true" >/dev/null 2>/dev/null; then
		break
	fi

	if [ "$i" == "30" ]; then
		echo 'Waited 30 seconds for sshd to start, exiting...'
		exit 11
	fi

	sleep 1s
done

ssh -i ${DATA_DIR}/id_ed25519 -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@"$VM_IP" /home/github-runner/config.sh "$@"
