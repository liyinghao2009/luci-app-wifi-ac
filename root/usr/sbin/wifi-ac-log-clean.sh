#!/bin/sh
# 清理7天前的wifi-ac日志（可crontab调用）

LOG_DIR="/var/log/wifi-ac"
KEEP_DAYS=7

find "$LOG_DIR" -type f -name "*.log" -mtime +$KEEP_DAYS -delete
