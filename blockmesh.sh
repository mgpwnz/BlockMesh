#!/bin/bash

# Default variables
function="install"
version=""

# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }

while test $# -gt 0; do
    case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -up|--update)
            function="update"
            shift
            if [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                version="$1"
                shift
            fi
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
        *|--)
            break
            ;;
    esac
done

# Function to check for empty variables
check_empty() {
    local varname=$1
    while [ -z "${!varname}" ]; do
        read -p "$2" input
        if [ -n "$input" ]; then
            eval $varname=\"$input\"
        else
            echo "The value cannot be empty. Please try again."
        fi
    done
}

# Function to confirm input
confirm_input() {
    echo "You have entered the following information:"
    echo "Email: $MAIL"
    echo "Password: $PASS"
    
    read -p "Is this information correct? (yes/no): " CONFIRM
    CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
    
    if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
        echo "Let's try again..."
        return 1 
    fi
    return 0 
}

install() {
    sudo apt update && sudo apt upgrade -y
    if [ -d "$HOME/blockmesh" ]; then
        echo "Directory $HOME/blockmesh already exists. Skipping installation."
        return 0
    else
        # Collect user data
        while true; do
            MAIL=""
            PASS=""

            check_empty MAIL "Enter email: "
            check_empty PASS "Enter password: "
            
            confirm_input
            if [ $? -eq 0 ]; then
                break 
            fi
        done

        echo "All data is confirmed. Proceeding..."
        blockmesh_version=$(wget -qO- https://api.github.com/repos/block-mesh/block-mesh-monorepo/releases/latest | jq -r ".tag_name")
        wget -qO "$HOME/blockmesh.tar.gz" "https://github.com/block-mesh/block-mesh-monorepo/releases/download/${blockmesh_version}/blockmesh-cli-x86_64-unknown-linux-gnu.tar.gz"
        
        if [ "$(wc -c < "$HOME/blockmesh.tar.gz")" -ge 1000 ]; then
            tar -xvf "$HOME/blockmesh.tar.gz" -C "$HOME"
            rm -rf "$HOME/blockmesh.tar.gz"

            # Rename the extracted directory
            mv "$HOME/target/x86_64-unknown-linux-gnu/release/" "$HOME/blockmesh/"
            chmod +x "$HOME/blockmesh/blockmesh-cli"

            # Create the systemd service file
            sudo tee /etc/systemd/system/blockmesh.service > /dev/null <<EOF
[Unit]
Description=Blockmesh Node
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/blockmesh/
ExecStart=$HOME/blockmesh/blockmesh-cli --email $MAIL --password $PASS
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

            sudo systemctl enable blockmesh.service
            sudo systemctl daemon-reload
            sudo systemctl start blockmesh.service
        else
            rm -rf "$HOME/blockmesh.tar.gz"
            echo "Archive is not downloaded or too small!"
            return 1
        fi
    fi
}

update() {
    sudo apt update && sudo apt upgrade -y

    if [ -d "$HOME/blockmesh" ]; then
        echo "Directory $HOME/blockmesh exists. Checking for updates..."
        if [ -z "$version" ]; then
            # Get the latest version if not specified
            blockmesh_version=$(wget -qO- https://api.github.com/repos/block-mesh/block-mesh-monorepo/releases/latest | jq -r ".tag_name")
        else
            blockmesh_version="$version"
        fi

        wget -qO "$HOME/blockmesh.tar.gz" "https://github.com/block-mesh/block-mesh-monorepo/releases/download/${blockmesh_version}/blockmesh-cli-x86_64-unknown-linux-gnu.tar.gz"
        
        if [ "$(wc -c < "$HOME/blockmesh.tar.gz")" -ge 1000 ]; then
            tar -xvf "$HOME/blockmesh.tar.gz" -C "$HOME"
            rm -rf "$HOME/blockmesh.tar.gz"
            # Delete old version
            rm -rf "$HOME/blockmesh"
            mv "$HOME/target/x86_64-unknown-linux-gnu/release/" "$HOME/blockmesh/"
            chmod +x "$HOME/blockmesh/blockmesh-cli"

            # Restart the service
            if sudo systemctl restart blockmesh.service; then
                echo "Blockmesh updated successfully to version ${blockmesh_version}."
            else
                echo "Failed to restart the blockmesh service."
                return 1
            fi
        else
            echo "Failed to download or archive is too small. No update applied."
            rm -rf "$HOME/blockmesh.tar.gz"
            return 1
        fi
    else
        echo "Directory $HOME/blockmesh does not exist. Installing..."
        install
    fi
}

uninstall() {
    if [ ! -d "$HOME/blockmesh" ]; then
        echo "Directory $HOME/blockmesh does not exist. Nothing to uninstall."
        return 0
    fi

    read -r -p "Wipe all DATA? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            sudo systemctl stop blockmesh.service  
            sudo systemctl disable blockmesh.service
            sudo systemctl daemon-reload

            # Remove blockmesh directory and service file
            rm -rf "$HOME/blockmesh"
            sudo rm -f /etc/systemd/system/blockmesh.service

            echo "Blockmesh successfully uninstalled and data wiped."
            ;;
        *)
            echo "Canceled"
            return 0
            ;;
    esac
}

# Install necessary packages and execute the function
sudo apt install wget jq -y &>/dev/null
cd
$function
