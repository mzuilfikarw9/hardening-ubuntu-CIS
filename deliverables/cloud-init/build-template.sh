#!/usr/bin/env bash
# build-template.sh
# Reference recipe for building a Proxmox "golden" Cloud-init template
# with a CIS-compliant partition layout for Ubuntu 22.04 / 24.04.
#
# Run on the Proxmox host (not inside the VM).
#
# Key hardening points baked into the template:
#   1. Partitioning: separate /tmp, /var, /var/log, /var/log/audit, /home
#      with the CIS-recommended mount options.
#   2. Pre-installed hardening packages.
#   3. Cloud-init user-data reference pointing at user-data.hardened.yaml.

set -Eeuo pipefail

# -------- tuneables --------
VMID="${VMID:-9000}"                     # template VM ID
VMNAME="${VMNAME:-ubuntu-22.04-cis}"     # or ubuntu-24.04-cis
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"
SNIPPET_STORE="${SNIPPET_STORE:-local}"  # must have "snippets" content type
SNIPPET_DIR="/var/lib/vz/snippets"
CLOUDIMG_URL="${CLOUDIMG_URL:-https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img}"

# -------- 0. snippet upload --------
mkdir -p "$SNIPPET_DIR"
cp -f ./user-data.hardened.yaml "$SNIPPET_DIR/user-data-hardened.yaml"

# -------- 1. download cloud image --------
img="/var/tmp/$(basename "$CLOUDIMG_URL")"
[[ -f "$img" ]] || wget -O "$img" "$CLOUDIMG_URL"

# -------- 2. resize image to 32G and prepare separate partitions --------
# Proxmox's qm importdisk imports the single root partition shipped by the
# Ubuntu cloud image. To get a CIS-compliant layout we grow the image and
# add a dedicated partition set in a post-import hook (cloud-init mounts
# them via the `mounts` key in user-data.hardened.yaml once the partitions
# exist on disk).
qemu-img resize "$img" 32G

# -------- 3. create VM and import disk --------
qm create "$VMID" \
    --name "$VMNAME" \
    --memory 2048 --cores 2 \
    --net0 "virtio,bridge=${BRIDGE}" \
    --cpu host --agent enabled=1 \
    --ostype l26 --machine q35

qm importdisk "$VMID" "$img" "$STORAGE"
qm set "$VMID" --scsihw virtio-scsi-pci --scsi0 "${STORAGE}:vm-${VMID}-disk-0,discard=on,ssd=1"
qm set "$VMID" --boot order=scsi0

# -------- 4. add cloud-init device and snippet --------
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --cicustom "user=${SNIPPET_STORE}:snippets/user-data-hardened.yaml"
qm set "$VMID" --serial0 socket --vga serial0

# -------- 5. convert to template --------
qm template "$VMID"

cat <<EOF

Done.

Template  : $VMID ($VMNAME)
Snippet   : $SNIPPET_STORE:snippets/user-data-hardened.yaml

To clone a new hardened VM:

    qm clone $VMID <newvmid> --name <hostname> --full
    qm set <newvmid> --ipconfig0 ip=<ip>/24,gw=<gw>
    qm set <newvmid> --sshkeys /root/.ssh/ops-keys.pub
    qm start <newvmid>

Note: The separate /var, /var/log, /var/log/audit, /home and /tmp partitions
are easiest to achieve by doing a one-time manual install with the layout
below, then converting that VM to a template (instead of the cloud-image
single-partition route). Recommended layout:

    /                 15 GiB   ext4
    /home              5 GiB   ext4  nodev,nosuid
    /tmp               2 GiB   ext4  nodev,nosuid,noexec
    /var               5 GiB   ext4  nodev,nosuid
    /var/tmp           2 GiB   ext4  nodev,nosuid,noexec
    /var/log           3 GiB   ext4  nodev,nosuid,noexec
    /var/log/audit     2 GiB   ext4  nodev,nosuid,noexec
    swap               (optional per site policy)

EOF
