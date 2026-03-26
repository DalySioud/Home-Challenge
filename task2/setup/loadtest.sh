#!/usr/bin/env bash
#
# loadtest.sh — Generate SSL load against the proxy to populate monitoring dashboards
#
# This load test specifically targets HTTPS to exercise the SSL offloading pipeline:
#   Client → [TLS handshake] → Nginx (SSL termination) → [plain HTTP] → Backend
#
# Usage: bash loadtest.sh [duration_seconds] [connections] [threads]
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DURATION="${1:-60}"
CONNECTIONS="${2:-500}"
THREADS="${3:-4}"

echo ""
echo "=============================================="
echo " SSL Offloading Proxy — Load Test"
echo "=============================================="
echo ""
echo -e "${BLUE}[CONFIG]${NC} Duration:    ${DURATION}s"
echo -e "${BLUE}[CONFIG]${NC} Connections: ${CONNECTIONS}"
echo -e "${BLUE}[CONFIG]${NC} Threads:     ${THREADS}"
echo -e "${BLUE}[CONFIG]${NC} Target:      https://127.0.0.1/ (TLS termination)"
echo ""

if ! command -v wrk &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} wrk is not installed. Run install.sh first."
    exit 1
fi

if ! systemctl is-active --quiet nginx; then
    echo -e "${RED}[ERROR]${NC} Nginx is not running."
    exit 1
fi

VM_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}[INFO]${NC} Check Grafana at http://${VM_IP}:3000 while this runs!"
echo -e "${GREEN}[INFO]${NC} Look at the ${CYAN}SSL / TLS Offloading${NC} dashboard row for SSL-specific metrics."
echo ""

# ====================================================================
# Phase 0: SSL Handshake Benchmark (openssl s_time)
# ====================================================================
echo -e "${BLUE}[PHASE 0/4]${NC} SSL Handshake Benchmark (10 seconds)..."
echo -e "  Testing how many TLS handshakes/sec this server can sustain:"
echo ""

if command -v openssl &> /dev/null; then
    # Test new TLS handshakes (no session reuse) — most CPU-expensive
    echo -e "  ${YELLOW}New handshakes (full TLS negotiation):${NC}"
    openssl s_time -connect 127.0.0.1:443 -new -time 10 2>/dev/null | tail -1 || echo "  (openssl s_time not available)"
    echo ""

    # Test resumed TLS handshakes (session reuse) — much cheaper
    echo -e "  ${YELLOW}Resumed handshakes (TLS session reuse):${NC}"
    openssl s_time -connect 127.0.0.1:443 -reuse -time 10 2>/dev/null | tail -1 || echo "  (openssl s_time not available)"
    echo ""

    echo -e "  ${CYAN}→ The ratio between new vs resumed shows how much CPU the SSL session cache saves.${NC}"
    echo -e "  ${CYAN}→ In production at 25k req/s, high session reuse is critical for CPU capacity.${NC}"
    echo ""
fi

# ====================================================================
# Phase 1: Warm-up (light HTTPS traffic)
# ====================================================================
echo -e "${BLUE}[PHASE 1/4]${NC} Warm-up (10 seconds, 50 connections over HTTPS)..."
wrk -t2 -c50 -d10s --timeout 5s https://127.0.0.1/ 2>/dev/null || true
echo ""

# ====================================================================
# Phase 2: Ramp-up (medium HTTPS traffic)
# ====================================================================
RAMP_CONNS=$((CONNECTIONS / 2))
echo -e "${BLUE}[PHASE 2/4]${NC} Ramp-up (15 seconds, ${RAMP_CONNS} connections over HTTPS)..."
wrk -t"$THREADS" -c"$RAMP_CONNS" -d15s --timeout 5s https://127.0.0.1/ 2>/dev/null || true
echo ""

# ====================================================================
# Phase 3: Full SSL load
# ====================================================================
echo -e "${BLUE}[PHASE 3/4]${NC} Full SSL load (${DURATION} seconds, ${CONNECTIONS} connections)..."
echo -e "  Every connection goes through full TLS handshake + HTTP request + SSL termination"
echo ""
wrk -t"$THREADS" -c"$CONNECTIONS" -d"${DURATION}s" --timeout 5s --latency https://127.0.0.1/ 2>/dev/null || true

# ====================================================================
# Phase 4: Connection storm (many short-lived TLS connections)
# ====================================================================
echo ""
echo -e "${BLUE}[PHASE 4/4]${NC} Connection storm (30 seconds — stress TIME_WAIT & handshake rate)..."
echo -e "  Short requests with no keep-alive to maximize TLS handshakes per second"
echo ""

# Use a Lua script inline to disable keep-alive, forcing new TLS handshakes
LUA_SCRIPT=$(mktemp /tmp/no-keepalive-XXXXX.lua)
cat > "$LUA_SCRIPT" << 'LUAEOF'
wrk.headers["Connection"] = "close"
LUAEOF

wrk -t"$THREADS" -c"$CONNECTIONS" -d30s --timeout 5s --latency -s "$LUA_SCRIPT" https://127.0.0.1/ 2>/dev/null || true
rm -f "$LUA_SCRIPT"

echo ""
echo "=============================================="
echo -e " ${GREEN}Load test complete!${NC}"
echo "=============================================="
echo ""
echo " Key things to check in Grafana:"
echo "  → SSL / TLS Offloading row: handshake rate, CPU cost, entropy"
echo "  → CPU row: user% spike during SSL processing"
echo "  → Network row: TCP TIME_WAIT accumulation during Phase 4"
echo "  → Nginx Proxy row: requests/sec and connection patterns"
echo ""
