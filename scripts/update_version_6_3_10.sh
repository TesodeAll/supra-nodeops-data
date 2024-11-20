#!/bin/bash

SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_configs"
CONFIG_FILE="$(pwd)/operator_config.toml"

if ! command -v jq &>/dev/null; then
    echo "jq is not installed. Please install jq before proceeding."
    exit 1
fi
# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config.toml | awk -F'=' '{print $2}' | tr -d ' "')

display_questions() {
    echo "1. Upgrade Validator Node with latest version"
    echo "2. Restart & Sync Validator node with latest snapshot"
    echo "3. Exit"
}
start_stop_container(){
    # Stop the Docker container if it's running
    echo "Stopping Supra container"
    if ! docker stop supra_$ip_address; then
        echo "Failed to stop Supra container. Exiting..."
    else 
        echo "Stopped Supra container"
    fi

    echo "Starting Supra container"
    if ! docker start supra_$ip_address; then
        echo "failed to start supra container, Exiting..."
    else
        echo "Started Supra container"
    fi
}
binary_upgrade(){
    # Check if ip_address is set
    read -p "Enter old Supra Docker image: " OLD_VALIDATOR_IMAGE_NAME
    read -p "Enter new Supra Docker Image: " NEW_VALIDATOR_IMAGE_NAME 
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

    # Remove the Docker container
    echo "Removing supra container"
    if ! docker rm supra_$ip_address; then
        echo "Failed to remove supra container. Exiting..."
    fi
    echo "supra container removed"




    # Run the Docker container
    echo "Running new docker container with new image $NEW_VALIDATOR_IMAGE_NAME "
    USER_ID=$(id -u)
    GROUP_ID=$(id -g)

    if !  docker run --name "supra_$ip_address" \
        -v $SCRIPT_EXECUTION_LOCATION:/supra/configs \
        --user "$USER_ID:$GROUP_ID" \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=400000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd $NEW_VALIDATOR_IMAGE_NAME; then
        echo "Failed to run new Validator Node container $NEW_VALIDATOR_IMAGE_NAME image. Exiting..."
        exit 1
    fi
    echo "Validator Node container upgraded with $NEW_VALIDATOR_IMAGE_NAME"

    # Remove the old Docker image
    echo "Deleting old docker images"
    if ! docker rmi $OLD_VALIDATOR_IMAGE_NAME; then
        echo "Failed to delete old Docker image. Exiting..."
    fi
    echo "Deleted the old Docker images"
}



snapshot_sync(){

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


    # Set the maximum number of retries
    MAX_RETRIES=5
    RETRY_DELAY=10  # Delay in seconds before retrying
    retry_count=0

    # Create a log file for Rclone sync
    LOG_FILE="$SCRIPT_EXECUTION_LOCATION/rclone_sync.log"
    echo "Rclone sync process started at $(date)" | tee -a "$LOG_FILE"

    # Loop to retry the command if it fails
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Run the rclone sync command, output to the console and log simultaneously
        echo "Running rclone sync attempt $((retry_count + 1)) at $(date)" | tee -a "$LOG_FILE"
        rclone sync cloudflare-r2:testnet-snapshot/snapshots/store "$SCRIPT_EXECUTION_LOCATION/smr_storage/" --progress | tee -a "$LOG_FILE"

        # Check if the rclone command was successful
        if [ $? -eq 0 ]; then
            rclone sync cloudflare-r2:testnet-snapshot/snapshots/store "$SCRIPT_EXECUTION_LOCATION/smr_storage/" --progress | tee -a "$LOG_FILE"
            echo "rclone sync completed successfully at $(date)" | tee -a "$LOG_FILE"
            break
        else
            echo "rclone sync failed. Attempt $((retry_count + 1))/$MAX_RETRIES." | tee -a "$LOG_FILE"
            retry_count=$((retry_count + 1))
            sleep $RETRY_DELAY
        fi
    done

    # Log final status
    if [ $retry_count -ge $MAX_RETRIES ]; then
        echo "Rclone sync process failed after $MAX_RETRIES attempts at $(date)" | tee -a "$LOG_FILE"
    else
        echo "Rclone sync process completed successfully at $(date)" | tee -a "$LOG_FILE"
    fi
}
start_node(){
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

}

# Function to fetch and compare block heights with ±10 tolerance
compare_block_heights() {
    # Fetch block data from the API and store it in a variable
    api_result=$(curl -s -X 'GET' 'https://rpc-testnet.supra.com/rpc/v1/block' -H 'accept: application/json')
    
    # Extract block height from the API response (requires jq)
    api_block_height=$(echo "$api_result" | jq '.height')
    
    # Check the log file for the latest block height using regex to match the specific format
    LOG_FILE="$SCRIPT_EXECUTION_LOCATION/supra_node_logs/supra.log"
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Warn: Log file isn't present, Hence Starting the supra container with latest snapshot"
        snapshot_sync
        start_node
        return 1
    else
        log_block_height=$(grep -i "Block height" $LOG_FILE | tail -n 1 | sed -n 's/.*Block height: (\([0-9]*\)).*/\1/p')  
    fi
    # Ensure both heights are valid integers
    if [[ -z "$api_block_height" || -z "$log_block_height" ]]; then
        echo "Error: Could not retrieve block heights, Hence starting the supra container with latest snapshot"
        snapshot_sync
        start_node
        return 1
    fi

    # Calculate the absolute difference
    difference=$(( api_block_height - log_block_height ))
    difference=${difference#-}  # Convert to absolute value

    # Compare the difference to the tolerance of ±1200
    tolerance=1200
    if (( difference <= tolerance )); then
        echo "Block heights are within tolerance of ±$tolerance."
        echo "API Block Height: $api_block_height"
        echo "Log Block Height: $log_block_height"
        start_node
    else
        echo "Block heights are NOT within tolerance of ±$tolerance."
        echo "API Block Height: $api_block_height"
        echo "Log Block Height: $log_block_height"
        snapshot_sync
        start_node
    fi
}


while true; do

    echo ""
    display_questions
    echo ""
    read -p "Enter your choice: " choice
    case $choice in
        1)
            binary_upgrade
            compare_block_heights
            ;;
        2)
            start_stop_container
            compare_block_heights
            ;;
        3)
            echo "Exit the script"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 3."
            ;;
    esac
    echo ""
done