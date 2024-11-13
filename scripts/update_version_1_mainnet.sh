#!/bin/bash

SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_configs_mainnet"

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config_mainnet.toml | awk -F'=' '{print $2}' | tr -d ' "')

echo "Remove old supra onboarding script"
rm  "$(pwd)/onboarding_mainnet.sh"

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi
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
echo "Deleting old docker images"
if ! docker rmi asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/validator-node:v7.0.0; then
    echo "Failed to delete old Docker image. Exiting..."
fi
echo "Deleted the old Docker images"
# Run the Docker container
echo "Running new docker image"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

if !     docker run --name "supra_mainnet_$ip_address" \
        -v $SCRIPT_EXECUTION_LOCATION:/supra/configs \
        --user "$USER_ID:$GROUP_ID" \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=500000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd asia-docker.pkg.dev/supra-devnet-misc/supra-mainnet/validator-node:v7.1.2; then
    echo "Failed to run new Docker image. Exiting..."
    exit 1
fi
echo "New Docker image created"

wget -O "$(pwd)/onboarding_mainnet.sh" https://raw.githubusercontent.com/Entropy-Foundation/supra-nodeops-data/refs/heads/master/scripts/onboarding_mainnet.sh
chmod +x "$(pwd)/onboarding_mainnet.sh"