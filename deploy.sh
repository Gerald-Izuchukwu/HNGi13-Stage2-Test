#!/bin/bash

# ==============================================================================
# DEPLOY.SH - Single-file, executable script for parameter collection and validation.
#
# This script collects necessary parameters for a hypothetical deployment process,
# including Git, SSH, and port details, validating inputs and handling errors.
# ==============================================================================

# Strict mode: Exit immediately if a command exits with a non-zero status (-e).
# Treat unset variables as an error (-u).
# The return status of a pipeline is the status of the last command to exit with a non-zero status,
# or zero if all commands exit successfully (-o pipefail).
set -euo pipefail

# --- Configuration & Logging ---
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"

# Define global variables (will be populated by prompt_and_set)
GIT_REPO_URL=""
PAT=""
BRANCH_NAME=""
SSH_USER=""
SERVER_IP=""
SSH_KEY_PATH=""
APP_PORT=""
REPO_DIR="deployed_repo"  # Directory to clone the repository into

log_info() {
    # Print to console (stdout) and tee to log file
    echo -e "[\e[34mINFO\e[0m] $(date +'%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    # Print to console (stdout) and tee to log file
    echo -e "[\e[32mSUCCESS\e[0m] $(date +'%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    # Print to console (stderr) and exit with failure status (1)
    echo -e "[\e[31mERROR\e[0m] $(date +'%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE" >&2
    exit 1
}

# --- Validation Functions ---

# Basic check for IPv4 structure
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Check for a valid port number (1-65535)
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Simple validation for a URL starting with http, https, or git
# validate_url() {
#     local url=$1
#     if [[ $url =~ ^(https?|git)://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(/.*)?$ ]]; then
#         return 0
#     else
#         echo "not valid"
#         return 1
#     fi
# }

validate_url() {
    local url=$1
    case $url in
        http://*|https://*|git://*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# --- Parameter Collection Function ---

# Prompts the user for input, validates it, and sets the corresponding global variable.
prompt_and_set() {
    local prompt_msg=$1
    local validation_func=$2
    local error_msg=$3
    local var_name=$4
    local default_val=${5:-}

    while true; do
        # Append default to prompt if provided
        local full_prompt="$prompt_msg"
        if [[ -n "$default_val" ]]; then
            full_prompt+=" (Default: $default_val): "
        else
            full_prompt+=": "
        fi

        read -r -p "$full_prompt" input
        local value="$input"

        # Apply default if input is empty
        if [[ -z "$value" ]] && [[ -n "$default_val" ]]; then
            value="$default_val"
            log_info "Using default for $var_name: $value"
        fi

        # Check if input is empty (and no default was set)
        if [[ -z "$value" ]]; then
            log_error "Input is required for $var_name."
            continue
        fi

        # Perform custom validation
        if [[ -n "$validation_func" ]]; then
            if ! "$validation_func" "$value"; then
                log_error "$error_msg"
                continue
            fi
        fi

        # Specific file existence check for SSH key path
        if [[ "$var_name" == "SSH_KEY_PATH" ]]; then
            # Expand tilde (~) before checking
            value=$(eval echo "$value")
            if [[ ! -f "$value" ]]; then
                log_error "SSH Private Key file not found or is not a file at '$value'."
                continue
            fi
        fi

        # Set the global variable using eval (be cautious with eval, but safe here)
        eval "$var_name=\"$value\""
        break
    done
}

collect_parameters() {
    log_info "--- Starting Parameter Collection ---"

    # 1. Git Repository URL
    prompt_and_set "Enter Git Repository URL" \
        "validate_url" "Invalid Git URL format. Must start with http(s) or git." \
        "GIT_REPO_URL"

    # 2. Personal Access Token (PAT)
    prompt_and_set "Enter Personal Access Token (PAT)" \
        "" "PAT cannot be empty." \
        "PAT"

    # 3. Branch Name (Optional, defaults to 'main')
    prompt_and_set "Enter branch name" \
        "" "Branch name cannot be empty." \
        "BRANCH_NAME" "main"

    # 4. Remote Server SSH Username
    prompt_and_set "Enter Remote Server SSH Username" \
        "" "SSH Username cannot be empty." \
        "SSH_USER"

    # 5. Remote Server IP Address
    prompt_and_set "Enter Remote Server IP Address" \
        "validate_ip" "Invalid IP address format (e.g., 192.168.1.1)." \
        "SERVER_IP"

    # 6. SSH Key Path
    prompt_and_set "Enter Absolute Path to SSH Private Key (e.g., ~/.ssh/id_rsa)" \
        "" "SSH Key Path cannot be empty and file must exist." \
        "SSH_KEY_PATH"

    # 7. Application Port (Internal container port)
    prompt_and_set "Enter Application Internal Port" \
        "validate_port" "Invalid port number (must be 1-65535)." \
        "APP_PORT"

    log_success "--- Parameter Collection Complete ---"
}

# clone_repository() {
#     log_info "Cloning repository from $GIT_REPO_URL (branch: $BRANCH_NAME)..."
#     # Example command (commented out for safety)
#     git clone --branch "$BRANCH_NAME" "https://$PAT@${GIT_REPO_URL#https://}" repo_dir
#     log_success "Repository cloned successfully."
# }

clone_repository() {
    log_info "Preparing deployment directory: $REPO_DIR"

    # Construct the authenticated Git URL. We strip 'https://' from the start
    # of GIT_REPO_URL to correctly form the URL with PAT embedded.
    local AUTH_URL="https://$PAT@${GIT_REPO_URL#https://}"

    # Check if the repository directory already exists and contains a .git folder
    if [[ -d "$REPO_DIR/.git" ]]; then
        log_info "Repository directory '$REPO_DIR' already exists. Performing git pull..."
        
        # Navigate to the repository directory
        cd "$REPO_DIR" || log_error "Failed to enter repository directory $REPO_DIR."
        
        # Ensure we are on the correct branch and pull the latest changes
        log_info "Checking out branch $BRANCH_NAME..."
        git checkout "$BRANCH_NAME" || log_error "Failed to checkout branch $BRANCH_NAME."
        
        log_info "Pulling latest changes..."
        git pull origin "$BRANCH_NAME" || log_error "Failed to pull latest changes for branch $BRANCH_NAME."
        
        # Navigate back to the original script directory
        cd .. || log_error "Failed to navigate back from repository directory."

        log_success "Repository successfully updated via git pull."
    else
        log_info "Repository directory '$REPO_DIR' does not exist. Performing git clone..."
        
        # Clone the repository using the authenticated URL and specific branch
        git clone --branch "$BRANCH_NAME" "$AUTH_URL" "$REPO_DIR" || log_error "Failed to clone repository $GIT_REPO_URL."
        
        log_success "Repository successfully cloned into $REPO_DIR."
    fi
}

change_into_repo_dir() {
    cd "$REPO_DIR" || log_error "Failed to change directory to $REPO_DIR."
    # check to see if Dockerfile or docker-compose.yml exists
    if [[ ! -f "Dockerfile" && ! -f "docker-compose.yml" ]]; then
        log_error "No Dockerfile or docker-compose.yml found in $REPO_DIR."
    fi
}

# ssh_into_remote_server(){
#     log_info "Attempting to SSH into remote server $SSH_USER@$SERVER_IP..."
#     ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" || log_error "SSH connection to $SERVER_IP failed."
#     log_success "SSH connection established successfully."
# }

ssh_into_remote_server(){
    log_info "Attempting to SSH into remote server $SSH_USER@$SERVER_IP..."
    ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful.'" \
        && log_success "SSH connection to $SERVER_IP succeeded." \
        || log_error "SSH connection to $SERVER_IP failed."
}


preparing_remote_environment(){
    log_info "Preparing remote environment on $SERVER_IP..."
    #update package lists
    log_info "Updating package lists on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'sudo apt update -y' || log_error "Failed to update package lists on remote server."
    #install docker, docker-compose and nginx
    log_info "Installing required packages (Docker, Docker-Compose, Nginx) on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'sudo apt install -y docker.io docker-compose nginx' || log_error "Failed to install required packages on remote server."
    # add user to docker group
    log_info "Adding user $SSH_USER to docker group on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "sudo usermod -aG docker $SSH_USER" || log_error "Failed to add user to docker group"
    # enable and start services
    log_info "Enabling and starting Docker and Nginx services on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'sudo systemctl enable docker && sudo systemctl start docker' || log_error "Failed to enable/start Docker service on remote server."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'sudo systemctl enable nginx && sudo systemctl start nginx' || log_error "Failed to enable/start Nginx service on remote server."
    # confirm installations
    log_info "Verifying installations on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'docker --version' || log_error "Docker installation verification failed."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'docker-compose --version' || log_error "Docker-Compose installation verification failed."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'nginx -v' || log_error "Nginx installation verification failed."

    log_success "Remote environment prepared successfully."
}
deploy_dockerize_app(){
    log_info "Deploying Dockerized application on remote server..."
    # Placeholder for deployment commands
    #scp docker-compose.yml and Dockerfile to remote server
    log_info "Copying Docker configuration files to remote server..."
    scp -i "$SSH_KEY_PATH" docker-compose.yml "$SSH_USER@$SERVER_IP:~/docker-compose.yml" || log_error "Failed to copy docker-compose.yml to remote server."
    scp -i "$SSH_KEY_PATH" Dockerfile "$SSH_USER@$SERVER_IP:~/Dockerfile" || log_error "Failed to copy Dockerfile to remote server."
    #build image and run container
    log_info "Building Docker image and running container on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'docker build -t my_app_image . && docker run -d -p '"$APP_PORT"':80 my_app_image' || log_error "Failed to build and run Docker container on remote server."
    # or using docker-compose
    #ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'docker-compose up -d' || log_error "Failed to deploy application using docker-compose on remote server."
    # validdate deployment
    log_info "Validating deployment on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'docker ps' || log_error "Failed to verify running Docker containers on remote server."
    # validate contianer health and logs
    log_info "Checking Docker container logs on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'docker logs $(docker ps -q --filter ancestor=my_app_image)' || log_error "Failed to retrieve Docker container logs on remote server."
    # confirm application is accessible
    log_info "Checking application accessibility at http://$SERVER_IP:$APP_PORT..."
    curl -I "http://$SERVER_IP:$APP_PORT" || log_error "Failed to access the deployed application at http://$SERVER_IP:$APP_PORT."


    log_success "Dockerized application deployed successfully."
}

configuring_nginx_reverse_proxy(){
    log_info "Configuring Nginx as a reverse proxy on remote server..."
    # Placeholder for Nginx configuration commands
    # Create Nginx config file
    local NGINX_CONFIG="server {
        listen 80;
        server_name $SERVER_IP;

        location / {
            proxy_pass http://localhost:$APP_PORT;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }"

    # Upload Nginx config to remote server
    log_info "Uploading Nginx configuration to remote server..."
    echo "$NGINX_CONFIG" | ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'sudo tee /etc/nginx/sites-available/default' || log_error "Failed to upload Nginx configuration to remote server."

    # Test Nginx configuration
    log_info "Testing Nginx configuration on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'sudo nginx -t' || log_error "Nginx configuration test failed on remote server."

    # Reload Nginx to apply changes
    log_info "Reloading Nginx on remote server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'sudo systemctl reload nginx' || log_error "Failed to reload Nginx on remote server."

    log_success "Nginx configured successfully as a reverse proxy."
}
# --- Main Execution ---

main() {
    echo "====================================================="
    echo "             Deployment Script Initialized             "
    echo "====================================================="
    log_info "All logs are being recorded in: $LOG_FILE"

    # 1. Collect and Validate Parameters
    collect_parameters

    # 2. Display Collected Parameters for Verification
    log_info "Deployment Configuration Summary:"
    log_info "---------------------------------"
    log_info "Git Repository URL: $GIT_REPO_URL"
    log_info "Git Branch:         $BRANCH_NAME"
    log_info "PAT:                *********** (Hidden)"
    log_info "SSH User:           $SSH_USER"
    log_info "Server IP:          $SERVER_IP"
    log_info "SSH Key Path:       $SSH_KEY_PATH"
    log_info "App Internal Port:  $APP_PORT"
    log_info "---------------------------------"

    #cloning the repository
    log_info "--- Step 1: Local Git Operations (Simulating Remote Checkout) ---"
    clone_repository

    #  Navigate into the cloned repository directory
    log_info "Changing into repository directory: $REPO_DIR"
    change_into_repo_dir

    # 3. Placeholder for Deployment Steps (e.g., SSH, Build, Deploy)
    log_info "Starting Mock Deployment to Remote Server..."
    #ssh into remote server
    ssh_into_remote_server
    #prepare remote environment
    preparing_remote_environment
    # deploy dockerized app 
    deploy_dockerize_app

    # Example of a deployment step that would use the variables:
    # log_info "Attempting to copy key to agent and connecting to remote host..."
    # ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" 'mkdir -p /opt/app' || log_error "SSH connection or directory creation failed."

    log_success "Script finished parameter collection and validation successfully."
}

# Execute main function
main
