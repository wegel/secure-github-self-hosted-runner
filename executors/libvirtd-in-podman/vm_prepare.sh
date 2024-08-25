#!/usr/bin/env bash
set -euo pipefail

_get_vm_ip() {
	virsh -q domifaddr "${VM_ID:-runner-vm}" | awk '{print $4}' | sed -E 's|/([0-9]+)?$||'
}

data_dir="/tmp/vm_data"

# generate a unique keypair for the VM
mkdir -p "$data_dir"
rm -f "${data_dir}/id_ed25519" "${data_dir}/id_ed25519.pub"
ssh-keygen -t ed25519 -f "${data_dir}/id_ed25519" -N "" >/dev/null 2>&1

# Create a cloud-init config file
cat >"${data_dir}/cloud-init.yaml" <<EOF
#cloud-config
password: lalol1
chpasswd: { expire: False }
ssh_pwauth: True
users:
  - name: root
    ssh-authorized-keys:
      - $(cat ${data_dir}/id_ed25519.pub)
  - name: runner
    ssh-authorized-keys:
      - $(cat ${data_dir}/id_ed25519.pub)
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
EOF

mkdir -p /share

# Install the VM
virt-install \
	--name "${VM_ID:-runner-vm}" \
	--os-variant "${VM_OS_VARIANT:-fedora38}" \
	--disk=path=/tmp/vm.qcow2,size="${VM_DISK_SIZE:-32}",backing_store="${VM_BASE_IMAGE_PATH:-/data/base.qcow2}" \
	--osinfo="${VM_OS_VARIANT:-fedora38}" \
	--vcpus="${VM_CPUS:-$(nproc --ignore=4)}" \
	--ram="${VM_RAM:-16384}" \
	--filesystem=/share,share,driver.type=virtiofs \
	--memorybacking=source.type=memfd,access.mode=shared \
	--cloud-init "user-data=${data_dir}/cloud-init.yaml,disable=on" \
	--import \
	--network default \
	--graphics none \
	--noautoconsole \
	--quiet

# Wait for VM to get IP
echo 'Waiting for VM to get IP'
for i in $(seq 1 30); do
	vm_ip=$(_get_vm_ip)

	if [ -n "${vm_ip}" ]; then
		echo "VM got IP: ${vm_ip}"
		echo "${vm_ip}" > "${data_dir}/ip"
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
	if ssh -i "${data_dir}/id_ed25519" -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "root@${vm_ip}" "true" >/dev/null 2>/dev/null; then
		break
	fi

	if [ "$i" == "30" ]; then
		echo 'Waited 30 seconds for sshd to start, exiting...'
		exit 11
	fi

	sleep 1s
done

echo "The VM is ready."
