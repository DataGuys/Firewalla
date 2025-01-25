# Copy everything below this line (including this comment) and paste into your SSH terminal
cat > install-pihole-unifi.sh << 'EOF'
#!/bin/bash
# ===========================================
# Pi-hole and UniFi Controller Installation Script for Firewalla Gold
# Version: 1.0.2
# 
# This script will automatically be saved and executed after you:
# 1. Paste this entire content into your SSH terminal
# 2. Wait for the prompt to return
# 3. The script will be ready to run with: ./install-pihole-unifi.sh
# ===========================================

# Verify we're running as the correct user
if [ "$USER" != "pi" ]; then
    echo "This script must be run as the 'pi' user"
    exit 1
fi

# Generate a strong random password for Pi-hole
PIHOLE_PASSWORD=$(openssl rand -base64 16)

# Create necessary directories for UniFi
path1=/data/unifi
if [ ! -d "$path1" ]; then
    sudo mkdir $path1
    sudo chown pi $path1
    sudo chmod +rw $path1
    echo -e "\n✅ unifi directory created."
else
    echo -e "\n✅ unifi directory exists."
fi

# Create directory for Pi-hole data
path_pihole=/data/pihole
if [ ! -d "$path_pihole" ]; then
    sudo mkdir $path_pihole
    sudo chown pi $path_pihole
    sudo chmod +rw $path_pihole
    echo -e "\n✅ pihole directory created."
else
    echo -e "\n✅ pihole directory exists."
fi

# Set up Docker run directories
path2=/home/pi/.firewalla/run/docker/unifi/
if [ ! -d "$path2" ]; then
    sudo mkdir -p $path2
    sudo chown pi $path2
    sudo chmod +rw $path2
    echo -e "\n✅ unifi run directory created."
else
    echo -e "\n✅ unifi run directory exists."
fi

# Create and configure docker-compose.yaml
echo "Creating docker-compose.yaml..."
cat > $path2/docker-compose.yaml << 'EOL'
version: '3'
services:
  unifi:
    image: jacobalberty/unifi:latest
    container_name: unifi
    restart: unless-stopped
    environment:
      - TZ=UTC
    networks:
      unifi_default:
        ipv4_address: 172.16.1.2
    volumes:
      - /data/unifi:/unifi
    ports:
      - "3478:3478/udp"
      - "8080:8080"
      - "8443:8443"
      - "8880:8880"
      - "8843:8843"
      - "6789:6789"
      - "10001:10001/udp"

  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    restart: unless-stopped
    environment:
      TZ: 'UTC'
      WEBPASSWORD: ${PIHOLE_PASSWORD}
      FTLCONF_LOCAL_IPV4: '172.16.1.3'
      PIHOLE_DNS_: '1.1.1.1;1.0.0.1'  # Explicitly set upstream DNS
      DNS1: '1.1.1.1'  # Backup DNS configuration
      DNS2: '1.0.0.1'  # Backup DNS configuration
      DNSMASQ_LISTENING: 'all'  # Listen on all interfaces
      FTLCONF_REPLY_ADDR4: '172.16.1.3'
      ServerIP: '172.16.1.3'  # Explicit ServerIP setting
    dns:
      - 1.1.1.1  # Primary DNS for container
      - 1.0.0.1  # Secondary DNS for container
    cap_add:
      - NET_ADMIN
    networks:
      unifi_default:
        ipv4_address: 172.16.1.3
    volumes:
      - '/data/pihole/etc-pihole:/etc/pihole'
      - '/data/pihole/etc-dnsmasq.d:/etc/dnsmasq.d'
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"

networks:
  unifi_default:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.1.0/24
          gateway: 172.16.1.1
    driver_opts:
      com.docker.network.bridge.name: br-pihole
EOL

sudo chown pi $path2/docker-compose.yaml
sudo chmod +rw $path2/docker-compose.yaml
echo -e "\n✅ docker-compose.yaml created."

# Start Docker services
cd $path2
export PIHOLE_PASSWORD
sudo systemctl start docker-compose@unifi

# Function to check if a container is ready
function check_container_ready() {
    local container_name=$1
    echo -n "Starting $container_name (this can take ~ one minute)"
    while [ -z "$(sudo docker ps | grep $container_name | grep -o Up)" ]
    do
        echo -n "."
        sleep 2s
    done
    echo -e "\n✅ $container_name has started"
}

# Wait for both containers to be ready
check_container_ready "unifi"
check_container_ready "pihole"

# Configure networks
echo "configuring networks..."
ID=$(sudo docker network ls | awk '$2 == "unifi_default" {print $1}')
while true; do
    if ping -W 1 -c 1 172.16.1.2 > /dev/null 2>&1 && ip route show table lan_routable | grep -q '172.16.1.0'; then
        break
    fi
    sudo ip route add 172.16.1.0/24 dev br-$ID table lan_routable
    sudo ip route add 172.16.1.0/24 dev br-$ID table wan_routable
done
echo -e "\n✅ Networks configured"

# Configure DNS settings
dns_settings=/home/pi/.firewalla/config/dnsmasq_local/unifi
sudo touch $dns_settings
sudo chown pi $dns_settings
sudo chmod a+rw $dns_settings
echo "address=/unifi/172.16.1.2" > $dns_settings
echo "address=/pihole/172.16.1.3" >> $dns_settings
echo -e "\n✅ Network settings saved."

# Restart DNS service
sleep 10
sudo systemctl restart firerouter_dns
echo -e "\n✅ Network service restarted..."

# Set up auto-start script
path3=/home/pi/.firewalla/config/post_main.d
if [ ! -d "$path3" ]; then
    sudo mkdir $path3
    sudo chown pi $path3
    sudo chmod +rw $path3
fi

cat > $path3/start_unifi_pihole.sh << 'EOL'
#!/bin/bash
sudo systemctl start docker
sudo systemctl start docker-compose@unifi
sudo ipset create -! docker_lan_routable_net_set hash:net
sudo ipset add -! docker_lan_routable_net_set 172.16.1.0/24
sudo ipset create -! docker_wan_routable_net_set hash:net
sudo ipset add -! docker_wan_routable_net_set 172.16.1.0/24
EOL

# Add Gold SE specific networking if needed
[ -f /etc/update-motd.d/00-header ] && series=$(/etc/update-motd.d/00-header | grep "Welcome to" | sed -e "s|Welcome to ||g" -e "s|FIREWALLA ||g" -e "s|\s[0-9].*$||g") || series=""
if [[ "$series" == *"gold-se"* ]] && ! grep -q "MASQUERADE" "$path3/start_unifi_pihole.sh"; then
    echo "Adding Gold SE networking..."
    echo -e "sudo iptables -t nat -A POSTROUTING -s 172.16.1.0/16 -o eth0 -j MASQUERADE" >> $path3/start_unifi_pihole.sh
fi

chmod a+x $path3/start_unifi_pihole.sh
chown pi $path3/start_unifi_pihole.sh

# Create update script
update=/home/pi/.firewalla/run/docker/updatedocker.sh
touch $update
sudo chown pi $update
sudo chmod a+xrw $update

# Final setup and information display
echo -e "\n================================================="
echo -e "Installation Complete! Important Information:"
echo -e "================================================="
echo -e "\nUniFi Controller: https://172.16.1.2:8443"
echo -e "Pi-hole Admin Interface: http://172.16.1.3/admin"
echo -e "\nPi-hole admin password: $PIHOLE_PASSWORD"
echo -e "\nIMPORTANT: Please save this password in a secure location."
echo -e "\nNext Steps:"
echo -e "1. Wait about 2 minutes for all services to fully start"
echo -e "2. Access Pi-hole admin interface at http://172.16.1.3/admin"
echo -e "3. Configure your Firewalla to use 172.16.1.3 as the DNS server"
echo -e "4. The UniFi Controller will be available at https://172.16.1.2:8443"
echo -e "\nNote: Browser security warnings are normal for these local addresses"
echo -e "================================================="
EOF

chmod +x install-pihole-unifi.sh
./install-pihole-unifi.sh
