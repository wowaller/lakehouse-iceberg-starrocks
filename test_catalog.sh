#!/bin/bash
# test_catalog.sh
# Script to test the BigLake Iceberg REST Catalog inside the StarRocks VM.

set -euo pipefail

echo "===================================================="
echo "Testing BigLake Iceberg Catalog in StarRocks"
echo "===================================================="

# 1. Fetch GCP access token
echo "Fetching GCP access token from metadata server..."
# Using grep/cut to avoid dependency on jq
TOKEN_RESPONSE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token)
TOKEN=$(echo "${TOKEN_RESPONSE}" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "${TOKEN}" ]; then
  echo "ERROR: Failed to fetch access token."
  echo "Response: ${TOKEN_RESPONSE}"
  exit 1
fi
echo "Access token fetched successfully."

# 2. Create catalog SQL
CATALOG_NAME="bq_iceberg"
SQL_CREATE="
CREATE EXTERNAL CATALOG ${CATALOG_NAME}
PROPERTIES (
    \"type\" = \"iceberg\",
    \"iceberg.catalog.type\" = \"rest\",
    \"uri\" = \"https://biglake.googleapis.com/iceberg/v1/restcatalog\",
    \"warehouse\" = \"gs://binggang-lab-lakehouse\",
    \"gcp.gcs.use_instance_role\" = \"true\",
    \"header.Authorization\" = \"Bearer ${TOKEN}\"
);
"

echo "Creating catalog in StarRocks..."
# Drop catalog if exists first to allow retries
mysql -h 127.0.0.1 -P 9030 -uroot -e "DROP CATALOG IF EXISTS ${CATALOG_NAME};"
mysql -h 127.0.0.1 -P 9030 -uroot -e "${SQL_CREATE}"

echo "Listing databases in catalog..."
mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW DATABASES FROM ${CATALOG_NAME};"

echo "Listing tables in sentiment_analysis schema..."
mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW TABLES FROM ${CATALOG_NAME}.sentiment_analysis;"

echo "Querying sentiment_summary table (LIMIT 5)..."
mysql -h 127.0.0.1 -P 9030 -uroot -e "SELECT review_id, game, overall_sentiment FROM ${CATALOG_NAME}.sentiment_analysis.sentiment_summary LIMIT 5;"

echo "Running group-by aggregation query..."
mysql -h 127.0.0.1 -P 9030 -uroot -e "SELECT COUNT(*), overall_sentiment FROM ${CATALOG_NAME}.sentiment_analysis.sentiment_summary GROUP BY overall_sentiment;"

echo "===================================================="
echo "Catalog Test Completed!"
echo "===================================================="
