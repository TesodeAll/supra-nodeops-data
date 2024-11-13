#!/bin/bash

SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_rpc_configs"

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_rpc_config.toml | awk -F'=' '{print $2}' | tr -d ' "')

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi
# Stop the Docker container if it's running
echo "Stopping rpc container"
if ! docker stop supra_rpc_$ip_address; then
    echo "Failed to stop rpc container. Exiting..."
fi
echo "Supra container stopped"

# Remove the Docker container
echo "Removing rpc container"
if ! docker rm supra_rpc_$ip_address; then
    echo "Failed to remove rpc container. Exiting..."
fi
echo "rpc container removed"

#rm -rf $SCRIPT_EXECUTION_LOCATION/rpc_archive/* $SCRIPT_EXECUTION_LOCATION/rpc_ledger/*  $SCRIPT_EXECUTION_LOCATION/rpc_store/* $SCRIPT_EXECUTION_LOCATION/rpc_node_logs $SCRIPT_EXECUTION_LOCATION/latest_snapshot.zip $SCRIPT_EXECUTION_LOCATION/snapshot/*

# Remove the old Docker image
echo "Deleting old docker images"
if ! docker rmi asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/rpc-node:v6.3.0; then
    echo "Failed to delete old Docker image. Exiting..."
fi
echo "Deleted the old Docker images"

# Run the Docker container
echo "Running new docker image"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

if !     docker run --name "supra_rpc_$ip_address" \
        -v $SCRIPT_EXECUTION_LOCATION:/supra/configs \
        --user "$USER_ID:$GROUP_ID" \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/rpc_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=4000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/rpc-node:v6.3.2; then
    echo "Failed to run new Docker image. Exiting..."
    exit 1
fi
echo "New Docker image created"

#setup Rclone
curl https://rclone.org/install.sh | sudo bash
mkdir -p ~/.config/rclone/
touch ~/.config/rclone/rclone.conf
cat <<EOF > ~/.config/rclone/rclone.conf
[cloudflare-r2]
type = s3
provider = Cloudflare
access_key_id = 229502d7eedd0007640348c057869c90
secret_access_key = 799d15f4fd23c57cd0f182f2ab85a19d885887d745e2391975bb27853e2db949
region = auto
endpoint = https://4ecc77f16aaa2e53317a19267e3034a4.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
EOF

rclone sync cloudflare-r2:testnet-snapshot/snapshots/store $SCRIPT_EXECUTION_LOCATION/rpc_store/ --progress
rclone sync cloudflare-r2:testnet-snapshot/snapshots/archive $SCRIPT_EXECUTION_LOCATION/rpc_archive/ --progress


docker cp $SCRIPT_EXECUTION_LOCATION/genesis.blob supra_rpc_$ip_address:/supra/
docker cp $SCRIPT_EXECUTION_LOCATION/config.toml supra_rpc_$ip_address:/supra/

echo "Starting the RPC node......."

/usr/bin/expect <<EOF
spawn docker exec -it supra_rpc_$ip_address /supra/rpc_node
expect "Starting logger runtime"
send "\r"
expect eof
EOF
