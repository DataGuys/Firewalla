#!/bin/bash
# AdGuard Home and UniFi Controller Installation Script for Firewalla Gold
# Version: 1.0.0

# Generate a secure random password for AdGuard Home
ADGUARD_PASSWORD=$(openssl rand -base64 16)
# Generate a username (default: admin)
ADGUARD_USER="admin"

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

# Create directory for AdGuard Home data
path_adguard=/data/adguardhome
if [ ! -d "$path_adguard" ]; then
    sudo mkdir -p $path_adguard/conf
    sudo mkdir -p $path_adguard/work
    sudo chown -R pi:pi $path_adguard
    sudo chmod -R +rw $path_adguard
    echo -e "\n✅ AdGuard Home directories created."
else
    echo -e "\n✅ AdGuard Home directories exist."
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
cat > $path2/docker-compose.yaml << EOL
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

  adguardhome:
    container_name: adguardhome
    image: adguard/adguardhome:latest
    restart: unless-stopped
    environment:
      - TZ=UTC
    networks:
      unifi_default:
        ipv4_address: 172.16.1.3
    volumes:
      - /data/adguardhome/conf:/opt/adguardhome/conf
      - /data/adguardhome/work:/opt/adguardhome/work
    # Note: We're binding specifically to the Docker network IP
    ports:
      - "172.16.1.3:53:53/tcp"
      - "172.16.1.3:53:53/udp"
      - "172.16.1.3:3000:3000/tcp"
      - "172.16.1.3:80:80/tcp"
    dns:
      - 1.1.1.1
      - 1.0.0.1
    cap_add:
      - NET_ADMIN
      - NET_BIND_SERVICE

networks:
  unifi_default:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.1.0/24
          gateway: 172.16.1.1
EOL

sudo chown pi $path2/docker-compose.yaml
sudo chmod +rw $path2/docker-compose.yaml
echo -e "\n✅ docker-compose.yaml created."

# Create initial AdGuard Home configuration
cat > $path_adguard/conf/AdGuardHome.yaml << EOL
bind_host: 0.0.0.0
bind_port: 3000
beta_bind_port: 0
users:
  - name: ${ADGUARD_USER}
    password: ${ADGUARD_PASSWORD}
auth_attempts: 5
block_auth_min: 15
http_proxy: ""
language: ""
debug_pprof: false
web_session_ttl: 720
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  statistics_interval: 1
  querylog_enabled: true
  querylog_file_enabled: true
  querylog_interval: 2160h
  querylog_size_memory: 1000
  anonymize_client_ip: false
  protection_enabled: true
  blocking_mode: default
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_response_ttl: 10
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  ratelimit: 20
  ratelimit_whitelist: []
  refuse_any: true
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - https://dns.google/dns-query
  upstream_dns_file: ""
  bootstrap_dns:
    - 1.1.1.1
    - 8.8.8.8
  all_servers: false
  fastest_addr: false
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
  trusted_proxies:
    - 127.0.0.1
    - ::1
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: true
  edns_client_subnet: false
  max_goroutines: 300
  ipset: []
  filtering_enabled: true
  filters_update_interval: 24
  parental_enabled: false
  safesearch_enabled: false
  safebrowsing_enabled: false
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576
  cache_time: 30
  rewrites: []
  blocked_services: []
  upstream_timeout: 10s
  local_domain_name: lan
  resolve_clients: true
  use_private_ptr_resolvers: true
  local_ptr_upstreams: []
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  certificate_chain: ""
  private_key: ""
  certificate_path: ""
  private_key_path: ""
filters:
  - enabled: true
    url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true
    url: https://adaway.org/hosts.txt
    name: AdAway Default Blocklist
    id: 2
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
  interface_name: ""
  local_domain_name: lan
  dhcpv4:
    gateway_ip: ""
    subnet_mask: ""
    range_start: ""
    range_end: ""
    lease_duration: 86400
    icmp_timeout_msec: 1000
    options: []
  dhcpv6:
    range_start: ""
    lease_duration: 86400
    ra_slaac_only: false
    ra_allow_slaac: false
clients: []
log_compress: false
log_localtime: false
log_max_backups: 0
log_max_size: 100
log_max_age: 3
log_file: ""
verbose: false
os:
  group: ""
  user: ""
  rlimit_nofile: 0
schema_version: 12
EOL

# Start Docker services
cd $path2
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
check_container_ready "adguardhome"

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
echo "address=/adguard/172.16.1.3" >> $dns_settings
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

cat > $path3/start_unifi_adguard.sh << 'EOL'
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
if [[ "$series" == *"gold-se"* ]] && ! grep -q "MASQUERADE" "$path3/start_unifi_adguard.sh"; then
    echo "Adding Gold SE networking..."
    echo -e "sudo iptables -t nat -A POSTROUTING -s 172.16.1.0/16 -o eth0 -j MASQUERADE" >> $path3/start_unifi_adguard.sh
fi

chmod a+x $path3/start_unifi_adguard.sh
chown pi $path3/start_unifi_adguard.sh

# Final setup and information display
echo -e "\n================================================="
echo -e "Installation Complete! Important Information:"
echo -e "================================================="
echo -e "\nUniFi Controller: https://172.16.1.2:8443"
echo -e "AdGuard Home Admin Interface: http://172.16.1.3:3000"
echo -e "\nAdGuard Home Credentials:"
echo -e "Username: ${ADGUARD_USER}"
echo -e "Password: ${ADGUARD_PASSWORD}"
echo -e "\nIMPORTANT: Please save these credentials in a secure location."
echo -e "\nNext Steps:"
echo -e "1. Wait about 2 minutes for all services to fully start"
echo -e "2. Access AdGuard Home admin interface at http://172.16.1.3:3000"
echo -e "3. Configure your Firewalla to use 172.16.1.3 as the DNS server"
echo -e "4. The UniFi Controller will be available at https://172.16.1.2:8443"
echo -e "\nNote: Browser security warnings are normal for these local addresses"
echo -e "================================================="
