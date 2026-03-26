#!/usr/bin/env bash
#
# uninstall.sh — Remove all monitoring components
#
# Usage: sudo bash uninstall.sh
#

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use: sudo bash uninstall.sh)"
    exit 1
fi

echo "Stopping and disabling services..."
for svc in grafana-server prometheus nginx_exporter node_exporter backend nginx; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done

echo "Removing custom systemd unit files..."
rm -f /etc/systemd/system/node_exporter.service
rm -f /etc/systemd/system/nginx_exporter.service
rm -f /etc/systemd/system/prometheus.service
rm -f /etc/systemd/system/backend.service
systemctl daemon-reload

echo "Removing binaries..."
rm -f /usr/local/bin/node_exporter
rm -f /usr/local/bin/nginx-prometheus-exporter
rm -f /usr/local/bin/prometheus
rm -f /usr/local/bin/promtool
rm -f /usr/local/bin/wrk

echo "Removing configurations and data..."
rm -rf /etc/prometheus
rm -rf /var/lib/prometheus
rm -rf /etc/nginx/ssl
rm -f /etc/nginx/sites-enabled/ssl-proxy.conf
rm -f /etc/nginx/sites-available/ssl-proxy.conf
rm -rf /opt/backend
rm -f /etc/sysctl.d/99-ssl-proxy-tuning.conf
rm -f /etc/security/limits.d/99-ssl-proxy.conf

echo "Removing Grafana provisioning..."
rm -f /etc/grafana/provisioning/datasources/datasource.yml
rm -f /etc/grafana/provisioning/dashboards/dashboard.yml
rm -rf /var/lib/grafana/dashboards

echo "Removing service users..."
userdel node_exporter 2>/dev/null || true
userdel nginx_exporter 2>/dev/null || true
userdel prometheus 2>/dev/null || true

echo "Removing packages..."
apt-get remove -y grafana nginx 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
rm -f /etc/apt/sources.list.d/grafana.list
rm -f /etc/apt/keyrings/grafana.gpg

echo "Reloading sysctl..."
sysctl --system > /dev/null 2>&1

echo ""
echo "Uninstall complete."
