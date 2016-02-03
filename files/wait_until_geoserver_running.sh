#!/bin/bash

for ((i=0;i<24;i++)); do
    wget -q -o /dev/null -O /dev/null  http://127.0.0.1:8080/geoserver
    if [ $? -eq 0 ]; then
        echo "Geoserver is running."
        exit 0
    fi
    sleep 5
done
echo "Geoserver is not running."
exit 1
