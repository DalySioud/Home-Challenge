#!/usr/bin/env bash
#
# install.sh — Automated setup for SSL Offloading Proxy Monitoring Stack
#
# Usage: sudo bash install.sh
#
# This script installs and configures:
#   - Nginx (SSL reverse proxy)
#   - Self-signed TLS certificates
#   - Simple Python backend server
#   - Prometheus
#   - Node Exporter
#   - Nginx Prometheus Exporter
#   - Grafana with pre-configured dashboards
#   - wrk (load testing tool)
#   - Kernel tuning for high-throughput networking
#

set -euo pipefail

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use: sudo bash install.sh)"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"

echo ""
echo "=============================================="
echo " SSL Offloading Proxy — Monitoring Setup"
echo "=============================================="
echo ""

# ============================================================
# 1. SYSTEM UPDATE & BASE PACKAGES
# ============================================================
log_info "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    python3 \
    build-essential \
    libssl-dev \
    git \
    unzip \
    jq \
    net-tools \
    sysstat \
    htop \
    iotop

log_success "Base packages installed"

# ============================================================
# 2. INSTALL NGINX
# ============================================================
log_info "Installing Nginx..."
apt-get install -y -qq nginx
systemctl enable nginx
log_success "Nginx installed"

# ============================================================
# 3. GENERATE SELF-SIGNED SSL CERTIFICATES
# ============================================================
log_info "Generating self-signed SSL certificates..."
mkdir -p /etc/nginx/ssl

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/server.key \
    -out /etc/nginx/ssl/server.crt \
    -subj "/C=US/ST=State/L=City/O=SSLProxy/OU=Monitoring/CN=ssl-proxy.local" \
    2>/dev/null

chmod 600 /etc/nginx/ssl/server.key
chmod 644 /etc/nginx/ssl/server.crt
log_success "SSL certificates generated at /etc/nginx/ssl/"

# ============================================================
# 4. CONFIGURE NGINX AS SSL REVERSE PROXY
# ============================================================
log_info "Configuring Nginx as SSL offloading proxy..."

cp "${PROJECT_DIR}/nginx/nginx.conf" /etc/nginx/nginx.conf
cp "${PROJECT_DIR}/nginx/ssl-proxy.conf" /etc/nginx/sites-available/ssl-proxy.conf

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/ssl-proxy.conf /etc/nginx/sites-enabled/ssl-proxy.conf

nginx -t
systemctl restart nginx
log_success "Nginx configured and running"

# ============================================================
# 5. SETUP BACKEND SERVER
# ============================================================
log_info "Setting up backend server..."

mkdir -p /opt/backend
cp "${PROJECT_DIR}/backend/server.py" /opt/backend/server.py
cp "${PROJECT_DIR}/backend/backend.service" /etc/systemd/system/backend.service

systemctl daemon-reload
systemctl enable backend
systemctl start backend
log_success "Backend server running on port 8080"

# ============================================================
# 6. INSTALL NODE EXPORTER
# ============================================================
log_info "Installing Node Exporter..."

NODE_EXPORTER_VERSION="1.7.0"
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*

useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
    --collector.cpu \
    --collector.meminfo \
    --collector.diskstats \
    --collector.filesystem \
    --collector.loadavg \
    --collector.netdev \
    --collector.netstat \
    --collector.stat \
    --collector.vmstat \
    --collector.entropy \
    --collector.conntrack \
    --collector.sockstat \
    --collector.filefd \
    --collector.interrupts \
    --collector.tcpstat \
    --collector.softnet
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter
log_success "Node Exporter running on port 9100"

# ============================================================
# 7. INSTALL NGINX PROMETHEUS EXPORTER
# ============================================================
log_info "Installing Nginx Prometheus Exporter..."

NGINX_EXPORTER_VERSION="1.1.0"
cd /tmp
wget -q "https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"
tar xzf "nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"
cp nginx-prometheus-exporter /usr/local/bin/
rm -f nginx-prometheus-exporter* LICENSE

useradd --no-create-home --shell /bin/false nginx_exporter 2>/dev/null || true

cat > /etc/systemd/system/nginx_exporter.service << 'EOF'
[Unit]
Description=Nginx Prometheus Exporter
Documentation=https://github.com/nginxinc/nginx-prometheus-exporter
After=network-online.target nginx.service

[Service]
User=nginx_exporter
Group=nginx_exporter
Type=simple
ExecStart=/usr/local/bin/nginx-prometheus-exporter \
    --nginx.scrape-uri=http://127.0.0.1:8081/stub_status
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nginx_exporter
systemctl start nginx_exporter
log_success "Nginx Exporter running on port 9113"

# ============================================================
# 8. INSTALL PROMETHEUS
# ============================================================
log_info "Installing Prometheus..."

PROMETHEUS_VERSION="2.50.1"
cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

mkdir -p /etc/prometheus /var/lib/prometheus
cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/
cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /usr/local/bin/
cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles" /etc/prometheus/
cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries" /etc/prometheus/
rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64"*

cp "${PROJECT_DIR}/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml
cp "${PROJECT_DIR}/prometheus/alert_rules.yml" /etc/prometheus/alert_rules.yml

useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus Monitoring System
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --storage.tsdb.retention.time=15d \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus
log_success "Prometheus running on port 9090"

# ============================================================
# 9. INSTALL GRAFANA
# ============================================================
log_info "Installing Grafana..."

mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg 2>/dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list > /dev/null
apt-get update -qq
apt-get install -y -qq grafana

mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /var/lib/grafana/dashboards

cp "${PROJECT_DIR}/grafana/datasource.yml" /etc/grafana/provisioning/datasources/datasource.yml
cp "${PROJECT_DIR}/grafana/dashboards/dashboard.yml" /etc/grafana/provisioning/dashboards/dashboard.yml
cp "${PROJECT_DIR}/grafana/dashboards/ssl-proxy-monitoring.json" /var/lib/grafana/dashboards/ssl-proxy-monitoring.json

chown -R grafana:grafana /var/lib/grafana/dashboards

systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server
log_success "Grafana running on port 3000 (admin/admin)"

# ============================================================
# 10. INSTALL WRK (LOAD TESTING TOOL)
# ============================================================
log_info "Installing wrk (load testing tool)..."

cd /tmp
if [ ! -d "wrk" ]; then
    git clone --quiet https://github.com/wg/wrk.git
fi
cd wrk
make -j"$(nproc)" > /dev/null 2>&1
cp wrk /usr/local/bin/
cd /tmp && rm -rf wrk
log_success "wrk installed"

# ============================================================
# 11. KERNEL TUNING
# ============================================================
log_info "Applying kernel tuning for high-throughput proxy..."

cp "${PROJECT_DIR}/sysctl/99-ssl-proxy-tuning.conf" /etc/sysctl.d/99-ssl-proxy-tuning.conf
sysctl --system > /dev/null 2>&1

cat > /etc/security/limits.d/99-ssl-proxy.conf << 'EOF'
*    soft    nofile    1000000
*    hard    nofile    1000000
root soft    nofile    1000000
root hard    nofile    1000000
EOF

log_success "Kernel tuning applied"

# ============================================================
# 12. OPEN FIREWALL PORTS (if UFW is active)
# ============================================================
if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "active"; then
    log_info "Configuring firewall rules..."
    ufw allow 80/tcp   > /dev/null
    ufw allow 443/tcp  > /dev/null
    ufw allow 3000/tcp > /dev/null
    ufw allow 9090/tcp > /dev/null
    log_success "Firewall rules added"
fi

# ============================================================
# FINAL STATUS CHECK
# ============================================================
echo ""
echo "=============================================="
echo " Installation Complete!"
echo "=============================================="
echo ""

VM_IP=$(hostname -I | awk '{print $1}')

check_service() {
    if systemctl is-active --quiet "$1"; then
        echo -e "  ${GREEN}✓${NC} $1 is running"
    else
        echo -e "  ${RED}✗${NC} $1 is NOT running"
    fi
}

log_info "Service Status:"
check_service nginx
check_service backend
check_service node_exporter
check_service nginx_exporter
check_service prometheus
check_service grafana-server

echo ""
log_info "Access URLs (from your Windows browser):"
echo "  Grafana:     http://${VM_IP}:3000  (user: admin / pass: admin)"
echo "  Prometheus:  http://${VM_IP}:9090"
echo "  Nginx HTTPS: https://${VM_IP}:443"
echo ""
log_info "Next step — run the load test:"
echo "  bash ~/task2/setup/loadtest.sh"
echo ""
log_success "Setup complete!"
