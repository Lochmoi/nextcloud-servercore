#!/bin/bash

# Docker Compose files, and configuration.
#Author: Lochmoi

set -e

echo "  SCRIPT 2/3: nextcloud setup"
echo "🚀 Setting up NextCloud on Servercore..."

# Servercore environment variables
PROJECT_NAME="nextcloud-servercore"
DOCKER_DIR="/home/ubuntu/${PROJECT_NAME}/docker"

# Check if running as root or with sudo access
if [[ $EUID -eq 0 ]]; then
    USER_HOME="/root"
    SYSTEM_USER="root"
else
     USER_HOME="/home/ubuntu"
     SYSTEM_USER="ubuntu"

fi

echo -e "\n📋 Configuration:"
echo "   User: $SYSTEM_USER"
echo "   Home: $USER_HOME"
echo "   Docker directory: $DOCKER_DIR"

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p "$DOCKER_DIR"
mkdir -p "$DOCKER_DIR/data/nextcloud"
mkdir -p "$DOCKER_DIR/data/mysql"
mkdir -p "$DOCKER_DIR/data/redis"
mkdir -p "$DOCKER_DIR/nginx"

# Set proper ownership
if [ "$SYSTEM_USER" != "root" ]; then
    sudo chown -R $SYSTEM_USER:$SYSTEM_USER "$USER_HOME/$PROJECT_NAME"
fi

# Generate secure passwords
echo "🔐 Generating secure passwords..."
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
MYSQL_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 16)
REDIS_PASSWORD=$(openssl rand -base64 24)
COLLABORA_PASSWORD=$(openssl rand -base64 16)
# Create .env file
echo "📝 Creating environment configuration..."
cat > "$DOCKER_DIR/.env" << EOF 
# NextCloud Configuration
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
NEXTCLOUD_TRUSTED_DOMAINS=localhost

# MySQL Configuration  
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud

# Redis Configuration
REDIS_PASSWORD=$REDIS_PASSWORD

# Network Configuration
COMPOSE_PROJECT_NAME=$PROJECT_NAME
EOF

echo ".env" >> "$DOCKER_DIR/.gitignore"

# Create docker-compose.yml 
echo "🐳 Creating Docker Compose configuration..."
cat > "$DOCKER_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    container_name: nextcloud-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
    volumes:
      - ./data/mysql:/var/lib/mysql
    networks:
      - nextcloud-network
    command: --default-authentication-plugin=mysql_native_password

  redis:
    image: redis:7-alpine
    container_name: nextcloud-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - ./data/redis:/data
    networks:
      - nextcloud-network

  nextcloud-app:
    image: nextcloud:latest
    container_name: nextcloud-app
    restart: unless-stopped
    environment:
      MYSQL_HOST: mysql
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      NEXTCLOUD_ADMIN_USER: ${NEXTCLOUD_ADMIN_USER}
      NEXTCLOUD_ADMIN_PASSWORD: ${NEXTCLOUD_ADMIN_PASSWORD}
      NEXTCLOUD_TRUSTED_DOMAINS: ${NEXTCLOUD_TRUSTED_DOMAINS}
      REDIS_HOST: redis
      REDIS_HOST_PASSWORD: ${REDIS_PASSWORD}
      OVERWRITEPROTOCOL: http
    volumes:
      - ./data/nextcloud:/var/www/html
    networks:
      - nextcloud-network
    depends_on:
      - mysql
      - redis

  nginx-proxy:
    image: nginx:alpine
    container_name: nextcloud-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./data/nextcloud:/var/www/html:ro
    networks:
      - nextcloud-network
    depends_on:
      - nextcloud-app

networks:
  nextcloud-network:
    driver: bridge

volumes:
  nextcloud_data:
  mysql_data:
  redis_data:
EOF

# Create nginx configuration
echo "🌐 Creating Nginx configuration..."
cat > "$DOCKER_DIR/nginx/nginx.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 16G;

    upstream nextcloud {
        server nextcloud-app:80;
    }

    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://nextcloud;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
            proxy_request_buffering off;
        }

        location /.well-known/carddav {
            return 301 $scheme://$host/remote.php/dav;
        }

        location /.well-known/caldav {
            return 301 $scheme://$host/remote.php/dav;
        }
    }
}
EOF

# Create startup script
echo "🔧 Creating startup script..."
cat > "$DOCKER_DIR/start-nextcloud.sh" << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting NextCloud services..."

# Change to docker directory
cd "$(dirname "$0")"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    exit 1
fi

# Start services
docker compose up -d

# Wait for services to start
echo "⏳ Waiting for services to start..."
sleep 30

# Check status
echo "📊 Container status:"
docker compose ps

echo "✅ NextCloud is starting up!"
echo ""
echo "🌐 Access your NextCloud at:"
echo "   http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
echo ""
echo "🔐 Admin credentials:"
source .env
echo "   Username: $NEXTCLOUD_ADMIN_USER"
echo "   Password: $NEXTCLOUD_ADMIN_PASSWORD"
echo ""
echo "📝 Save these credentials in a secure location!"
EOF

chmod +x "$DOCKER_DIR/start-nextcloud.sh"

# Create stop script
cat > "$DOCKER_DIR/stop-nextcloud.sh" << 'EOF'
#!/bin/bash
set -e

echo "🛑 Stopping NextCloud services..."

# Change to docker directory
cd "$(dirname "$0")"

# Stop services
docker compose down

echo "✅ NextCloud services stopped"
EOF

chmod +x "$DOCKER_DIR/stop-nextcloud.sh"

# Final setup
echo "🔧 Final setup..."
cd "$DOCKER_DIR"

# Set proper permissions
chmod 600 .env
chmod +x *.sh

echo "=============================================="
echo "  SCRIPT 2/3 COMPLETED: PROJECT CONFIGURED"
echo "=============================================="
echo ""
echo "📁 Project location: $DOCKER_DIR"
echo ""
echo "🔐 Generated credentials (save these!):"
echo "   NextCloud Admin: admin / $NEXTCLOUD_ADMIN_PASSWORD"
echo "   MySQL Root: root / $MYSQL_ROOT_PASSWORD"
echo "   MySQL User: nextcloud / $MYSQL_PASSWORD"
echo "   Redis Password: $REDIS_PASSWORD"
echo ""
echo "📝 Files created:"
echo "   - docker-compose.yml"
echo "   - .env (environment variables)"
echo "   - nginx/nginx.conf (web server config)"
echo "   - start-nextcloud.sh (startup script)"
echo "   - stop-nextcloud.sh (shutdown script)"
echo ""
echo "🔄 EXECUTION ORDER:"
echo "✅ [1] install-docker.sh     ← COMPLETED"
echo "✅ [2] servercore-setup.sh   ← COMPLETED"
echo "⏳ [3] deploy-nextcloud.sh   ← NEXT"