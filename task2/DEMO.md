# Demo: SSL Proxy Monitoring Setup

The full answer to the monitoring questions is in [README.md](./README.md).

I also built a working demo of the monitoring setup to show it in action, not just on paper.

## What's in here

```
task2/
├── DEMO.md                 # This file (how to run the demo)
├── setup/
│   ├── install.sh             # One-command setup for everything
│   ├── loadtest.sh            # SSL load test with wrk + openssl
│   └── uninstall.sh           # Clean removal
├── nginx/
│   ├── nginx.conf             # Tuned for SSL offloading
│   ├── ssl-proxy.conf         # TLS termination + reverse proxy
│   └── generate-certs.sh      # Self-signed cert generator
├── backend/
│   ├── server.py              # Simple Python backend
│   └── backend.service        # Systemd unit
├── prometheus/
│   ├── prometheus.yml         # Scrape config
│   └── alert_rules.yml        # 16 alert rules
├── grafana/
│   ├── datasource.yml         # Auto-provisioned Prometheus source
│   └── dashboards/
│       ├── dashboard.yml      # Provisioning config
│       └── ssl-proxy-monitoring.json  # 26-panel dashboard
├── sysctl/
│   └── 99-ssl-proxy-tuning.conf      # Kernel params for high-throughput
└── screenshots/               # Grafana dashboard captures
```

## Running the demo

You need an Ubuntu 22.04 VM (VMware, VirtualBox, whatever works). I used VMware with 4GB RAM and 2 cores.

**1. Get files onto the VM:**
```bash
# from Windows PowerShell
scp -r task2 <user>@<VM_IP>:~/task2
```

**2. Install everything:**
```bash
ssh <user>@<VM_IP>
cd ~/task2
sudo bash setup/install.sh
```

This installs Nginx, Prometheus, Grafana, Node Exporter, Nginx Exporter, wrk, and applies kernel tuning. Takes about 2-3 minutes.

**3. Run the load test:**
```bash
bash setup/loadtest.sh
```

**4. Open Grafana:**

Go to `http://<VM_IP>:3000` (login: admin/admin) — the dashboard is pre-configured.

## Services

| Service | Port | What it does |
|---------|------|-------------|
| Nginx | 443/80 | SSL termination proxy |
| Backend | 8080 | Simple upstream |
| Prometheus | 9090 | Metrics + alerts |
| Node Exporter | 9100 | System metrics |
| Nginx Exporter | 9113 | Proxy metrics |
| Grafana | 3000 | Dashboards |

## Screenshots

See [screenshots/](./screenshots/) — captures of the Grafana dashboards under load.

## Cleanup

```bash
sudo bash setup/uninstall.sh
```
