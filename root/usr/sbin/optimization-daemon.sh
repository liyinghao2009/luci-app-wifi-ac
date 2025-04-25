#!/bin/sh

QUEUE="/tmp/wifi-ac/optimization_queue.json"

process_queue() {
    lua -e "require('luci.model.wifi_ac').process_optimization_queue()"
}

while true; do
    process_queue
    sleep 5
done
