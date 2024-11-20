#!/bin/bash

SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_configs_mainnet"
CONFIG_FILE="$(pwd)/operator_config_mainnet.toml"


# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config_mainnet.toml | awk -F'=' '{print $2}' | tr -d ' "')

if [ -f "$(pwd)/onboarding_mainnet.sh" ]; then
    echo "Remove old supra onboarding script"
    rm "$(pwd)/onboarding_mainnet.sh"
fi

if [ -f "$(pwd)/update_version_mainnet_2.sh" ]; then
    echo "Remove old update_version_mainnet_2.sh script"
    rm "$(pwd)/update_version_mainnet_2.sh"
fi


# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi

rm -rf $SCRIPT_EXECUTION_LOCATION/*.sig $SCRIPT_EXECUTION_LOCATION/genesis_config_arbitrary_data.json $SCRIPT_EXECUTION_LOCATION/hashmap_phase_1_previous.toml.bak $SCRIPT_EXECUTION_LOCATION/Hashmap_phase_1_latest.toml $SCRIPT_EXECUTION_LOCATION/hashmap_phase_2_latest.toml $SCRIPT_EXECUTION_LOCATION/smr_storage $SCRIPT_EXECUTION_LOCATION/hashmap_phase_2_previous.toml $SCRIPT_EXECUTION_LOCATION/supra_committees.json $SCRIPT_EXECUTION_LOCATION/extracted $SCRIPT_EXECUTION_LOCATION/supra_history $SCRIPT_EXECUTION_LOCATION/genesis.blob $SCRIPT_EXECUTION_LOCATION/ledger_storage $SCRIPT_EXECUTION_LOCATION/supra_node_logs $SCRIPT_EXECUTION_LOCATION/genesis_configs.json $SCRIPT_EXECUTION_LOCATION/latest_validator_info.json

# Stop the Docker container if it's running
echo "Stopping supra container"
if ! docker stop supra_mainnet_$ip_address; then
    echo "Failed to stop supra container. Exiting..."
fi
echo "Supra container stopped"

# Remove the Docker container
echo "Removing supra container"
if ! docker rm supra_mainnet_$ip_address; then
    echo "Failed to remove supra container. Exiting..."
fi
echo "Supra container removed"

# Remove the old Docker image
echo "Deleting old docker images"
if ! docker rmi asia-docker.pkg.dev/supra-devnet-misc/supra-mainnet/validator-node:v7.1.4; then
    echo "Failed to delete old Docker image. Exiting..."
fi
echo "Deleted the old Docker images"

# Check if smr_settings.toml exists before creating a new one
echo "Changing the smr settings file"
smr_settings_file="$SCRIPT_EXECUTION_LOCATION/smr_settings.toml"
rm ${smr_settings_file}
wget -O $SCRIPT_EXECUTION_LOCATION/smr_settings.toml https://mainnet-data.supra.com/configs/smr_settings.toml
wget -O $SCRIPT_EXECUTION_LOCATION/genesis_configs.json https://mainnet-data.supra.com/configs/genesis_configs.json
wget -O $SCRIPT_EXECUTION_LOCATION/supra_committees.json https://mainnet-data.supra.com/configs/supra_committees.json
wget -O $SCRIPT_EXECUTION_LOCATION/genesis_config_arbitrary_data.json https://mainnet-data.supra.com/configs/genesis_config_arbitrary_data.json
# Run the Docker container
echo "Running new docker image"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

if !     docker run --name "supra_mainnet_$ip_address" \
        -v $SCRIPT_EXECUTION_LOCATION:/supra/configs \
        --user "$USER_ID:$GROUP_ID" \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=4000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd asia-docker.pkg.dev/supra-devnet-misc/supra-mainnet/validator-node:v7.1.7; then
    echo "Failed to run new Docker image. Exiting..."
    exit 1
fi
echo "New Docker image created"

# Update hash in hashmap_phase_1_previous.toml
new_sha=$(sha256sum $SCRIPT_EXECUTION_LOCATION/smr_settings.toml | awk '{print $1}')
if ! sed -i.bak "s|\(smr_settings.toml\s*=\s*\).*|\1\"$new_sha\"|" "$SCRIPT_EXECUTION_LOCATION/hashmap_phase_1_previous.toml"; then
    echo "Failed to update hashmap_phase_1_previous.toml. Exiting..."
    exit 1
fi
echo "Updated smr_settings.toml hash"

function parse_toml() {
    grep -w "$1" "$2" | cut -d'=' -f2- | tr -d ' "'
}


encoded_pswd=$(parse_toml "password" "$CONFIG_FILE")
password=$(echo "$encoded_pswd" | openssl base64 -d -A)

# Execute supra genesis sign-supra-committee with expect script for password input
    expect << EOF
spawn docker exec -it supra_mainnet_$ip_address /supra/supra genesis sign-supra-committee
expect "password:" { send "$password\r" }
expect eof
EOF
sleep 10
if ls "$SCRIPT_EXECUTION_LOCATION"/*.sig 1> /dev/null 2>&1; then
    echo "Signature has been generated and stored at $SCRIPT_EXECUTION_LOCATION with suffix .sig. Please push and create PR to supra-nodeops-data repository in the master branch."
else
    echo "Signature isn't present at $SCRIPT_EXECUTION_LOCATION with suffix .sig, Please re-run the script or connect with Supra Team to get support."
fi
