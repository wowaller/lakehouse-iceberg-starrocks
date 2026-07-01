#!/bin/bash
# setup_sr_inside_vm.sh
# This script runs inside the VM to deploy and configure StarRocks.

set -euo pipefail

echo "===================================================="
echo "Starting StarRocks Setup Inside VM"
echo "===================================================="

# 1. Install dependencies
echo "Installing dependencies (waiting if apt is locked)..."
until sudo apt-get update; do
  echo "Apt update is locked, waiting 5 seconds..."
  sleep 5
done

sudo apt-get install -y default-jdk default-mysql-client wget curl net-tools

# 2. Get internal IP
INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
echo "Internal IP: ${INTERNAL_IP}"

# Determine CIDR for priority_networks (use /16 to cover the VPC subnet range)
CIDR_PREFIX=$(echo "${INTERNAL_IP}" | cut -d'.' -f1-2)
PRIORITY_NETWORK="${CIDR_PREFIX}.0.0/16"
echo "Priority Network configured: ${PRIORITY_NETWORK}"

# 3. Download StarRocks 3.5.19
SR_VERSION="3.5.19"
SR_TARBALL="StarRocks-${SR_VERSION}-ubuntu-amd64.tar.gz"
SR_URL="https://releases.starrocks.io/starrocks/${SR_TARBALL}"

if [ ! -f "${SR_TARBALL}" ]; then
  echo "Downloading StarRocks from ${SR_URL}..."
  wget -q "${SR_URL}"
else
  echo "Tarball ${SR_TARBALL} already exists."
fi

# 4. Extract
SR_DIR="StarRocks-${SR_VERSION}-ubuntu-amd64"
if [ ! -d "${SR_DIR}" ]; then
  echo "Extracting StarRocks..."
  tar -zxf "${SR_TARBALL}"
else
  echo "Directory ${SR_DIR} already exists."
fi

cd "${SR_DIR}"

# 5. Configure FE
echo "Configuring FE..."
FE_CONF="fe/conf/fe.conf"
sudo mkdir -p /var/lib/starrocks/meta
sudo chown -R $USER:$USER /var/lib/starrocks/meta

# Replace or add configs
sed -i "s|# meta_dir =.*|meta_dir = /var/lib/starrocks/meta|g" "${FE_CONF}"
if ! grep -q "^meta_dir" "${FE_CONF}"; then
  echo "meta_dir = /var/lib/starrocks/meta" >> "${FE_CONF}"
fi

if ! grep -q "^priority_networks" "${FE_CONF}"; then
  echo "priority_networks = ${PRIORITY_NETWORK}" >> "${FE_CONF}"
else
  sed -i "s|priority_networks =.*|priority_networks = ${PRIORITY_NETWORK}|g" "${FE_CONF}"
fi

# Set default_replication_num to 1 since we only have 1 BE
if ! grep -q "^default_replication_num" "${FE_CONF}"; then
  echo "default_replication_num = 1" >> "${FE_CONF}"
else
  sed -i "s|default_replication_num =.*|default_replication_num = 1|g" "${FE_CONF}"
fi

# 6. Configure BE
echo "Configuring BE..."
BE_CONF="be/conf/be.conf"
sudo mkdir -p /var/lib/starrocks/storage
sudo chown -R $USER:$USER /var/lib/starrocks/storage

sed -i "s|# storage_root_path =.*|storage_root_path = /var/lib/starrocks/storage|g" "${BE_CONF}"
if ! grep -q "^storage_root_path" "${BE_CONF}"; then
  echo "storage_root_path = /var/lib/starrocks/storage" >> "${BE_CONF}"
fi

if ! grep -q "^priority_networks" "${BE_CONF}"; then
  echo "priority_networks = ${PRIORITY_NETWORK}" >> "${BE_CONF}"
else
  sed -i "s|priority_networks =.*|priority_networks = ${PRIORITY_NETWORK}|g" "${BE_CONF}"
fi

# 7. Start FE
echo "Starting FE..."
./fe/bin/start_fe.sh --daemon

# Wait for FE to start (port 9030)
echo "Waiting for FE to start..."
for i in {1..30}; do
  if ss -an | grep 9030 | grep LISTEN >/dev/null; then
    echo "FE is up and listening on 9030."
    break
  fi
  sleep 2
done

# 8. Start BE
echo "Starting BE..."
./be/bin/start_be.sh --daemon

# Wait for BE to start (heartbeat port 9050)
echo "Waiting for BE to start..."
for i in {1..30}; do
  if ss -an | grep 9050 | grep LISTEN >/dev/null; then
    echo "BE is up and listening on 9050."
    break
  fi
  sleep 2
done

# 9. Add BE to FE
echo "Registering BE with FE..."
# Try to register BE using mysql client. We use 127.0.0.1 and port 9030.
# We run it multiple times if FE is still initializing.
for i in {1..5}; do
  if mysql -h 127.0.0.1 -P 9030 -uroot -e "ALTER SYSTEM ADD BACKEND \"${INTERNAL_IP}:9050\";" 2>/dev/null; then
    echo "BE registered successfully!"
    break
  else
    echo "Retrying BE registration..."
    sleep 5
  fi
done

# Check status
echo "Checking FE and BE status..."
mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW FRONTENDS\G"
mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW BACKENDS\G"

echo "===================================================="
echo "StarRocks Setup Inside VM Completed!"
echo "===================================================="
