# Sample logs

Sanitized lines captured from live Talos syslog traffic. Paste a line into `wazuh-logtest` on the manager to check decoding.

| File | Expected decoder |
|---|---|
| `argocd.log` | `talos-argocd` |
| `kafka.log` | `talos-kafka` |
| `kube-apiserver.log` | `talos-kube-apiserver` (also triggers rule `100101`) |
| `mqtt-activities.log` | `talos-mqtt-activities` |
| `pgbouncer.log` | line 1 `talos-pgbouncer-login`; line 2 fallback `talos-syslog-fields` (unix-socket access, not covered) |
| `postgres.log` | `talos-postgres-json` |
| `prometheus.log` | `talos-prometheus` |
| `redis.log` | `talos-redis` |
| `kube-network-policies.log` | line 1 `talos-network-policy-egress-limited`; line 2 `talos-network-policy-tuple` (`srcip`/`dstip`/`dstport`); line 3 `talos-network-policy-port-denied` → rule `100109` |
| `opensearch-dashboards.log` | `osd-dashboard-log` (journald, not Talos syslog) |

IPs use documentation ranges (192.0.2.0/24, 198.51.100.0/24). Hostnames, namespaces, and DB users are placeholders.
