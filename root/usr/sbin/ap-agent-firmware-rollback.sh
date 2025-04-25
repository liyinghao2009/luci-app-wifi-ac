#!/bin/sh
# /usr/sbin/firmware_rollback.sh

if [ "$(uci get firmware.status)" = "failed" ]; then
  cp /firmware/backup.bin /firmware/current.bin
  reboot
fi
