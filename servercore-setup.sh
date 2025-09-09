#!/bin/bash
#===============================================================================
# SCRIPT: servercore-setup.sh
# PURPOSE: Enhanced NextCloud setup with security configurations
# AUTHOR: Lochmoi
# VERSION: 2.0
#
# DESCRIPTION:
# Creates project structure, Docker configurations, and security settings.

# EXECUTION ORDER: 2/3  
# - [1] install-docker.sh     <- 1/3
# - [2] servercore-setup.sh   <- HERE
# - [3] deploy-nextcloud.sh   <- 3/3
#===============================================================================

set -e

echo "=============================================="
echo "  SCRIPT 2/3: ENHANCED NEXTCLOUD SETUP"
echo "  With Security and OnlyOffice Integration"

# Configuration
PROJECT_NAME="nextcloud-servercore"

# Determine user
if [[ $EUID -eq 0 ]]; then
    SYSTEM_USER="root"
    USER_HOME="/root"
else
    SYSTEM_USER="${USER}"
    USER_HOME=$(eval echo "~${SYSTEM_USER}")
fi

DOCKER_DIR="${USER_HOME}/${PROJECT_NAME}/docker"


echo "Configuration:"
echo "   User: $SYSTEM_USER"
echo "   Home: $USER_HOME"
echo "   Docker directory: $DOCKER_DIR"

# =================================================================
# STEP 1: CREATE ENHANCED DIRECTORY STRUCTURE
# =================================================================

echo "Step 1: Creating enhanced directory structure..."

# Create comprehensive directory structure
mkdir -p "$DOCKER_DIR"
mkdir -p "$DOCKER_DIR/data"/{nextcloud,mariadb,redis,onlyoffice}
mkdir -p "$DOCKER_DIR/nginx/ssl"
mkdir -p "$DOCKER_DIR/logs/nginx"
mkdir -p "$DOCKER_DIR/config/onlyoffice"
mkdir -p "$DOCKER_DIR/backups"
mkdir -p "$DOCKER_DIR/scripts"

# Set proper ownership
if [ "$SYSTEM_USER" != "root" ]; then
    sudo chown -R $SYSTEM_USER:$SYSTEM_USER "$USER_HOME/$PROJECT_NAME"
fi

echo "SUCCESS: Directory structure created"

# =================================================================
# STEP 2: GENERATE SECURE CREDENTIALS
# =================================================================

echo "Step 2: Generating secure credentials..."

# Generate strong, unique passwords
MARIADB_ROOT_PASSWORD=$(openssl rand -base64 32)
MARIADB_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 16)
REDIS_PASSWORD=$(openssl rand -base64 24)
ONLYOFFICE_JWT_SECRET=$(openssl rand -base64 32)

echo "SUCCESS: Secure credentials generated"

# =================================================================
# STEP 3: CREATE ENVIRONMENT CONFIGURATION
# =================================================================

echo "Step 3: Creating environment configuration..."

# Create comprehensive .env file
cat > "$DOCKER_DIR/.env" << EOF
# NextCloud Configuration
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
NEXTCLOUD_TRUSTED_DOMAINS=workspace.reelanalytics.net

# MariaDB Configuration  
MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD
MARIADB_PASSWORD=$MARIADB_PASSWORD
MARIADB_DATABASE=nextcloud
MARIADB_USER=nextcloud

# Redis Configuration
REDIS_PASSWORD=$REDIS_PASSWORD

# OnlyOffice Configuration
ONLYOFFICE_JWT_SECRET=$ONLYOFFICE_JWT_SECRET

# Network Configuration
COMPOSE_PROJECT_NAME=$PROJECT_NAME

# Security Configuration
TZ=UTC
EOF

# Secure the .env file
chmod 600 "$DOCKER_DIR/.env"

echo "SUCCESS: Environment configuration created and secured"

# =================================================================
# STEP 4: CREATE ENHANCED DOCKER COMPOSE
# =================================================================

echo "Step 4: Creating enhanced Docker Compose configuration..."

# Create Docker Compose with security enhancements and MariaDB
cat > "$DOCKER_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  mariadb:
    image: mariadb:10.11
    container_name: nextcloud-mariadb
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${MARIADB_ROOT_PASSWORD}
      MARIADB_PASSWORD: ${MARIADB_PASSWORD}
      MARIADB_DATABASE: ${MARIADB_DATABASE}
      MARIADB_USER: ${MARIADB_USER}
      TZ: ${TZ}
    volumes:
      - ./data/mariadb:/var/lib/mysql
    networks:
      - nextcloud-network
    command: --innodb-buffer-pool-size=512M --transaction-isolation=READ-COMMITTED --binlog-format=ROW --innodb-file-per-table=1 --skip-innodb-read-only-compressed
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 30s
      timeout: 10s
      retries: 3

  redis:
    image: redis:7-alpine
    container_name: nextcloud-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - ./data/redis:/data
    networks:
      - nextcloud-network
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 30s
      timeout: 5s
      retries: 3

  nextcloud-app:
    image: nextcloud:latest
    container_name: nextcloud-app
    restart: unless-stopped
    environment:
      MYSQL_HOST: mariadb
      MYSQL_DATABASE: ${MARIADB_DATABASE}
      MYSQL_USER: ${MARIADB_USER}
      MYSQL_PASSWORD: ${MARIADB_PASSWORD}
      NEXTCLOUD_ADMIN_USER: ${NEXTCLOUD_ADMIN_USER}
      NEXTCLOUD_ADMIN_PASSWORD: ${NEXTCLOUD_ADMIN_PASSWORD}
      NEXTCLOUD_TRUSTED_DOMAINS: ${NEXTCLOUD_TRUSTED_DOMAINS}
      REDIS_HOST: redis
      REDIS_HOST_PASSWORD: ${REDIS_PASSWORD}
      OVERWRITEPROTOCOL: https
      OVERWRITEHOST: ${NEXTCLOUD_TRUSTED_DOMAINS}
      PHP_MEMORY_LIMIT: 512M
      PHP_UPLOAD_LIMIT: 2048M
      APACHE_DISABLE_REWRITE_IP: 1
      TZ: ${TZ}
    volumes:
      - ./data/nextcloud:/var/www/html
    networks:
      - nextcloud-network
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_healthy
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/status.php"]
      interval: 30s
      timeout: 10s
      retries: 3

  nginx-proxy:
    image: nginx:alpine
    container_name: nextcloud-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./data/nextcloud:/var/www/html:ro
      - ./logs/nginx:/var/log/nginx
    networks:
      - nextcloud-network
    depends_on:
      nextcloud-app:
        condition: service_healthy
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 5s
      retries: 3

  onlyoffice:
    image: onlyoffice/documentserver
    container_name: onlyoffice
    restart: unless-stopped
    environment:
      - JWT_ENABLED=true
      - JWT_SECRET=${ONLYOFFICE_JWT_SECRET}
      - JWT_HEADER=Authorization
      - JWT_IN_BODY=true
      - TZ=${TZ}
    networks:
      - nextcloud-network
    volumes:
      - ./data/onlyoffice:/var/www/onlyoffice/Data
      - ./config/onlyoffice/local.json:/etc/onlyoffice/documentserver/local.json:ro
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  nextcloud-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: nextcloud-br0

volumes:
  nextcloud_data:
  mariadb_data:
  redis_data:
  onlyoffice_data:
EOF

echo "SUCCESS: Docker Compose configuration created with MariaDB"

# =================================================================
# STEP 5: CREATE ENHANCED NGINX CONFIGURATION
# =================================================================

echo "Step 5: Creating enhanced Nginx configuration..."

# Create secure nginx configuration with rate limiting
cat > "$DOCKER_DIR/nginx/nginx.conf" << 'EOF'
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Security settings
    server_tokens off;
    
    # Logging with detailed format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    '$request_time $upstream_response_time';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # Performance settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 2048M;
    client_body_timeout 60s;
    client_header_timeout 60s;
    
    # SECURITY: Rate limiting zones - CRITICAL for brute force protection
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/m;      # 1 login per minute
    limit_req_zone $binary_remote_addr zone=general:10m rate=30r/m;   # 30 requests per minute
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/m;       # 10 API requests per minute
    limit_conn_zone $binary_remote_addr zone=addr:10m;                # Connection limiting

    # SECURITY: Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-Robots-Tag "noindex, nofollow" always;

    upstream nextcloud {
        server nextcloud-app:80;
        keepalive 32;
    }

    upstream onlyoffice {
        server onlyoffice:80;
        keepalive 16;
    }

    # Redirect HTTP to HTTPS
    server {
        listen 80;
        server_name workspace.reelanalytics.net;
        
        # Block suspicious user agents
        if ($http_user_agent ~* (nmap|nikto|wikto|sf|sqlmap|bsqlbf|w3af|acunetix|havij|AhrefsBot|MJ12bot|DotBot)) {
            return 444;
        }
        
        # Block requests with no user agent
        if ($http_user_agent = "") {
            return 444;
        }
        
        return 301 https://$server_name$request_uri;
    }

    # HTTPS server
    server {
        listen 443 ssl http2;
        server_name workspace.reelanalytics.net;

        # SSL configuration
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 1h;

        # SECURITY: Enhanced security headers for HTTPS
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; media-src 'self'; object-src 'none'; child-src 'self'; frame-src 'self'; worker-src 'self' blob:; form-action 'self';" always;

        # SECURITY: Rate limiting and connection limiting
        limit_req zone=general burst=50 nodelay;
        limit_conn addr 20;

        # Block malicious requests
        if ($http_user_agent ~* (nmap|nikto|wikto|sf|sqlmap|bsqlbf|w3af|acunetix|havij|AhrefsBot|MJ12bot|DotBot)) {
            return 444;
        }

        if ($http_user_agent = "") {
            return 444;
        }

        # Block access to hidden files and directories
        location ~ /\. {
            deny all;
            access_log off;
            log_not_found off;
        }

        # Block access to sensitive files
        location ~* \.(env|git|svn|htaccess|htpasswd)$ {
            deny all;
            access_log off;
            log_not_found off;
        }

        # STRICT rate limiting for authentication endpoints
        location ~* ^/(index\.php/)?login {
            limit_req zone=login burst=2 nodelay;
            
            proxy_pass http://nextcloud;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_buffering off;
            proxy_request_buffering off;
        }

        # OnlyOffice integration with enhanced security
        location /onlyoffice/ {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://onlyoffice/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
   
            # OnlyOffice specific headers
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            # Increase timeouts for large documents
            proxy_read_timeout 600s;
            proxy_connect_timeout 75s;
            proxy_send_timeout 600s;

            # Handle large file uploads
            proxy_request_buffering off;
            proxy_buffering off;
            client_max_body_size 2G;
        }

        location /cache/ {
            proxy_pass http://onlyoffice/cache/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # Main NextCloud application
        location / {
            proxy_pass http://nextcloud;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $host;
            proxy_buffering off;
            proxy_request_buffering off;
        }

        # WebDAV endpoints with rate limiting
        location /.well-known/carddav {
            limit_req zone=login burst=5 nodelay;
            return 301 $scheme://$host/remote.php/dav;
        }

        location /.well-known/caldav {
            limit_req zone=login burst=5 nodelay;
            return 301 $scheme://$host/remote.php/dav;
        }

        # Block common attack vectors
        location ~* \.(php|pl|cgi|py|sh|lua)$ {
            return 404;
        }

        location ~* /(wp-admin|wp-login|xmlrpc\.php) {
            return 404;
        }
    }
}
EOF

echo "SUCCESS: Enhanced Nginx configuration created"

# =================================================================
# STEP 6: CREATE ONLYOFFICE CONFIGURATION
# =================================================================

echo "Step 6: Creating OnlyOffice configuration..."

# Create OnlyOffice configuration with proper security and file size limits
cat > "$DOCKER_DIR/config/onlyoffice/local.json" << EOF
{
  "services": {
    "CoAuthoring": {
      "server": {
        "port": 8000,
        "mode": "production",
        "limits_tempfile_upload": 2147483648,
        "limits_image_size": 26214400
      },
      "token": {
        "enable": {
          "browser": true,
          "request": {
            "inbox": true,
            "outbox": true
          }
        }
      },
      "secret": {
        "inbox": {"string": "$ONLYOFFICE_JWT_SECRET"},
        "outbox": {"string": "$ONLYOFFICE_JWT_SECRET"},
        "session": {"string": "$ONLYOFFICE_JWT_SECRET"}
      }
    }
  },
  "FileConverter": {
    "converter": {
      "maxDownloadBytes": 2147483648,
              "downloadTimeout": {
          "connectionAndInactivity": "2m",
          "wholeCycle": "2m"
        },
        "downloadAttemptMaxCount": 3,
        "downloadAttemptDelay": 1000
      }
    }
  }
}
EOF

echo "SUCCESS: OnlyOffice configuration created"

# =================================================================
# STEP 7: CREATE MANAGEMENT SCRIPTS
# =================================================================

echo "Step 7: Creating management scripts..."

# Create enhanced start script
cat > "$DOCKER_DIR/start-nextcloud.sh" << 'EOF'
#!/bin/bash
set -e

echo "Starting NextCloud services..."

# Change to docker directory
cd "$(dirname "$0")"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    exit 1
fi

# Start services
docker compose up -d

# Wait for services to start
echo "Waiting for services to start..."
sleep 30

# Check status
echo "Container status:"
docker compose ps

echo "NextCloud is starting up!"
echo ""
echo "Access your NextCloud at:"
echo "   https://workspace.reelanalytics.net"
echo ""
echo "Admin credentials:"
source .env
echo "   Username: $NEXTCLOUD_ADMIN_USER"
echo "   Password: $NEXTCLOUD_ADMIN_PASSWORD"
echo ""
echo "Save these credentials in a secure location!"
EOF

# Create enhanced stop script
cat > "$DOCKER_DIR/stop-nextcloud.sh" << 'EOF'
#!/bin/bash
set -e

echo "Stopping NextCloud services..."

# Change to docker directory
cd "$(dirname "$0")"

# Stop services
docker compose down

echo "NextCloud services stopped"
EOF

# Create OnlyOffice fix script with enhanced security
cat > "$DOCKER_DIR/fix-onlyoffice-filesize.sh" << 'EOF'
#!/bin/bash
echo "Applying OnlyOffice file size fix..."

# Apply the file size fix
docker compose exec onlyoffice sed -i 's/"maxDownloadBytes": 104857600/"maxDownloadBytes": 2147483648/' /etc/onlyoffice/documentserver/default.json

# Restart OnlyOffice services inside the container to apply changes
docker compose exec onlyoffice supervisorctl restart all

# Verify the change was applied
echo "Verifying the fix..."
docker compose exec onlyoffice grep "maxDownloadBytes" /etc/onlyoffice/documentserver/default.json

echo "OnlyOffice file size limit increased to 2GB"
EOF

# Create backup script updated for MariaDB
cat > "$DOCKER_DIR/scripts/backup-nextcloud.sh" << 'EOF'
#!/bin/bash
# NextCloud backup script

BACKUP_DIR="/home/ubuntu/nextcloud-servercore/docker/backups"
DATE=$(date +%Y%m%d_%H%M%S)

echo "Creating NextCloud backup..."

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup database (MariaDB)
docker compose exec mariadb mysqldump -u root -p${MARIADB_ROOT_PASSWORD} nextcloud > "$BACKUP_DIR/nextcloud_db_$DATE.sql"

# Backup NextCloud data
tar -czf "$BACKUP_DIR/nextcloud_data_$DATE.tar.gz" data/nextcloud/

echo "Backup completed: $BACKUP_DIR"
EOF

# Make scripts executable
chmod +x "$DOCKER_DIR/start-nextcloud.sh"
chmod +x "$DOCKER_DIR/stop-nextcloud.sh"
chmod +x "$DOCKER_DIR/fix-onlyoffice-filesize.sh"
chmod +x "$DOCKER_DIR/scripts/backup-nextcloud.sh"

echo "SUCCESS: Management scripts created"

# =================================================================
# STEP 8: CREATE SECURITY MONITORING
# =================================================================

echo "Step 8: Setting up security monitoring..."

# Create security monitoring script
sudo cat > /usr/local/bin/nextcloud-security-monitor.sh << EOF
#!/bin/bash
LOG_FILE="/var/log/nextcloud-security.log"
DATE=\$(date '+%Y-%m-%d %H:%M:%S')

echo "[\$DATE] Security check..." >> \$LOG_FILE

# Check fail2ban status
BANNED_IPS=\$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print \$NF}' || echo "0")
echo "[\$DATE] Banned IPs: \$BANNED_IPS" >> \$LOG_FILE

# Check for failed login attempts
FAILED_LOGINS=\$(tail -100 $DOCKER_DIR/logs/nginx/access.log 2>/dev/null | grep -c " 401 " || echo "0")
echo "[\$DATE] Failed logins: \$FAILED_LOGINS" >> \$LOG_FILE

# Check system load
LOAD=\$(uptime | awk '{print \$(NF-2)}' | sed 's/,//')
echo "[\$DATE] Load: \$LOAD" >> \$LOG_FILE

# Check disk usage
DISK_USAGE=\$(df -h / | awk 'NR==2 {print \$5}')
echo "[\$DATE] Disk usage: \$DISK_USAGE" >> \$LOG_FILE

if [ "\$FAILED_LOGINS" -gt 20 ]; then
    echo "[\$DATE] WARNING: High failed login attempts!" >> \$LOG_FILE
fi
EOF

sudo chmod +x /usr/local/bin/nextcloud-security-monitor.sh

# Setup cron job for security monitoring
(sudo crontab -l 2>/dev/null; echo "*/15 * * * * /usr/local/bin/nextcloud-security-monitor.sh") | sudo crontab -

echo "SUCCESS: Security monitoring configured"

# =================================================================
# STEP 9: CREATE GITIGNORE AND README
# =================================================================

echo "Step 9: Creating project documentation..."

# Create .gitignore
cat > "$DOCKER_DIR/.gitignore" << 'EOF'
# Environment files
.env

# Data directories
data/

# Log files
logs/
*.log

# Backup files
backups/

# SSL certificates
nginx/ssl/*.pem
nginx/ssl/*.key

# Temporary files
*.tmp
*.swp
*~

# OS generated files
.DS_Store
Thumbs.db
EOF

# Create README for the project
cat > "$USER_HOME/$PROJECT_NAME/README.md" << 'EOF'
# NextCloud ServerCore Setup

Enhanced NextCloud deployment with security features and OnlyOffice integration.

## Features

- NextCloud with OnlyOffice integration
- MariaDB database (optimized for NextCloud)
- Enhanced security (Fail2ban, UFW, rate limiting)
- SSL/TLS support
- Automated backups
- Health checks
- Security monitoring

## Deployment

1. Run install-docker.sh (installs Docker + security)
2. Run servercore-setup.sh (creates project structure)
3. Run deploy-nextcloud.sh (deploys services)

## Security Features

- SSH hardened on custom port
- UFW firewall protection
- Fail2ban intrusion prevention
- Nginx rate limiting
- Container security options
- Automated security monitoring

## Management

- Start: `./start-nextcloud.sh`
- Stop: `./stop-nextcloud.sh`
- Backup: `./scripts/backup-nextcloud.sh`
- Logs: `docker compose logs -f`

## Security Monitoring

- Security logs: `/var/log/nextcloud-security.log`
- Fail2ban status: `sudo fail2ban-client status`
- Firewall status: `sudo ufw status`
EOF

echo "SUCCESS: Project documentation created"

# =================================================================
# FINAL SUMMARY
# =================================================================

echo ""
echo "ENHANCED NEXTCLOUD SETUP COMPLETED!"
echo ""
echo "=============================================="
echo "  SCRIPT 2/3 COMPLETED: PROJECT CONFIGURED"
echo "=============================================="
echo ""
echo "Project location: $DOCKER_DIR"
echo ""
echo "Generated credentials (SAVE THESE!):"
echo "   NextCloud Admin: admin / $NEXTCLOUD_ADMIN_PASSWORD"
echo "   MariaDB Root: $MARIADB_ROOT_PASSWORD"
echo "   MariaDB User: nextcloud / $MARIADB_PASSWORD"
echo "   Redis: $REDIS_PASSWORD"
echo "   OnlyOffice JWT: $ONLYOFFICE_JWT_SECRET"
echo ""
echo "Files created:"
echo "   - docker-compose.yml (with MariaDB and security options)"
echo "   - .env (environment variables)"
echo "   - nginx/nginx.conf (hardened web server config)"
echo "   - config/onlyoffice/local.json (JWT secured)"
echo "   - start-nextcloud.sh (startup script)"
echo "   - stop-nextcloud.sh (shutdown script)"
echo "   - fix-onlyoffice-filesize.sh (OnlyOffice optimization)"
echo "   - scripts/backup-nextcloud.sh (MariaDB backup script)"
echo ""
echo "Security enhancements added:"
echo "   - Container security options"
echo "   - Health checks for all services"
echo "   - Rate limiting on login endpoints"
echo "   - Security headers"
echo "   - OnlyOffice JWT authentication"
echo "   - Automated security monitoring"
echo ""
echo "=============================================="
echo "  EXECUTION ORDER"
echo "=============================================="
echo "   [1] install-docker.sh     <- COMPLETED"
echo "   [2] servercore-setup.sh   <- COMPLETED"
echo "   [3] deploy-nextcloud.sh   <- RUN THIS NEXT"
echo ""
echo "NEXT STEPS:"
echo "1. Copy your SSL certificates to: $DOCKER_DIR/nginx/ssl/"
echo "2. Run the deployment script: ./deploy-nextcloud.sh"
echo "3. Access: https://workspace.reelanalytics.net"
echo ""
echo "SAVE ALL CREDENTIALS SECURELY!"