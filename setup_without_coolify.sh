#!/bin/bash

# Variables
NEW_USER="youruser"
NEW_USER_PASSWORD="your-secret-password"
SSH_PUBLIC_KEY="your-public-key-content"

# Update system
apt update && apt upgrade -y

# Install required packages
apt install -y sudo ufw fail2ban unattended-upgrades apt-listchanges

# Configure unattended-upgrades
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
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

# Enable unattended-upgrades
systemctl enable unattended-upgrades
systemctl start unattended-upgrades

# Create new user and add to sudo group
useradd -m -s /bin/bash $NEW_USER
echo "$NEW_USER:$NEW_USER_PASSWORD" | chpasswd
usermod -aG sudo $NEW_USER

# Setup SSH key for new user
mkdir -p /home/$NEW_USER/.ssh
echo "$SSH_PUBLIC_KEY" > /home/$NEW_USER/.ssh/authorized_keys
chmod 700 /home/$NEW_USER/.ssh
chmod 600 /home/$NEW_USER/.ssh/authorized_keys
chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh

# Configure SSH
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Configure fail2ban
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

# Configure firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
echo "y" | ufw enable

# Install Docker
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

# Restart services
systemctl restart sshd
systemctl restart fail2ban

# Print access information
echo "=== IMPORTANT: SAVE THIS INFORMATION ==="
echo "New user: $NEW_USER"
echo "Password: $NEW_USER_PASSWORD"
echo ""
echo "Test SSH access with: ssh $NEW_USER@<your-vps-ip>"
echo ""
echo "After confirming SSH key access works, run:"
echo "ssh $NEW_USER@<your-vps-ip> 'sudo sed -i \"s/PasswordAuthentication yes/PasswordAuthentication no/\" /etc/ssh/sshd_config && sudo systemctl restart sshd'"
echo "==================================="

echo "Setup completed!"
