Decoder files go here (`talos_decoders.xml`, `osd_dashboard_decoders.xml`).
Every child decoder uses `<parent>talos-syslog</parent>` directly (no 3-level chains) and `type="pcre2"`.
