# wazuh-talos-linux

[![validate](https://github.com/ranatalha4/wazuh-talos-linux/actions/workflows/validate.yml/badge.svg)](https://github.com/ranatalha4/wazuh-talos-linux/actions/workflows/validate.yml)
![Wazuh](https://img.shields.io/badge/Wazuh-4.14.7-005571?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

Wazuh decoders, rules and field notes for monitoring **Talos Linux / Kubernetes** nodes **agentlessly over syslog**.

Talos has no shell and no package manager, so the Wazuh agent can't be installed. This repo covers the syslog path instead, plus the parsing traps that make decoders fail silently.

**Tested on:** Wazuh 4.14.7 (manager + indexer on AlmaLinux).

---

## Architecture

```text
Talos nodes (no agent)
   |  syslog, TCP 514
   v
Wazuh Manager  ── decoders/ + rules/
   |
   v
Wazuh Indexer (ISM retention policy)
   |
   v
Wazuh Dashboard
```

## Repo layout

| Path | Contents |
|---|---|
| `decoders/talos_decoders.xml` | Parent `talos-syslog` + 26 children (network policies incl. packet 5-tuple → `srcip`/`dstip`, Grafana, Kafka, kube-apiserver, Prometheus stack, MQTT, Redis, Traefik, Argo CD, PgBouncer, PostgreSQL JSON) + fallback |
| `decoders/osd_dashboard_decoders.xml` | OpenSearch Dashboards request/log decoders |
| `rules/talos_rules.xml` | Detection rules `100100–100153` |
| `rules/wazuh_health_rules.xml` | `/var/ossec` disk ≥ 85% alert (`100120`) |
| `config/ossec-remote-syslog.xml` | `<remote>` block for receiving Talos syslog |
| `config/ism-retention-policy.json` | Index retention for `wazuh-alerts-*` / `wazuh-archives-*` |
| `scripts/baseline-flows.sh` | Build a flow baseline from `archives.json` (awk only, no Python) |
| `scripts/leak-check.sh` | Pre-commit check for IPs, hostnames and credentials |
| `samples/` | Sanitized sample logs for `wazuh-logtest` |

---

## Detections

| Rule | Level | Detects | MITRE |
|---|---|---|---|
| 100102 | 10 | 50+ etcd connection errors in 5 min on one node | T1499 |
| 100107 | 8 | Traefik request from outside allow-listed CIDRs | T1133 |
| 100108 | 8 | 300+ network-policy drops in 60 s on one node | T1046 |
| 100110 | 7 | 20+ egress-port denials in 60 s from one pod | T1046 |
| 100111 | 10 | Pod denied egress to a control-plane/node port (etcd, apiserver, kubelet, Talos API, SSH) | T1613, T1210 |
| 100132 | 8 | PgBouncer login from a non-cluster IP | T1078 |
| 100133 | 8 | PgBouncer login with an unexpected DB user | T1078 |
| 100135 | 10 | 5+ PgBouncer auth failures in 60 s from one IP | T1110.001 |
| 100142 | 12 | PostgreSQL superuser login over the network | T1078.003 |
| 100143 | 10 | PostgreSQL login by an unknown user | T1078 |
| 100144/45 | 8 | App user touching an unexpected database | T1078 |
| 100147 | 12 | 5+ PostgreSQL failed logins in 2 min | T1110 |
| 100148 | 8 | DDL (`CREATE/ALTER/DROP/TRUNCATE`) | T1565.001 |
| 100150/52 | 10 | Role/privilege changes (statement log + pgaudit) | T1098 |
| 100153 | 5 | PostgreSQL restart / config reload | n/a |

Level-0 rules (`100100`, `100104`, `100106`, `100131`, `100149` …) are base classifiers and noise suppressors.

PostgreSQL rules expect CloudNativePG JSON logs, `log_statement=ddl`, and pgaudit for `100152`.

---

## Install

### Step 1 — Receive syslog

**Run on the Wazuh Manager:**

```bash
sudo cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak
sudo vi /var/ossec/etc/ossec.conf
```

Add the block from [`config/ossec-remote-syslog.xml`](config/ossec-remote-syslog.xml) inside `<ossec_config>`, then set `allowed-ips` to your node subnets.

### Step 2 — Install decoders and rules

**Run on the Wazuh Manager:**

```bash
sudo cp /var/ossec/etc/decoders/local_decoder.xml /var/ossec/etc/decoders/local_decoder.xml.bak
sudo cp /var/ossec/etc/rules/local_rules.xml /var/ossec/etc/rules/local_rules.xml.bak
sudo cp decoders/*.xml /var/ossec/etc/decoders/
sudo cp rules/*.xml /var/ossec/etc/rules/
sudo chown wazuh:wazuh /var/ossec/etc/decoders/*.xml /var/ossec/etc/rules/*.xml
```

### Step 3 — Validate before restarting

**Run on the Wazuh Manager:**

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Paste a line from `samples/`. You should see the expected fields extracted and the expected rule ID fire.

### Step 4 — Reload

> ⚠️ This interrupts alert processing briefly.

**Run on the Wazuh Manager:**

```bash
sudo systemctl stop wazuh-manager && sudo systemctl start wazuh-manager
```

Use stop + start rather than `restart`; see the gotchas below.

### Step 5 — Verify on live traffic

**Run on the Wazuh Manager** (needs `logall_json` on temporarily):

```bash
sudo tail -n 300000 /var/ossec/logs/archives/archives.json | grep -c '"talos_data"'
```

The count should fall to near zero for covered services. Anything left over is a log shape that no child decoder matches yet.

---

## Gotchas (the reason this repo exists)

| # | Problem | Fix |
|---|---|---|
| 1 | **Talos prepends a UTF-8 BOM** (`EF BB BF`) to every message body after the RFC5424 `- -` separator. Decoders fail silently. | Start PCRE2 patterns with `(?:\xEF\xBB\xBF)?` |
| 2 | `hostname` and `program_name` are **reserved fields**. Custom values get overwritten without an error. | Use prefixed names: `talos_host`, `talos_program` |
| 3 | Decoders are **first-match, not best-match**. | Put specific children before greedy fallbacks |
| 4 | The default OSRegex engine has **no interval quantifiers** (`\d{4}`). | Set `type="pcre2"` on **both** `prematch` and `regex` |
| 5 | 3-level chains with `use_own_name` give the error *parent decoder name invalid*. | Flatten: every child points directly at one parent |
| 6 | Rule `<match>` has **no regex**. | Use `<field name="x" type="pcre2">` |
| 7 | `decoded_as` has to match the name Wazuh **reports at runtime**, which can differ from the declared name. | Check it in `wazuh-logtest` first |
| 8 | `decoder.name` can show the **parent** even when a child matched. | Validate by **field shape**: extracted fields present, fallback field absent |
| 9 | `systemctl restart` was observed to keep **stale decoder/rule definitions**. | `stop` then `start` |
| 10 | `logall_json` used for decoder work **fills the disk fast**. | Turn it on only temporarily, put `/var/ossec` on its own volume, and set index retention |
| 11 | `<field name="dstport">` (or any **static** field: `srcip`, `dstip`, `srcport`, `dstport`, `srcuser`…) is **rejected on save**. | Use the dedicated option, e.g. `<dstport>` |
| 12 | Static-field options like `<dstport>` matched `\d` **literally** in testing. | Use literals with `^…$\|` alternation, or check the value in a regex `<field>` on a dynamic field |
| 13 | At high klog verbosity, `kube-network-policies` dumps every packet as **6–8 syslog lines** (header, `[id]` tuple, hex, `>`). Wazuh can't join them by `id`. | Lower the verbosity at source; alert from single self-contained lines |

---

## Retention policy

**Run on the Wazuh Indexer:**

```bash
curl -k -u admin -X PUT "https://localhost:9200/_plugins/_ism/policies/wazuh-retention" \
  -H 'Content-Type: application/json' -d @config/ism-retention-policy.json
```

`ism_template` only attaches the policy to **new** indices. To attach it to existing ones:

```bash
curl -k -u admin -X POST "https://localhost:9200/_plugins/_ism/add/wazuh-alerts-*,wazuh-archives-*" \
  -H 'Content-Type: application/json' -d '{"policy_id":"wazuh-retention"}'
```

Change `min_index_age` (default `3d`) to match your retention requirement.

---

## Workflow used per service

```text
decoder audit → sample logs → wazuh-logtest → live field-shape check
      → traffic baseline → rule writing → tune noise (level 0 suppressors)
```

## License

MIT
