#!/bin/bash

# ... [rest of the script remains the same until the service creation section] ...

# ---------------- CREATE SYSTEMD SERVICE ----------------
echo "[+] Creating systemd service for VXLAN..."

cat <<EOF > /usr/local/bin/vxlan_bridge_${VNI}.sh
#!/bin/bash
# Cleanup any existing interface
if ip link show $VXLAN_IF &>/dev/null; then
    echo "[*] Removing existing VXLAN interface $VXLAN_IF"
    ip link del $VXLAN_IF 2>/dev/null
    sleep 1
fi

echo "[*] Creating VXLAN interface $VXLAN_IF"
ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning || {
    echo "[x] Failed to create VXLAN interface"
    exit 1
}

echo "[*] Assigning IP $VXLAN_IP to $VXLAN_IF"
ip addr add $VXLAN_IP dev $VXLAN_IF || {
    echo "[x] Failed to assign IP address"
    exit 1
}

echo "[*] Bringing up $VXLAN_IF"
ip link set $VXLAN_IF up || {
    echo "[x] Failed to bring up interface"
    exit 1
}

echo "[✓] VXLAN interface $VXLAN_IF created successfully"

# Keep the script running to maintain the service
sleep infinity
EOF

chmod +x /usr/local/bin/vxlan_bridge_${VNI}.sh

cat <<EOF > /etc/systemd/system/vxlan-tunnel-${VNI}.service
[Unit]
Description=VXLAN Tunnel Interface (VNI $VNI)
After=network.target
Requires=network.target

[Service]
Type=simple
ExecStart=/bin/bash /usr/local/bin/vxlan_bridge_${VNI}.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/vxlan-tunnel-${VNI}.service
systemctl daemon-reload

# Clear logs ONLY for this specific tunnel service
echo "[*] Clearing existing logs for tunnel $VNI..."
journalctl --unit=vxlan-tunnel-${VNI}.service --rotate
journalctl --unit=vxlan-tunnel-${VNI}.service --vacuum-time=1s >/dev/null 2>&1

# Enable and start the service
systemctl enable --now vxlan-tunnel-${VNI}.service

# Verify service status
if systemctl is-active --quiet vxlan-tunnel-${VNI}.service; then
    echo -e "\n${GREEN}[✓] VXLAN tunnel service is running${NC}"
    
    # Wait for logs to be generated
    sleep 2
    
    # Show last 10 logs
    echo -e "\n${YELLOW}Last 10 log entries for tunnel $VNI:${NC}"
    journalctl -u vxlan-tunnel-${VNI}.service -n 10 --no-pager
else
    echo -e "\n${RED}[x] Service failed to start${NC}"
    journalctl -u vxlan-tunnel-${VNI}.service -n 10 --no-pager
    exit 1
fi

echo -e "${GREEN}[✓] VXLAN tunnel setup completed successfully.${NC}"
