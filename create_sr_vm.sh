#!/bin/bash
# create_sr_vm.sh
# Provisions a VM for StarRocks deployment in the local-lab network.

set -euo pipefail

PROJECT_ID="binggang-lab"
ZONE="us-central1-b"
SUBNET="local-lab-us"
VM_NAME="starrocks-test-vm"

echo "===================================================="
echo "Provisioning StarRocks VM: ${VM_NAME}"
echo "Project:                   ${PROJECT_ID}"
echo "Zone:                      ${ZONE}"
echo "Subnet:                    ${SUBNET}"
echo "===================================================="

if gcloud compute instances describe "${VM_NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "VM ${VM_NAME} already exists. Skipping creation."
else
  echo "Creating VM..."
  gcloud compute instances create "${VM_NAME}" \
      --project="${PROJECT_ID}" \
      --zone="${ZONE}" \
      --subnet="${SUBNET}" \
      --no-address \
      --machine-type=n4-standard-8 \
      --image-project=debian-cloud \
      --image-family=debian-12 \
      --boot-disk-size=100 \
      --scopes=cloud-platform \
      --metadata="startup-script=apt-get update && apt-get install -y git gnupg curl wget net-tools default-jdk"
fi

echo "===================================================="
echo "VM is ready or already existed."
echo "===================================================="
