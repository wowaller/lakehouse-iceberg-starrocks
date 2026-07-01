#!/bin/bash
# deploy_sr.sh
# Host script to orchestrate the creation and deployment of StarRocks on GCP VM.

set -euo pipefail

PROJECT_ID="binggang-lab"
ZONE="us-central1-b"
VM_NAME="starrocks-test-vm"

# 1. Create the VM
chmod +x create_sr_vm.sh
./create_sr_vm.sh

# 2. Wait for VM ssh to be ready
echo "Waiting for VM ${VM_NAME} to be ready for SSH..."
# We can poll using gcloud compute ssh with a simple command
for i in {1..30}; do
  if gcloud compute ssh --project="${PROJECT_ID}" --zone="${ZONE}" "${VM_NAME}" --tunnel-through-iap --command="echo 'SSH ready'" >/dev/null 2>&1; then
    echo "SSH is ready!"
    break
  fi
  echo "Still waiting..."
  sleep 5
done

# 3. Copy setup script to VM
echo "Copying setup script to VM..."
gcloud compute scp --project="${PROJECT_ID}" --zone="${ZONE}" setup_sr_inside_vm.sh "${VM_NAME}:~/setup_sr_inside_vm.sh" --tunnel-through-iap

# 4. Execute setup script on VM
echo "Executing setup script on VM..."
gcloud compute ssh --project="${PROJECT_ID}" --zone="${ZONE}" "${VM_NAME}" --tunnel-through-iap --command="chmod +x setup_sr_inside_vm.sh && ./setup_sr_inside_vm.sh"

echo "===================================================="
echo "StarRocks VM deployment and setup completed!"
echo "===================================================="
