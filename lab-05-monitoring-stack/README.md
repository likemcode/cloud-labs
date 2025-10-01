# Lab 05: Monitoring Stack

## Objective

Observability isn't optional. You can't fix what you can't see. This lab sets up a full monitoring stack with Prometheus for metrics, Grafana for visualization, and Alertmanager for notifications. The goal is to understand the RED method (Rate, Errors, Duration) and USE method (Utilization, Saturation, Errors).

## What I Learned

### The "aha moment"

I thought my API was fast. Average response time was 50ms. Then I looked at p99 in Grafana and it was 2.3 seconds. A bad database query was causing tail latency that I never would have noticed without percentile metrics. Average lies. Always look at percentiles.

### PromQL is its own language

`rate()` vs `increase()` confused me. `rate()` gives you per-second average rate of increase --- use this for graphing. `increase()` gives the total increase over the time window --- use this for "how many requests in the last hour." Both only work on counters. For gauges (current values like CPU%), just use the metric directly.

### Alert fatigue is real

My first alert rules fired constantly. CPU > 50%? That's normal on a laptop. The `for` clause is essential --- it means "only fire if the condition has been true for this long." 5 minutes is a good minimum for non-critical alerts. Also: group related alerts in Alertmanager so you get one Slack message instead of 50.

## Stack

| Component | Port | Purpose |
|-----------|------|---------|
| Prometheus | 9090 | Metrics collection & querying |
| Grafana | 3000 | Dashboards & visualization |
| Alertmanager | 9093 | Alert routing & notification |
| Node Exporter | 9100 | Host metrics (CPU, memory, disk) |

## Running

```bash
docker compose up -d
# Grafana: http://localhost:3000 (admin/admin)
# Prometheus: http://localhost:9090
# Alertmanager: http://localhost:9093
```
