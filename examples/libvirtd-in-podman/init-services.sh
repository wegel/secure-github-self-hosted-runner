#!/bin/sh

# Copy all services from /data/services to /etc/systemd/system and enable them
for service in /data/services/*.service; do
    if [ -f "$service" ]; then
        service_name=$(basename "$service")
        cp "$service" /etc/systemd/system/$service_name
        systemctl daemon-reload
        systemctl enable --now "$service_name"
    fi
done
