#!/bin/bash
# run_test.sh
# Copies and executes the catalog test script on the StarRocks VM.

set -euo pipefail

PROJECT_ID="binggang-lab"
ZONE="us-central1-b"
VM_NAME="starrocks-test-vm"

echo "Copying test script to VM..."
gcloud compute scp --project="${PROJECT_ID}" --zone="${ZONE}" test_catalog.sh "${VM_NAME}:~/test_catalog.sh" --tunnel-through-iap

echo "Executing test script on VM..."
gcloud compute ssh --project="${PROJECT_ID}" --zone="${ZONE}" "${VM_NAME}" --tunnel-through-iap --command="chmod +x test_catalog.sh && ./test_catalog.sh"
