# Secure VPS Setup Automation

This repository contains automation scripts to set up a secure Debian-based VPS with essential security features and Docker installation. The setup is completely automated using GitHub Actions and can be easily forked and customized for your own use.

## 🔑 Features

- **User Management**
  - Creates a non-root user with sudo privileges
  - Configures SSH key-based authentication
  - Disables root login and password authentication

- **Security**
  - Sets up UFW firewall (allows only SSH, HTTP, HTTPS)
  - Installs and configures fail2ban to prevent brute-force attacks
  - Configures unattended-upgrades for automatic security updates
  - Implements secure SSH configuration

- **Docker**
  - Installs Docker and Docker Compose
  - Adds user to docker group

- **System Updates**
  - Configures automatic security updates
  - Sets up unattended-upgrades with email notifications
  - Automatic system cleanup

## 🚀 Usage

### 1. Fork this Repository
First, fork this repository and make it private to safely store your configurations.

### 2. Configure GitHub Secrets
In your forked repository, go to Settings > Secrets and variables > Actions and add the following secrets:

- `VPS_HOST`: Your VPS IP address
- `VPS_ROOT_PASSWORD`: Initial root password
- `VPS_USER`: Desired username for the non-root user
- `SSH_PUBLIC_KEY`: Your SSH public key content (from `~/.ssh/id_rsa.pub`)

### 3. Deploy
The setup will automatically deploy when you push to the main branch, or you can manually trigger it from the Actions tab.

## 📋 What Gets Installed

- UFW (Uncomplicated Firewall)
- fail2ban
- unattended-upgrades
- Docker & Docker Compose
- Essential system utilities

## ⚙️ Configuration Details

### Firewall Rules
- Default: deny incoming, allow outgoing
- Allowed incoming ports:
  - 22 (SSH)
  - 80 (HTTP)
  - 443 (HTTPS)

### fail2ban Configuration
- Monitors SSH authentication
- Bans IP after 3 failed attempts
- Ban duration: 1 hour
- Monitor window: 10 minutes

### Automatic Updates
- Daily security updates
- Automatic removal of unused packages
- Configured reboot at 2 AM if necessary
- Email notifications for important updates

### SSH Security
- Key-based authentication only
- Root login disabled
- Password authentication disabled

## 🛠️ Customization

1. Fork this repository
2. Modify `setup.sh` according to your needs
3. Update the GitHub Actions workflow in `.github/workflows/deploy.yml` if necessary
4. Set up your secrets
5. Deploy!

## 📈 Security Recommendations

- Always keep your SSH private key secure
- Regularly update your SSH keys
- Monitor system logs regularly
- Keep Docker and system packages updated
- Review automatic update logs periodically

## 🔍 Monitoring

After deployment, you can monitor various aspects:

- Fail2ban logs: `/var/log/fail2ban.log`
- UFW logs: `/var/log/ufw.log`
- Unattended upgrades: `/var/log/unattended-upgrades/`
- System logs: `/var/log/syslog`

## ⚠️ Important Notes

- This script is designed for Debian-based systems (tested on Debian 12)
- Ensure you have root access to your VPS before running
- Make sure to test the setup in a development environment first
- Keep your forked repository private to protect sensitive information
- Regularly update your SSH keys and monitor system logs

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⭐ Support

If you find this useful, please give it a star!

## 🔐 Security

If you discover any security issues, please send an email to [your-email] instead of using the issue tracker.
