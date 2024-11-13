#!/bin/bash

SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_configs"
CONFIG_FILE="$(pwd)/operator_config.toml"

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config.toml | awk -F'=' '{print $2}' | tr -d ' "')

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi
# Stop the Docker container if it's running
echo "Stopping supra container"
if ! docker stop supra_$ip_address; then
    echo "Failed to stop supra container. Exiting..."
fi
echo "Supra container stopped"

#rm -rf $SCRIPT_EXECUTION_LOCATION/ledger_storage $SCRIPT_EXECUTION_LOCATION/smr_storage/* $SCRIPT_EXECUTION_LOCATION/supra_node_logs $SCRIPT_EXECUTION_LOCATION/latest_snapshot.zip $SCRIPT_EXECUTION_LOCATION/snapshot

# Start the Docker container if it's running
echo "Starting supra container"
if ! docker start supra_$ip_address; then
    echo "Failed to Start supra container."
fi
echo "Supra container Start"

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

rclone sync cloudflare-r2:testnet-snapshot/snapshots/store $SCRIPT_EXECUTION_LOCATION/smr_storage/ --progress

function parse_toml() {
    grep -w "$1" "$2" | cut -d'=' -f2- | tr -d ' "'
}


encoded_pswd=$(parse_toml "password" "$CONFIG_FILE")
password=$(echo "$encoded_pswd" | openssl base64 -d -A)

expect << EOF
    spawn docker exec -it supra_$ip_address /supra/supra node smr run
    expect "password:" { send "$password\r" }
    expect eof
EOF
