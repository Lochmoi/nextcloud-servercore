#!/bin/bash
# SCRIPT: install-docker.sh
# PURPOSE: Enhanced Docker installation with system security hardening
# AUTHOR: Lochmoi
# VERSION: 2.0
#
# DESCRIPTION:
# Installs Docker, Docker Compose, and implements system-level security.
#
# EXECUTION ORDER: 1/3
# - [1] install-docker.sh     <- 1/3
# - [2] servercore-setup.sh   <- 2/3
# - [3] deploy-nextcloud.sh   <- 3/3

set -e

echo "=============================================="
echo "  SCRIPT 1/3: ENHANCED DOCKER INSTALLATION"
echo "  With System Security Hardening"

# Configuration
SSH_PORT="7392"
PROJECT_USER="ubuntu"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)" 
   exit 1
fi

echo "Starting enhanced Docker installation with security..."

# STEP 1: SYSTEM UPDATE AND SECURITY TOOLS

echo "Step 1: System update and security tools installation..."

# Update system
apt-get update && apt-get upgrade -y

# Install essential packages and security tools
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg \
    lsb-release \
    fail2ban \
    ufw \
    openssl \
    htop \
    unattended-upgrades \
    logrotate \
    rsyslog

# Configure automatic security updates
echo "Configuring automatic security updates..."
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
echo 'Unattended-Upgrade::Remove-Unused-Dependencies "true";' >> /etc/apt/apt.conf.d/50unattended-upgrades

echo "SUCCESS: System updated and security tools installed"

# =================================================================
# STEP 2: SSH SECURITY HARDENING
# =================================================================

echo "Step 2: SSH security hardening..."

# Backup original SSH config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup-$(date +%Y%m%d)

# Create secure SSH configuration
cat > /etc/ssh/sshd_config << EOF
# Enhanced SSH Security Configuration
Port $SSH_PORT
Protocol 2
AddressFamily inet

# Authentication
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
MaxAuthTries 2
LoginGraceTime 30

# User restrictions
AllowUsers $PROJECT_USER
DenyUsers root

# Session settings
ClientAliveInterval 300
ClientAliveCountMax 1
TCPKeepAlive yes

# Security options
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
GatewayPorts no
PermitTunnel no
PermitUserEnvironment no

# Disable unused authentication methods
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
UsePAM yes

# Logging
SyslogFacility AUTH
LogLevel INFO
EOF

# Test SSH configuration
sshd -t

echo "SUCCESS: SSH hardened on port $SSH_PORT"
echo "IMPORTANT: Copy your SSH public key before restarting SSH!"

# =================================================================
# STEP 3: FIREWALL CONFIGURATION
# =================================================================

echo "Step 3: UFW firewall configuration..."

# Reset UFW to clean state
ufw --force reset

# Set default policies
ufw default deny incoming
ufw default allow outgoing

# Allow essential services
ufw allow $SSH_PORT/tcp comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

# Enable firewall
ufw --force enable

echo "SUCCESS: UFW firewall configured and enabled"

# =================================================================
# STEP 4: FAIL2BAN CONFIGURATION
# =================================================================

echo "Step 4: Fail2Ban configuration..."

# Create enhanced fail2ban configuration
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = -1     # Default
findtime = 600      # 10 minutes
maxretry = 2
backend = systemd
banaction = iptables-multiport
protocol = tcp
chain = INPUT
action = %(action_)s

# SSH Protection
[sshd]
enabled = true
port = $SSH_PORT
logpath = %(sshd_log)s
maxretry = 2
bantime = 604800    # 7 days for SSH attempts

# Nginx Protection (will be active after NextCloud deployment)
[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /home/$PROJECT_USER/nextcloud-servercore/docker/logs/nginx/error.log
maxretry = 3
bantime = 86400

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /home/$PROJECT_USER/nextcloud-servercore/docker/logs/nginx/error.log
maxretry = 5
bantime = 86400

# NextCloud specific protection
[nextcloud-auth]
enabled = true
filter = nextcloud-auth
logpath = /home/$PROJECT_USER/nextcloud-servercore/docker/logs/nginx/access.log
maxretry = 2
bantime = 86400
findtime = 600
EOF

# Create NextCloud fail2ban filter
cat > /etc/fail2ban/filter.d/nextcloud-auth.conf << EOF
[Definition]
failregex = ^<HOST> .* "POST /index\.php/login HTTP/.*" 401
            ^<HOST> .* "POST /remote\.php/webdav/ HTTP/.*" 401
            ^<HOST> .* "POST /apps/.*login.* HTTP/.*" 401

ignoreregex = 
EOF

# Enable and start fail2ban
systemctl enable fail2ban
systemctl start fail2ban

echo "SUCCESS: Fail2Ban configured and started"

# =================================================================
# STEP 5: DOCKER INSTALLATION
# =================================================================

echo "Step 5: Docker installation..."

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "SUCCESS: Docker packages installed"

# =================================================================
# STEP 6: DOCKER SECURITY CONFIGURATION
# =================================================================

echo "Step 6: Docker security configuration..."

# Create secure Docker daemon configuration
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "icc": false,
  "userland-proxy": false,
  "no-new-privileges": true,
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Hard": 64000,
      "Name": "nofile",
      "Soft": 64000
    }
  }
}
EOF

# Add user to docker group
usermod -aG docker $PROJECT_USER

# Enable and restart Docker with new configuration
systemctl enable docker
systemctl restart docker

echo "SUCCESS: Docker configured with security settings"

# =================================================================
# STEP 7: CREATE PROJECT DIRECTORY
# =================================================================

echo "Step 7: Creating project directory structure..."

# Create project directory structure
sudo -u $PROJECT_USER mkdir -p /home/$PROJECT_USER/nextcloud-servercore

echo "SUCCESS: Project directory created"

# =================================================================
# STEP 8: VERIFY INSTALLATION
# =================================================================

echo "Step 8: Verifying installation..."

# Verify Docker installation
docker --version
docker compose version

# Check security services
systemctl status fail2ban --no-pager -l
ufw status

echo "SUCCESS: Installation verification completed"

# =================================================================
# FINAL SUMMARY
# =================================================================

echo ""
echo "ENHANCED DOCKER INSTALLATION COMPLETED!"
echo ""
echo "=============================================="
echo "  SCRIPT 1/3 COMPLETED: DOCKER + SECURITY"
echo "=============================================="
echo ""
echo "Installed and Configured:"
echo "   - Docker Engine with security settings"
echo "   - Docker Compose plugin"
echo "   - UFW Firewall (ports 7392, 80, 443 allowed)"
echo "   - Fail2Ban (SSH and web protection)"
echo "   - SSH hardened on port $SSH_PORT"
echo "   - Automatic security updates"
echo ""
echo "CRITICAL NEXT STEPS:"
echo "1. Generate NEW SSH keys on your local machine:"
echo "   ssh-keygen -t ed25519 -C 'lochmoimicah@gmail.com'"
echo ""
echo "2. Copy public key to server:"
echo "   ssh-copy-id -p $SSH_PORT $PROJECT_USER@45.150.188.27"
echo ""
echo "3. Test new SSH connection:"
echo "   ssh -p $SSH_PORT $PROJECT_USER@45.150.188.27"
echo ""
echo "4. Restart SSH service:"
echo "   sudo systemctl restart sshd"
echo ""
echo "5. Log out and log back in for docker group changes"
echo ""
echo "=============================================="
echo "  EXECUTION ORDER"
echo "=============================================="
echo "✅ [1] install-docker.sh     <- COMPLETED"
echo "⏳ [2] servercore-setup.sh   <- RUN THIS NEXT"  
echo "⏳ [3] deploy-nextcloud.sh   <- RUN THIS LAST"
echo ""
echo "WARNING: SSH is now on port $SSH_PORT with key-only auth!"
echo "Make sure you can connect before closing this session!"