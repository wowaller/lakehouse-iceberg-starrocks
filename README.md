# StarRocks Integration with GCP BigLake Iceberg REST Catalog

This project contains scripts to automate the deployment of a single-node StarRocks (v3.5.19) cluster on a Google Compute Engine (GCE) VM and verify its integration with Google Cloud BigLake Iceberg REST Catalog.

## Architecture

The setup deploys StarRocks (FE and BE) on a single VM in a secure, private VPC subnet.
*   **Metadata Access**: StarRocks FE connects to the BigLake Iceberg REST Catalog API (`https://biglake.googleapis.com/iceberg/v1/restcatalog`) to fetch schemas and table metadata.
*   **Data Access**: StarRocks BE reads the underlying Iceberg data files directly from Google Cloud Storage (GCS) using the VM's Google Service Account (Instance Role).

```
+-------------------------------------------------------------+
| GCE VM (starrocks-test-vm)                                  |
|  +------------------+             +------------------+      |
|  |   StarRocks FE   |             |   StarRocks BE   |      |
|  +--------+---------+             +--------+---------+      |
+-----------|--------------------------------|----------------+
            | (REST Metadata API)            | (GCS Read)
            v                                v
+---------------------------+     +---------------------------+
|    GCP BigLake Metastore  |     |     Google Cloud Storage  |
|    (Iceberg REST Catalog) |     |  (gs://binggang-lab-...)  |
+---------------------------+     +---------------------------+
```

## Directory Structure

*   `create_sr_vm.sh`: Script to provision the GCE VM in the specified project and VPC subnet.
*   `setup_sr_inside_vm.sh`: Deployment script that runs inside the VM (installs Java, downloads StarRocks, configures FE/BE, and registers the Backend).
*   `deploy_sr.sh`: Host orchestrator script that creates the VM, copies the setup script, and runs it on the VM.
*   `test_catalog.sh`: Test script that runs inside the VM to fetch the GCP OAuth2 token, create the external catalog, and query a test table.
*   `run_test.sh`: Host helper script to copy and run `test_catalog.sh` on the VM.

## Prerequisites

1.  **Google Cloud SDK (gcloud)**: Must be installed and authenticated on your local workstation.
2.  **VPC Network**: A VPC network (default: `local-lab`) and subnet (default: `local-lab-us`) in region `us-central1`.
3.  **Cloud NAT**: The private subnet must have Cloud NAT configured so the VM can download packages and StarRocks tarball from the internet without having a public IP.
4.  **BigLake Catalog**: An existing BigLake Iceberg Catalog (default: `binggang-lab-lakehouse`) with a table (default: `sentiment_analysis.sentiment_summary`).
5.  **Permissions**: The VM's default compute service account (`<project-number>-compute@developer.gserviceaccount.com`) must have the following roles:
    *   `roles/biglake.admin` (or `roles/biglake.viewer`)
    *   `roles/storage.admin` (or read/write access to the GCS bucket)

## Configuration

You can configure the project ID, zone, subnet, and VM name by editing the variables at the top of the host scripts:
*   [deploy_sr.sh](deploy_sr.sh)
*   [create_sr_vm.sh](create_sr_vm.sh)
*   [run_test.sh](run_test.sh)

The catalog details, GCS bucket, and query parameters can be configured in [test_catalog.sh](test_catalog.sh).

## Usage

### 1. Deploy StarRocks
Run the deployment script from your workstation:
```bash
bash deploy_sr.sh
```
This script will:
1.  Create the GCE VM `starrocks-test-vm` in zone `us-central1-b`.
2.  Wait for SSH to become ready.
3.  Copy and run `setup_sr_inside_vm.sh` inside the VM.
4.  Download StarRocks 3.5.19, configure it, start FE/BE, and pair them.

### 2. Run the Catalog Integration Test
Run the test script from your workstation:
```bash
bash run_test.sh
```
This script will:
1.  Copy `test_catalog.sh` to the VM.
2.  Execute it, which will:
    *   Fetch the local GCP service account access token.
    *   Create the `bq_iceberg` catalog in StarRocks using the token.
    *   List the databases and tables in the catalog.
    *   Query the first 5 rows of `sentiment_analysis.sentiment_summary`.

## Key Configuration Note: Opaque Token Authentication

Standard Iceberg REST Catalog clients expect the `token` property to contain a JWT (Base64-encoded JSON) and will fail with `IllegalArgumentException` when trying to parse opaque GCP access tokens (e.g. `ya29...`).

To resolve this, our configuration bypasses the `token` property and sends the token directly as a custom HTTP header using `header.Authorization`:

```sql
CREATE EXTERNAL CATALOG bq_iceberg
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "rest",
    "uri" = "https://biglake.googleapis.com/iceberg/v1/restcatalog",
    "warehouse" = "gs://binggang-lab-lakehouse",
    "gcp.gcs.use_instance_role" = "true",
    "header.Authorization" = "Bearer <GCP_ACCESS_TOKEN>"
);
```

## Clean Up

To delete the VM and clean up the Compute Engine resources:
```bash
gcloud compute instances delete starrocks-test-vm --zone=us-central1-b --project=binggang-lab
```
