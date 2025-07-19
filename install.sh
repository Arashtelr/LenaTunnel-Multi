#!/bin/bash

# ---------------- INSTALL DEPENDENCIES ----------------
echo "[*] Installing prerequisites (iproute2, net-tools, grep, awk, jq, curl)..."
sudo apt update -y >/dev/null 2>&1
sudo apt install -y iproute2 net-tools grep awk sudo iputils-ping jq curl >/dev/null 2>&1
sudo apt-get install -y jq

# ---------------- COLORS ----------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ---------------- FUNCTIONS ----------------

check_core_status() {
    ip link show | grep -q 'vxlan' && echo "Active" || echo "Inactive"
}

Lena_menu() {
    clear
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')

    echo "+-----------------------------------------------------------------------------+"
    echo "| _                      										|"
    echo "|| |                     										|"
    echo "|| |     ___ _ __   __ _ 										|"
    echo "|| |    / _ \ '_ \ / _  |										|"
    echo "|| |___|  __/ | | | (_| |										|"
    echo "|\_____/\___|_| |_|\__,_|	V1.0.2 Beta				            |" 
    echo "+-----------------------------------------------------------------------------+"    
    echo -e "| Telegram Channel : ${MAGENTA}@AminiDev ${NC}| Version : ${GREEN} 1.0.2 Beta ${NC} "
    echo "+-----------------------------------------------------------------------------+"      
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "1- Install new tunnel"
    echo -e "2- Uninstall tunnel(s)"
    echo -e "3- Install BBR"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "\033[0m"
}

uninstall_all_vxlan() {
    echo "[!] Deleting all VXLAN interfaces and cleaning up..."
    for i in $(ip -d link show | grep -o 'vxlan[0-9]\+'); do
        ip link del $i 2>/dev/null
    done
    rm -f /usr/local/bin/vxlan_bridge_*.sh
    find /etc/systemd/system/ -name 'vxlan-tunnel-*.service' -exec rm -f {} \;
    systemctl daemon-reload
    echo "[+] All VXLAN tunnels deleted."
}

install_bbr() {
    echo "Running BBR script..."
    curl -fsSL https://raw.githubusercontent.com/MrAminiDev/NetOptix/main/scripts/bbr.sh -o /tmp/bbr.sh
    bash /tmp/bbr.sh
    rm /tmp/bbr.sh
}

# ---------------- MAIN ----------------
while true; do
    Lena_menu
    read -p "Enter your choice [1-3]: " main_action
    case $main_action in
        1)
            break
            ;;
        2)
            uninstall_all_vxlan
            read -p "Press Enter to return to menu..."
            ;;
        3)
            install_bbr
            read -p "Press Enter to return to menu..."
            ;;
        *)
            echo "[x] Invalid option. Try again."
            sleep 1
            ;;
    esac
done

# Check if ip command is available
if ! command -v ip >/dev/null 2>&1; then
    echo "[x] iproute2 is not installed. Aborting."
    exit 1
fi

# ------------- VARIABLES --------------
read -p "Enter unique VNI number (1-255): " VNI
while [[ ! $VNI =~ ^[0-9]+$ ]] || (( VNI < 1 || VNI > 255 )); do
    echo "Invalid VNI. Must be between 1-255."
    read -p "Enter unique VNI number (1-255): " VNI
done

VXLAN_IF="vxlan${VNI}"

# --------- Choose Server Role ----------
echo "Choose server role:"
echo "1- Iran"
echo "2- Kharej"
read -p "Enter choice (1/2): " role_choice

if [[ "$role_choice" == "1" ]]; then
    read -p "Enter IRAN IP: " IRAN_IP
    read -p "Enter Kharej IP: " KHAREJ_IP

    # Port validation loop
    while true; do
        read -p "Tunnel port (1 ~ 64435): " DSTPORT
        if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
            break
        else
            echo "Invalid port. Try again."
        fi
    done

    VXLAN_IP="30.0.${VNI}.1/24"
    REMOTE_IP=$KHAREJ_IP
    echo "IRAN Server setup complete."
    echo -e "####################################"
    echo -e "# Your IPv4 :                      #"
    echo -e "#  30.0.${VNI}.1                   #"
    echo -e "####################################"

elif [[ "$role_choice" == "2" ]]; then
    read -p "Enter IRAN IP: " IRAN_IP
    read -p "Enter Kharej IP: " KHAREJ_IP

    # Port validation loop
    while true; do
        read -p "Tunnel port (1 ~ 64435): " DSTPORT
        if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
            break
        else
            echo "Invalid port. Try again."
        fi
    done

    VXLAN_IP="30.0.${VNI}.2/24"
    REMOTE_IP=$IRAN_IP
    echo "Kharej Server setup complete."
    echo -e "####################################"
    echo -e "# Your IPv4 :                      #"
    echo -e "#  30.0.${VNI}.2                  #"
    echo -e "####################################"

else
    echo "[x] Invalid role selected."
    exit 1
fi

# Detect default interface
INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
echo "Detected main interface: $INTERFACE"

# ------------ Setup VXLAN --------------
echo "[+] Creating VXLAN interface..."
ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning

echo "[+] Assigning IP $VXLAN_IP to $VXLAN_IF"
ip addr add $VXLAN_IP dev $VXLAN_IF
ip link set $VXLAN_IF up

echo "[+] Adding iptables rules"
iptables -I INPUT 1 -p udp --dport $DSTPORT -j ACCEPT
iptables -I INPUT 1 -s $REMOTE_IP -j ACCEPT
iptables -I INPUT 1 -s ${VXLAN_IP%/*} -j ACCEPT

# ---------------- CREATE SYSTEMD SERVICE ----------------
echo "[+] Creating systemd service for VXLAN..."

cat <<EOF > /usr/local/bin/vxlan_bridge_${VNI}.sh
#!/bin/bash
ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning
ip addr add $VXLAN_IP dev $VXLAN_IF
ip link set $VXLAN_IF up
EOF

chmod +x /usr/local/bin/vxlan_bridge_${VNI}.sh

cat <<EOF > /etc/systemd/system/vxlan-tunnel-${VNI}.service
[Unit]
Description=VXLAN Tunnel Interface (VNI $VNI)
After=network.target

[Service]
ExecStart=/usr/local/bin/vxlan_bridge_${VNI}.sh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/vxlan-tunnel-${VNI}.service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable vxlan-tunnel-${VNI}.service
systemctl start vxlan-tunnel-${VNI}.service

echo -e "\n${GREEN}[✓] VXLAN tunnel service enabled to run on boot.${NC}"
echo "[✓] VXLAN tunnel setup completed successfully."
