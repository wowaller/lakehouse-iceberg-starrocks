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

## Connecting to StarRocks

Since the VM is deployed in a private subnet, you can connect to the StarRocks Frontend (query port `9030`) using one of the following methods:

### Method 1: SSH Port Forwarding (Recommended for Workstation)
Forward port `9030` from the VM to your local workstation:
```bash
gcloud compute ssh starrocks-test-vm \
  --zone=us-central1-b \
  --project=binggang-lab \
  --tunnel-through-iap \
  -- -L 9030:127.0.0.1:9030 -N
```
Then connect locally using any MySQL-compatible client:
```bash
mysql -h 127.0.0.1 -P 9030 -uroot
```

### Method 2: SSH and Run Locally on VM
SSH into the VM:
```bash
gcloud compute ssh starrocks-test-vm --zone=us-central1-b --project=binggang-lab --tunnel-through-iap
```
Then run the pre-installed MySQL client inside the VM:
```bash
mysql -h 127.0.0.1 -P 9030 -uroot
```

### Method 3: Internal VPC Connection
If connecting from another VM (e.g., Spark cluster) in the same VPC network (`local-lab`), connect directly to the internal IP of the FE node:
```bash
mysql -h <starrocks-fe-internal-ip> -P 9030 -uroot
```
*(The default internal IP for the test VM is `10.0.0.27`).*

## Authentication Options

To connect StarRocks to the BigLake REST Catalog, you have two options for authentication:

### Option 1: Automatic OAuth2 Auth via GoogleAuthManager (Recommended)
This method uses the Google Cloud SDK's Application Default Credentials (ADC) to automatically fetch and rotate access tokens. It is the most robust option and prevents queries from failing due to token expiry.

This requires copying `iceberg-gcp-1.10.0.jar` and `iceberg-gcp-bundle-1.10.0.jar` to StarRocks' `fe/lib/` directory.

```sql
CREATE EXTERNAL CATALOG bq_iceberg
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "rest",
    "uri" = "https://biglake.googleapis.com/iceberg/v1/restcatalog",
    "warehouse" = "gs://binggang-lab-lakehouse",
    "gcp.gcs.use_instance_role" = "true",
    "io-impl" = "org.apache.iceberg.gcp.gcs.GCSFileIO",
    "rest.auth.type" = "org.apache.iceberg.gcp.auth.GoogleAuthManager",
    "header.x-goog-user-project" = "binggang-lab"
);
```


## Configuring an Existing StarRocks Cluster

If you already have a running StarRocks cluster (v3.1.x or later) and want to connect it to a GCP BigLake Iceberg REST Catalog, follow these steps:

### Step 1: Enable JNI on StarRocks BE Nodes
Iceberg integration requires the Java Native Interface (JNI) to load Iceberg Java libraries inside the BE C++ process.
1.  Ensure JDK (JDK 8, 11, or 17) is installed on all BE instances.
2.  Edit the BE configuration file `be/conf/be.conf` on each BE node and set the `JAVA_HOME` property:
    ```properties
    JAVA_HOME = /usr/lib/jvm/default-java
    ```
    *(Replace `/usr/lib/jvm/default-java` with the actual path of your JDK).*
3.  Restart all BE services to apply the change:
    ```bash
    ./be/bin/stop_be.sh
    ./be/bin/start_be.sh --daemon
    ```

### Step 2: Install GCP Iceberg Jars (Recommended for Automatic Auth)
If you want StarRocks to automatically manage token lifecycle using `GoogleAuthManager` (Option 1):
1.  Download `iceberg-gcp` and `iceberg-gcp-bundle` jars (version `1.10.0` or later is required for `GoogleAuthManager`).
    ```bash
    wget https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-gcp/1.10.0/iceberg-gcp-1.10.0.jar
    wget https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-gcp-bundle/1.10.0/iceberg-gcp-bundle-1.10.0.jar
    ```
2.  Copy both jars to the `fe/lib/` directory of all your StarRocks Frontend instances.
3.  Restart all FE services:
    ```bash
    ./fe/bin/stop_fe.sh
    ./fe/bin/start_fe.sh --daemon
    ```

### Step 3: Grant IAM Permissions to StarRocks BE Instances
StarRocks BE nodes need permissions to read data files from GCS.
*   **If using Instance Role (Recommended)**:
    1.  Identify the Service Account attached to your GCE VMs.
    2.  Grant this Service Account the **Storage Object Viewer** (or **Storage Admin**) role on the GCS bucket containing the Iceberg data.
*   **If using Service Account Key File**:
    *   Create a GCP service account, download its JSON key file, copy it to the StarRocks nodes, and refer to it in the catalog properties (using `gcp.gcs.credential.file.path` property).

### Step 4: Create the External Catalog in StarRocks
Connect to StarRocks using a MySQL client and run the following DDL to create the catalog. This uses `GoogleAuthManager` for automatic credentials handling:

```sql
CREATE EXTERNAL CATALOG biglake_iceberg
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "rest",
    "uri" = "https://biglake.googleapis.com/iceberg/v1/restcatalog",
    "warehouse" = "gs://<your-gcs-bucket-name>",
    "gcp.gcs.use_instance_role" = "true",
    "io-impl" = "org.apache.iceberg.gcp.gcs.GCSFileIO",
    "rest.auth.type" = "org.apache.iceberg.gcp.auth.GoogleAuthManager",
    "header.x-goog-user-project" = "<your-gcp-project-id>"
);
```
Replace:
*   `<your-gcs-bucket-name>`: The GCS bucket containing your Iceberg tables.
*   `<your-gcp-project-id>`: Your GCP Project ID (used for billing project header).

### Step 5: Verify Connectivity
Run basic queries to verify:
```sql
SHOW DATABASES FROM biglake_iceberg;
USE biglake_iceberg.<your-database-name>;
SHOW TABLES;
SELECT * FROM <your-table-name> LIMIT 10;
```

## Outdated / Alternative Methods

### Manual Token Authentication (Alternative)
If you cannot add the `iceberg-gcp` jars to the classpath to use `GoogleAuthManager`, you can fall back to manual token authentication. 

#### Setup Steps:
1.  **Obtain GCP Access Token**: Fetch a token from the metadata server or via `gcloud`:
    ```bash
    TOKEN=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    ```
2.  **Create Catalog in StarRocks**: Bypasses standard JWT token parsing by sending the token as `header.Authorization`:
    ```sql
    CREATE EXTERNAL CATALOG biglake_iceberg
    PROPERTIES (
        "type" = "iceberg",
        "iceberg.catalog.type" = "rest",
        "uri" = "https://biglake.googleapis.com/iceberg/v1/restcatalog",
        "warehouse" = "gs://<your-gcs-bucket-name>",
        "gcp.gcs.use_instance_role" = "true",
        "header.Authorization" = "Bearer <GCP_ACCESS_TOKEN>"
    );
    ```
3.  **Handling Token Expiry**: The token expires after 1 hour. You must update it using `ALTER CATALOG`:
    ```sql
    ALTER CATALOG biglake_iceberg SET PROPERTIES (
        "header.Authorization" = "Bearer <NEW_GCP_ACCESS_TOKEN>"
    );
    ```

## Clean Up

To delete the VM and clean up the Compute Engine resources:
```bash
gcloud compute instances delete starrocks-test-vm --zone=us-central1-b --project=binggang-lab
```
