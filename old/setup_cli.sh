#!/bin/bash

# Function to prompt for input with a default value
prompt() {
    local var_name=$1
    local prompt_text=$2
    local default_value=$3
    read -p "$prompt_text [$default_value]: " input
    export $var_name="${input:-$default_value}"
}

# Function to prompt for yes/no with a default value
prompt_yes_no() {
    local var_name=$1
    local prompt_text=$2
    local default_value=$3
    read -p "$prompt_text (y/n) [$default_value]: " input
    case "${input:-$default_value}" in
        y|Y ) export $var_name="true";;
        n|N ) export $var_name="false";;
        * ) export $var_name=$default_value;;
    esac
}

# Prompt for variables
prompt NEW_USER "Enter the new username" "youruser"
prompt NEW_USER_PASSWORD "Enter the new user password" "your-secret-password"
prompt SSH_PUBLIC_KEY "Enter the SSH public key content" "your-public-key-content"
prompt_yes_no INSTALL_COOLIFY "Do you want to install Coolify?" "n"
prompt_yes_no AUTO_REBOOT "Enable automatic reboot for unattended upgrades?" "n"
prompt_yes_no REMOVE_UNUSED_DEPS "Remove unused dependencies during unattended upgrades?" "n"

# Update system
prompt_yes_no RUN_UPDATE "Do you want to update the system?" "y"
if [ "$RUN_UPDATE" = "true" ]; then
    apt update && apt upgrade -y
fi

# Install required packages
prompt_yes_no INSTALL_PACKAGES "Do you want to install required packages?" "y"
if [ "$INSTALL_PACKAGES" = "true" ]; then
    apt install -y sudo ufw fail2ban unattended-upgrades apt-listchanges
fi

# Configure unattended-upgrades
prompt_yes_no CONFIGURE_UNATTENDED_UPGRADES "Do you want to configure unattended-upgrades?" "y"
if [ "$CONFIGURE_UNATTENDED_UPGRADES" = "true" ]; then
    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=\${distro_codename},label=Debian-Security";
    "origin=Debian,codename=\${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "${REMOVE_UNUSED_DEPS}";
Unattended-Upgrade::Automatic-Reboot "${AUTO_REBOOT}";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
fi

# Create new user and add to sudo group
prompt_yes_no CREATE_USER "Do you want to create a new user?" "y"
if [ "$CREATE_USER" = "true" ]; then
    useradd -m -s /bin/bash $NEW_USER
    echo "$NEW_USER:$NEW_USER_PASSWORD" | chpasswd
    usermod -aG sudo $NEW_USER

    # Setup SSH key for new user
    mkdir -p /home/$NEW_USER/.ssh
    echo "$SSH_PUBLIC_KEY" > /home/$NEW_USER/.ssh/authorized_keys
    chmod 700 /home/$NEW_USER/.ssh
    chmod 600 /home/$NEW_USER/.ssh/authorized_keys
    chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
fi

# Configure SSH
prompt_yes_no CONFIGURE_SSH "Do you want to configure SSH?" "y"
if [ "$CONFIGURE_SSH" = "true" ]; then
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
fi

# Configure fail2ban
prompt_yes_no CONFIGURE_FAIL2BAN "Do you want to configure fail2ban?" "y"
if [ "$CONFIGURE_FAIL2BAN" = "true" ]; then
    cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
fi

# Configure firewall
prompt_yes_no CONFIGURE_UFW "Do you want to configure the firewall?" "y"
if [ "$CONFIGURE_UFW" = "true" ]; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    echo "y" | ufw enable
fi

# Install Docker
prompt_yes_no INSTALL_DOCKER "Do you want to install Docker?" "y"
if [ "$INSTALL_DOCKER" = "true" ]; then
    apt install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add user to docker group
    usermod -aG docker $NEW_USER
fi

# Optionally install and configure Coolify
if [ "${INSTALL_COOLIFY}" = "true" ]; then

    echo "Installing Coolify..."

    # Temporary Coolify ports
    echo "⚠️ Adding temporary Coolify ports. Remember to remove them after configuring your domain!"
    ufw allow 8000/tcp comment 'Temporary Coolify Web UI'
    ufw allow 6001/tcp comment 'Temporary Coolify Websocket'
    ufw allow 6002/tcp comment 'Temporary Coolify API'


    mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance}
    mkdir -p /data/coolify/ssh/{keys,mux}
    mkdir -p /data/coolify/proxy/dynamic

    ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify

    cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >>~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys

    curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.yml -o /data/coolify/source/docker-compose.yml
    curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml
    curl -fsSL https://cdn.coollabs.io/coolify/.env.production -o /data/coolify/source/.env
    curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh -o /data/coolify/source/upgrade.sh

    chown -R 9999:root /data/coolify
    chmod -R 700 /data/coolify

    sed -i "s|APP_ID=.*|APP_ID=$(openssl rand -hex 16)|g" /data/coolify/source/.env
    sed -i "s|APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|g" /data/coolify/source/.env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
    sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
    sed -i "s|PUSHER_APP_ID=.*|PUSHER_APP_ID=$(openssl rand -hex 32)|g" /data/coolify/source/.env
    sed -i "s|PUSHER_APP_KEY=.*|PUSHER_APP_KEY=$(openssl rand -hex 32)|g" /data/coolify/source/.env
    sed -i "s|PUSHER_APP_SECRET=.*|PUSHER_APP_SECRET=$(openssl rand -hex 32)|g" /data/coolify/source/.env

    docker network create --attachable coolify

    docker compose --env-file /data/coolify/source/.env -f /data/coolify/source/docker-compose.yml -f /data/coolify/source/docker-compose.prod.yml up -d --pull always --remove-orphans --force-recreate

    echo "⚠️ After configuring your domain in Coolify, remove temporary ports:"
    echo "ssh $VPS_USER@$VPS_HOST 'sudo ufw delete allow 8000/tcp && sudo ufw delete allow 6001/tcp && sudo ufw delete allow 6002/tcp'"
fi

# Restart services
prompt_yes_no RESTART_SERVICES "Do you want to restart services?" "y"
if [ "$RESTART_SERVICES" = "true" ]; then
    systemctl restart sshd
    systemctl restart fail2ban
fi

# Print access information
echo "=== IMPORTANT: SAVE THIS INFORMATION ==="
echo "New user: $NEW_USER"
echo "Password: $NEW_USER_PASSWORD"
echo ""
echo "Test SSH access with: ssh $NEW_USER@<your-vps-ip>"
echo ""
echo "After confirming SSH key access works, run:"
echo "ssh $NEW_USER@<your-vps-ip> 'sudo sed -i \"s/PasswordAuthentication yes/PasswordAuthentication no/\" /etc/ssh/sshd_config && sudo systemctl restart sshd'"
echo ""
if [ "${INSTALL_COOLIFY}" = "true" ]; then
    echo "⚠️ After configuring your domain in Coolify, remove temporary ports:"
    echo "ssh $NEW_USER@<your-vps-ip> 'sudo ufw delete allow 8000/tcp && sudo ufw delete allow 6001/tcp && sudo ufw delete allow 6002/tcp'"
fi
echo ""
echo "==================================="
echo "Setup completed! "
