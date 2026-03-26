# Monitoring an SSL Offloading Proxy

## Understanding the server

These are the server specs:

**4x Xeon E7-4830 v4 (56 cores, 112 threads)** - CPU should be able to handle SSL/TLS handshakes which are CPU-heavy (25k req/s).

**64GB RAM** - Should enough for a proxy.

**2TB HDD** - Writing logs at 25k req/s can saturate the disk, this should be well monitored.

**2x 10Gbit NICs** - The bandwith should be enough to handle operations.

---

## 1. Which metrics are interesting to monitor?

Given that this is an **SSL offloading proxy at 25k req/s**, these are the most important metrics:

**CPU** - n1 concern for SSL offloading:
- Per-core utilization 
- Breakdown by mode: user, network interrupts, disk
- Load average (should stay below core count)

**Network** - high traffic with two 10Gbit NICs:
- Bandwidth per NIC (bytes in/out)
- Packets per second (can hit limits before bandwidth)
- Packet drops and errors (silent data loss)
- TCP TIME_WAIT count (piles up fast at 25k req/s, can exhaust ephemeral ports)
- TCP retransmissions (sign of congestion or buffer issues)

**SSL/TLS** - core function of this server:
- TLS handshake rate (new vs resumed, huge CPU difference)
- Session reuse ratio
- Certificate expiry
- Handshake errors

**Disk I/O** — because HDD is the bottleneck:
- Disk utilization % (This is expected to be high just from logging)
- I/O wait time
- Free disk space

**System limits** — things that break silently at scale:
- Open file descriptors (each proxied request = 2 FDs)
- Kernel entropy pool (TLS needs randomness, can stall if depleted)

---

## 2. How would I monitor them?

**Prometheus + Grafana.** It's the industry standard for this, I have experience using this stack and it's what I used to build the demo.

```
  Client → [HTTPS] → Nginx (terminates TLS) → [HTTP] → Backend

  Monitoring:
  ├── node_exporter (:9100)        → CPU, memory, disk, network, TCP, entropy, FDs
  ├── nginx-prometheus-exporter (:9113) → connections, requests/s, connection states
  └── Prometheus (:9090)           → scrapes exporters, stores metrics, evaluates alerts
      └── Grafana (:3000)          → dashboards, visualization
```

**Why this stack:**
- `node_exporter` gives us all the system metrics from `/proc` and `/sys` with almost no overhead (standard integration with Prometheus)
- `nginx-prometheus-exporter` reads Nginx's `stub_status` for proxy-level metrics (exposes Nginx metrics in Prometheus format)
- Prometheus scrapes every 15s, this is frequent enough without adding load (Industry standard for infra monitoring)
- Grafana ties it all together visually (much better dashboards than Prometheus UI)

**Alerts I'd set up:**

| What | Threshold | Why it matters |
|------|-----------|---------------|
| CPU > 95% | Critical | SSL processing is maxed out |
| Softirq CPU > 20% | Warning | Network interrupts overloading cores |
| Any swap usage | Critical | Proxy + swap = latency disaster |
| Packet drops | Critical | Losing traffic silently |
| TIME_WAIT > 50k | Warning | Ephemeral port exhaustion risk |
| Disk utilization > 90% | Warning | HDD can't keep up with logging |
| Entropy < 200 bits | Warning | TLS handshakes could stall |
| Nginx down | Critical | — |


### Demo

I built a working version of this setup, please check [DEMO.md](./DEMO.md) for how to run it. Here's what the Grafana dashboard looks like under load:

#### Overview
![Overview](./screenshots/overview.png)

#### CPU during SSL load
![CPU](./screenshots/cpu.png)

#### Network and TCP states
![Network](./screenshots/network.png)

#### SSL/TLS offloading metrics
![SSL](./screenshots/ssl.png)

#### Nginx proxy metrics
![Nginx](./screenshots/nginx.png)


---

## 3. What are the challenges?

- **HDD is the weak link** logging 25k req/s to a spinning disk (100-200 IOPS) will saturate it. Buffered logging or shipping logs off-server is needed.

- **Monitoring costs resources too** exporters and scrapes use CPU/disk on an already busy server. Keep scrape intervals reasonable (15s) and don't collect everything.

- **Network interrupts can pile on one core** with 2x 10Gbit NICs, if IRQ affinity isn't configured, one core gets all the interrupts while the others sit idle. Only visible per-core.

- **TIME_WAIT socket buildup** at 25k req/s, closed connections stick around in TIME_WAIT for ~60s. Can exhaust ephemeral ports. `tcp_tw_reuse` helps but doesn't eliminate it.

- **SSL session cache is hard to observe** Nginx doesn't expose cache hit/miss as metrics. The only indirect data comes from log variables like `$ssl_protocol`.

- **Entropy can run low** TLS needs randomness, heavy handshake load can drain the pool. `haveged` or hardware `RDRAND` fixes it, but it should still be monitored.

- **Averages lie at scale** "2ms average" might hide a p99 of 500ms. Need percentile metrics.

- **Correlating metrics is hard** a CPU spike could be TLS handshakes, a DDoS, or a slow backend. Lining up metrics from different sources takes practice.
