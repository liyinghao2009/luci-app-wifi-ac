#!/bin/sh
[ -d /tmp/wifi-ac ] || mkdir -p /tmp/wifi-ac   # 修复点
while true; do
  ubus call wifi_data get_status > /tmp/wifi_status.json
  sqlite3 /etc/wifi-ac/data.db "
    INSERT INTO trends (mac, timestamp, load, signal)
    VALUES (
      '$(uci get wifi-ac.master_ap)',
      $(date +%s),
      $(jq .load /tmp/wifi_status.json),
      $(jq .signal /tmp/wifi_status.json)
    )
  "
  sleep 30
done
