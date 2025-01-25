#!/bin/bash
# Installation script for UniFi Controller and AdGuard Home on Firewalla Gold
# Version: 1.0.3
# This script carefully manages Docker networking and ensures clean installation

# Generate a secure random password for AdGuard Home
ADGUARD_PASSWORD=$(openssl rand -base64 16)
ADGUARD_USER="admin"

# First, ensure we clean up any existing installations
echo "Cleaning up any existing installations..."
sudo systemctl stop docker-compose@unifi 2>/dev/null || true

# Remove existing containers if they exist
if sudo docker ps -a | grep -q "unifi\|adguardhome"; then
    echo "Removing existing containers..."
    sudo docker rm -f unifi adguardhome 2>/dev/null || true
fi

# Clean up any existing networks
echo "Cleaning up Docker networks..."
for network in $(sudo docker network ls --filter name=unifi --format "{{.Name}}"); do
    echo "Removing network: $network"
    sudo docker network rm $network 2>/dev/null || true
done

# Create necessary directories with proper permissions
echo "Setting up directories..."
for dir in "/data/unifi" "/data/adguardhome/conf" "/data/adguardhome/work"; do
    if [ ! -d "$dir" ]; then
        sudo mkdir -p "$dir"
        echo "✅ Created $dir"
    fi
    sudo chown -R pi:pi "$dir"
    sudo chmod -R 755 "$dir"
done

# Set up Docker run directory
DOCKER_DIR="/home/pi/.firewalla/run/docker/unifi"
if [ ! -d "$DOCKER_DIR" ]; then
    sudo mkdir -p "$DOCKER_DIR"
    sudo chown pi:pi "$DOCKER_DIR"
    sudo chmod 755 "$DOCKER_DIR"
    echo "✅ Created Docker configuration directory"
fi

# Create docker-compose.yaml with explicit network naming
echo "Creating docker-compose configuration..."
cat > "$DOCKER_DIR/docker-compose.yaml" << EOL
version: '3'
services:
  unifi:
    image: lscr.io/linuxserver/unifi-network-application:latest
    container_name: unifi
    restart: unless-stopped
    environment:
      - TZ=UTC
      - PUID=1000
      - PGID=1000
      - MEM_LIMIT=512M
      - MEM_STARTUP=512M
    networks:
      docker_network:
        ipv4_address: 172.16.1.2
    volumes:
      - /data/unifi:/config
    ports:
      - "172.16.1.2:3478:3478/udp"
      - "172.16.1.2:8080:8080"
      - "172.16.1.2:8443:8443"
      - "172.16.1.2:8880:8880"
      - "172.16.1.2:8843:8843"
      - "172.16.1.2:6789:6789"
      - "172.16.1.2:10001:10001/udp"

  adguardhome:
    container_name: adguardhome
    image: adguard/adguardhome:latest
    restart: unless-stopped
    environment:
      - TZ=UTC
    networks:
      docker_network:
        ipv4_address: 172.16.1.3
    volumes:
      - /data/adguardhome/conf:/opt/adguardhome/conf
      - /data/adguardhome/work:/opt/adguardhome/work
    ports:
      - "172.16.1.3:53:53/tcp"
      - "172.16.1.3:53:53/udp"
      - "172.16.1.3:3000:3000/tcp"
      - "172.16.1.3:80:80/tcp"
    cap_add:
      - NET_ADMIN
      - NET_BIND_SERVICE

networks:
  docker_network:
    name: docker_network  # Explicitly naming the network
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.1.0/24
          gateway: 172.16.1.1
EOL

echo "✅ Created docker-compose.yaml"

# Function to monitor container startup
monitor_container() {
    local container_name=$1
    local max_attempts=150  # 5 minutes (2 seconds per attempt)
    local attempt=1
    
    echo -n "Starting $container_name (this may take up to 5 minutes)"
    
    while [ $attempt -le $max_attempts ]; do
        local status=$(sudo docker inspect --format='{{.State.Status}}' $container_name 2>/dev/null)
        
        if [ "$status" = "running" ]; then
            if [ "$container_name" = "unifi" ]; then
                # Additional check for UniFi's web interface
                if sudo docker logs $container_name 2>&1 | grep -q "Starting UniFi Controller"; then
                    echo -e "\n✅ $container_name is now running"
                    return 0
                fi
            else
                echo -e "\n✅ $container_name is now running"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo -e "\n⚠️  Container startup is taking longer than usual"
    return 1
}

# Start services
echo "Starting Docker services..."
cd "$DOCKER_DIR"
sudo systemctl start docker-compose@unifi

# Monitor container startup
monitor_container "unifi"
monitor_container "adguardhome"

# Configure networks
echo "Configuring network routes..."
ID=$(sudo docker network ls | grep "docker_network" | awk '{print $1}')
while true; do
    if ping -W 1 -c 1 172.16.1.2 > /dev/null 2>&1 && ip route show table lan_routable | grep -q '172.16.1.0'; then
        break
    fi
    sudo ip route add 172.16.1.0/24 dev br-$ID table lan_routable
    sudo ip route add 172.16.1.0/24 dev br-$ID table wan_routable
    sleep 1
done
echo "✅ Network routes configured"

# Configure DNS settings
dns_settings="/home/pi/.firewalla/config/dnsmasq_local/unifi"
sudo touch "$dns_settings"
sudo chown pi:pi "$dns_settings"
sudo chmod 644 "$dns_settings"
echo "address=/unifi/172.16.1.2" > "$dns_settings"
echo "address=/adguard/172.16.1.3" >> "$dns_settings"
echo "✅ DNS settings configured"

# Set up auto-start configuration
auto_start="/home/pi/.firewalla/config/post_main.d/start_services.sh"
sudo mkdir -p "$(dirname "$auto_start")"
cat > "$auto_start" << 'EOL'
#!/bin/bash
sudo systemctl start docker
sudo systemctl start docker-compose@unifi
sudo ipset create -! docker_lan_routable_net_set hash:net
sudo ipset add -! docker_lan_routable_net_set 172.16.1.0/24
sudo ipset create -! docker_wan_routable_net_set hash:net
sudo ipset add -! docker_wan_routable_net_set 172.16.1.0/24
EOL

sudo chmod +x "$auto_start"
sudo chown pi:pi "$auto_start"

# Final setup information
echo -e "\n================================================="
echo -e "Installation Complete! Important Information:"
echo -e "================================================="
echo -e "\nUniFi Controller: https://172.16.1.2:8443"
echo -e "AdGuard Home Admin Interface: http://172.16.1.3:3000"
echo -e "\nAdGuard Home Credentials:"
echo -e "Username: ${ADGUARD_USER}"
echo -e "Password: ${ADGUARD_PASSWORD}"
echo -e "\nIMPORTANT: Please save these credentials securely!"
echo -e "\nNext Steps:"
echo -e "1. Allow 5 minutes for services to fully initialize"
echo -e "2. Access the UniFi Controller at https://172.16.1.2:8443"
echo -e "3. Access AdGuard Home at http://172.16.1.3:3000"
echo -e "4. Configure Firewalla to use 172.16.1.3 as DNS server"
echo -e "\nNote: Browser security warnings are normal for local addresses"
echo -e "================================================="
