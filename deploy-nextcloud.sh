#!/bin/bash

#Deploy and start NextCloud services (replaces deploycloud.sh)
# AUTHOR: Lochmoi

set -e

# Configuration
COMPOSE_DIR="/home/ubuntu/nextcloud-servercore/docker"
LOG_FILE="/tmp/nextcloud-deploy.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo "ERROR: $1" >&2
    log "ERROR: $1"
    exit 1
}

# Success message
success() {
    echo "SUCCESS: $1"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo "WARNING: $1"
    log "WARNING: $1"
}

# Info message
info() {
    echo "INFO: $1"
    log "INFO: $1"
}

# Header
echo "=============================================="
echo "  SCRIPT 3/3: NEXTCLOUD DEPLOYMENT"
echo "  Servercore Edition (No Monitoring)"
echo "=============================================="

log "Starting NextCloud deployment process"

# Check if running from correct directory
if [ ! -d "$COMPOSE_DIR" ]; then
    error_exit "Project directory not found at $COMPOSE_DIR. Please run servercore-setup.sh."
fi

cd "$COMPOSE_DIR"

# Check for required files
info "Checking required files..."
[ ! -f "docker-compose.yml" ] && error_exit "docker-compose.yml not found. Run servercore-setup.sh."
[ ! -f ".env" ] && error_exit ".env file not found. Run servercore-setup.sh."
[ ! -f "nginx/nginx.conf" ] && error_exit "nginx configuration not found. Run servercore-setup.sh."

success "All required files found"

# Check Docker installation
info "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    error_exit "Docker is not installed. Please run install-docker.sh."
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    error_exit "Docker Compose is not installed. Please run install-docker.sh."
fi

success "Docker and Docker Compose are installed"

# Check if user is in docker group
if ! groups $USER | grep &>/dev/null '\bdocker\b'; then
    warning "User $USER is not in the docker group."
fi

# Detect server IP
info "Detecting server IP address..."
PUBLIC_IP=""

# Try multiple methods to get public IP
for method in "curl -s --connect-timeout 5 ifconfig.me" "curl -s --connect-timeout 5 ipinfo.io/ip" "curl -s --connect-timeout 5 icanhazip.com" "dig +short myip.opendns.com @resolver1.opendns.com"; do
    if PUBLIC_IP=$(eval "$method" 2>/dev/null) && [ ! -z "$PUBLIC_IP" ]; then
        break
    fi
done

# Fallback to local IP
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    warning "Could not detect public IP, using local IP: $PUBLIC_IP"
else
    success "Detected public IP: $PUBLIC_IP"
fi

# Update trusted domains in .env file
info "Updating trusted domains configuration..."
if grep -q "NEXTCLOUD_TRUSTED_DOMAINS=" .env; then
    sed -i "s/NEXTCLOUD_TRUSTED_DOMAINS=.*/NEXTCLOUD_TRUSTED_DOMAINS=$PUBLIC_IP,localhost/" .env
else
    echo "NEXTCLOUD_TRUSTED_DOMAINS=$PUBLIC_IP,localhost" >> .env
fi

success "Trusted domains updated"

# Create data directories with proper permissions
info "Creating data directories..."
mkdir -p data/{nextcloud,mariadb,redis,onlyoffice}
mkdir -p nginx

# Set proper ownership (if not root)
if [ "$USER" != "root" ]; then
    sudo chown -R $USER:$USER data/
    sudo chown -R $USER:$USER nginx/
fi

success "Data directories created"

# Pull latest images
info "Pulling latest Docker images..."
docker compose pull || error_exit "Failed to pull Docker images"

success "Docker images pulled successfully"

# Stop any existing containers
info "Stopping any existing NextCloud containers..."
if docker compose ps -q | grep -q .; then
    docker compose down
    warning "Stopped existing containers"
fi

# Start containers
info "Starting NextCloud containers..."
if ! docker compose up -d; then
    error_exit "Failed to start containers"
fi

success "Containers started successfully"

# Wait for services to be ready
info "Waiting for services to initialize..."
sleep 10

# Check container health
info "Checking container status..."
FAILED_CONTAINERS=""

for service in mariadb redis nextcloud-app nginx-proxy onlyoffice; do
    if ! docker compose ps | grep -q "$service.*Up"; then
        FAILED_CONTAINERS="$FAILED_CONTAINERS $service"
    fi
done

if [ ! -z "$FAILED_CONTAINERS" ]; then
    error_exit "The following containers failed to start:$FAILED_CONTAINERS"
fi

success "All containers are running"

# Wait a bit more for NextCloud to initialize
info "NextCloud is initializing (this may take a few minutes)..."
sleep 30

# Test connectivity
info "Testing NextCloud connectivity..."
for i in {1..12}; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost" | grep -q "200\|302\|301"; then
        success "NextCloud is responding"
        break
    fi
    if [ $i -eq 12 ]; then
        warning "NextCloud may still be initializing. Check logs if needed."
    else
        sleep 10
    fi
done

# Get credentials from .env file
source .env

# Display final information
echo ""
echo "NextCloud deployment completed successfully!"
echo "=============================================="
echo "  SCRIPT 3/3 COMPLETED: DEPLOYMENT FINISHED"
echo "=============================================="

echo "================================================="
echo "           ACCESS INFORMATION"
echo "================================================="
echo ""
echo "NextCloud URL:"
echo "   http://$PUBLIC_IP"
echo ""
echo "Admin Credentials:"
echo "   Username: $NEXTCLOUD_ADMIN_USER"
echo "   Password: $NEXTCLOUD_ADMIN_PASSWORD"
echo ""
echo "================================================="
echo "           CONTAINER STATUS"
echo "================================================="
docker compose ps
echo ""
echo "================================================="
echo "           MANAGEMENT COMMANDS"
echo "================================================="
echo ""
echo "Project directory: $COMPOSE_DIR"
echo ""
echo "Management commands:"
echo "   Start:   ./start-nextcloud.sh"
echo "   Stop:    ./stop-nextcloud.sh"
echo "   Logs:    docker compose logs -f"
echo "   Status:  docker compose ps"
echo ""
echo "Configuration files:"
echo "   Environment: .env"
echo "   Compose:     docker-compose.yml"
echo "   Nginx:       nginx/nginx.conf"
echo ""
echo "Next steps:"
echo "1. Open http://$PUBLIC_IP in your browser"
echo "2. Log in with the admin credentials above"
echo "3. Complete the NextCloud setup wizard"
echo "4. Configure your apps and users"
echo ""
echo "IMPORTANT: Save your credentials securely!"
echo ""

# Save deployment info
cat > deployment-info.txt << EOF
NextCloud Deployment Information
================================
Deployment Date: $(date)
Server IP: $PUBLIC_IP
NextCloud URL: http://$PUBLIC_IP

Admin Credentials:
Username: $NEXTCLOUD_ADMIN_USER
Password: $NEXTCLOUD_ADMIN_PASSWORD

Database: MariaDB
Database User: $MARIADB_USER
Database Password: $MARIADB_PASSWORD

Project Directory: $COMPOSE_DIR

Container Status:
$(docker compose ps)

Management Commands:
- Start: ./start-nextcloud.sh
- Stop: ./stop-nextcloud.sh
- Logs: docker compose logs -f
- Status: docker compose ps
EOF

success "Deployment information saved to deployment-info.txt"

log "NextCloud deployment completed successfully"

echo "For troubleshooting, check the deployment log: $LOG_FILE"
echo ""
echo "Your NextCloud is now ready to use!"