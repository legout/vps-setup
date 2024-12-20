#!/bin/bash

# Helper function for yes/no prompts
confirm() {
    while true; do
        read -p "$1 [y/N] " yn
        case $yn in
            [Yy]* ) echo "yes"; return 0;;
            [Nn]* | "" ) echo "no"; return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Helper function for required input
prompt_required() {
    local value=""
    while [ -z "$value" ]; do
        read -p "$1: " value
        if [ -z "$value" ]; then
            echo "This field is required."
        fi
    done
    echo "$value"
}

# Helper function for optional input with default
prompt_with_default() {
    local default=$2
    read -p "$1 [$default]: " value
    echo "${value:-$default}"
}

echo "=== VPS Setup Interactive Configuration ==="
echo

# Gather basic information
NEW_USER=$(prompt_required "Enter new username")
NEW_USER_PASSWORD=$(prompt_required "Enter password for new user")
SSH_PUBLIC_KEY=$(prompt_required "Enter your SSH public key (content of id_rsa.pub)")

# Configuration options
echo
echo "=== Configuration Options ==="
AUTO_UPDATE=$(confirm "Enable automatic system updates?")
AUTO_REBOOT=$(confirm "Enable automatic system reboots?")
REMOVE_UNUSED_DEPS=$(confirm "Remove unused dependencies?")
INSTALL_DOCKER=$(confirm "Install Docker?")
INSTALL_COOLIFY=$(confirm "Install Coolify?")

# Security configuration
echo
echo "=== Security Configuration ==="
SETUP_UFW=$(confirm "Configure UFW firewall?")
SETUP_FAIL2BAN=$(confirm "Configure fail2ban?")

# Confirmation
echo
echo "=== Configuration Summary ==="
echo "New User: $NEW_USER"
echo "Auto Updates: $AUTO_UPDATE"
echo "Auto Reboot: $AUTO_REBOOT"
echo "Remove Unused Deps: $REMOVE_UNUSED_DEPS"
echo "Install Docker: $INSTALL_DOCKER"
echo "Install Coolify: $INSTALL_COOLIFY"
echo "Setup UFW: $SETUP_UFW"
echo "Setup fail2ban: $SETUP_FAIL2BAN"
echo

if ! confirm "Proceed with installation?"; then
    echo "Setup cancelled."
    exit 1
fi

# Update system
echo "Updating system..."
apt update && apt upgrade -y

# Install required packages
apt install -y sudo

if [ "$AUTO_UPDATE" = "yes" ]; then
    echo "Configuring automatic updates..."
    apt install -y unattended-upgrades apt-listchanges

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

# Create new user
echo "Creating new user..."
useradd -m -s /bin/bash $NEW_USER
echo "$NEW_USER:$NEW_USER_PASSWORD" | chpasswd
usermod -aG sudo $NEW_USER

# Setup SSH
echo "Configuring SSH..."
mkdir -p /home/$NEW_USER/.ssh
echo "$SSH_PUBLIC_KEY" > /home/$NEW_USER/.ssh/authorized_keys
chmod 700 /home/$NEW_USER/.ssh
chmod 600 /home/$NEW_USER/.ssh/authorized_keys
chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh

sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

if [ "$SETUP_FAIL2BAN" = "yes" ]; then
    echo "Configuring fail2ban..."
    apt install -y fail2ban
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

if [ "$SETUP_UFW" = "yes" ]; then
    echo "Configuring UFW..."
    apt install -y ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    echo "y" | ufw enable
fi

if [ "$INSTALL_DOCKER" = "yes" ]; then
    echo "Installing Docker..."
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
    usermod -aG docker $NEW_USER
fi

if [ "$INSTALL_COOLIFY" = "yes" ]; then
    echo "Installing Coolify..."
    
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
fi

# Restart services
systemctl restart sshd
[ "$SETUP_FAIL2BAN" = "yes" ] && systemctl restart fail2ban

# Print access information
echo
echo "=== IMPORTANT: SAVE THIS INFORMATION ==="
echo "New user: $NEW_USER"
echo "Password: $NEW_USER_PASSWORD"
echo
echo "Test SSH access with: ssh $NEW_USER@<your-vps-ip>"
echo
echo "After confirming SSH key access works, run:"
echo "ssh $NEW_USER@<your-vps-ip> 'sudo sed -i \"s/PasswordAuthentication yes/PasswordAuthentication no/\" /etc/ssh/sshd_config && sudo systemctl restart sshd'"
echo
if [ "$INSTALL_COOLIFY" = "yes" ]; then
    echo "⚠️ After configuring your domain in Coolify, remove temporary ports:"
    echo "ssh $NEW_USER@<your-vps-ip> 'sudo ufw delete allow 8000/tcp && sudo ufw delete allow 6001/tcp && sudo ufw delete allow 6002/tcp'"
fi
echo
echo "==================================="
echo "Setup completed!"
