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
CYAN='\033[0;36m'
RED='\033[0;31m'
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
    echo "|    _                                                                       |"
    echo "|   | |                                                                      |"
    echo "|   | |     ___ _ __   __ _                                                  |"
    echo "|   | |    / _ \ '_ \ / _\`|                                                 |"
    echo "|   | |___|  __/ | | | (_| |                                                 |"
    echo "|   |_____/\___|_| |_|\__,_|       V1.0.3 Beta                               |"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "| Telegram Channel : ${MAGENTA}@AminiDev ${NC}| Version : ${GREEN} 1.0.3 Beta ${NC} |"
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
    echo -e "4- List tunnels"
    echo -e "0- Exit"
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
    rm -f /etc/vxlan-tunnel-*.conf
    systemctl daemon-reload
    echo -e "${GREEN}[+] All VXLAN tunnels deleted.${NC}"
}

uninstall_single_vxlan() {
    list_tunnels
    if [ $active_tunnels -eq 0 ]; then
        return
    fi
    
    read -p "Enter VNI to uninstall (0 to cancel): " VNI
    if [[ "$VNI" == "0" ]]; then
        return
    fi
    if [[ ! $VNI =~ ^[0-9]+$ ]] || (( VNI < 1 || VNI > 255 )); then
        echo -e "${RED}[x] Invalid VNI. Must be between 1-255.${NC}"
        return
    fi
    
    VXLAN_IF="vxlan${VNI}"
    
    # Load tunnel config
    CONFIG_FILE="/etc/vxlan-tunnel-${VNI}.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}[x] Tunnel VNI $VNI not found.${NC}"
        return
    fi
    
    source "$CONFIG_FILE"
    echo "[*] Removing iptables rules..."
    iptables -D INPUT -p udp --dport $DSTPORT -j ACCEPT 2>/dev/null
    iptables -D INPUT -s $REMOTE_IP -j ACCEPT 2>/dev/null
    iptables -D INPUT -s ${VXLAN_IP%/*} -j ACCEPT 2>/dev/null

    echo "[*] Stopping tunnel vxlan${VNI}..."
    systemctl stop vxlan-tunnel-${VNI}.service 2>/dev/null
    systemctl disable vxlan-tunnel-${VNI}.service 2>/dev/null
    rm -f /etc/systemd/system/vxlan-tunnel-${VNI}.service
    rm -f /usr/local/bin/vxlan_bridge_${VNI}.sh
    rm -f "$CONFIG_FILE"
    ip link del $VXLAN_IF 2>/dev/null
    systemctl daemon-reload
    echo -e "${GREEN}[✓] Tunnel vxlan${VNI} uninstalled.${NC}"
}

install_bbr() {
    echo "Running BBR script..."
    curl -fsSL https://raw.githubusercontent.com/MrAminiDev/NetOptix/main/scripts/bbr.sh -o /tmp/bbr.sh
    bash /tmp/bbr.sh
    rm /tmp/bbr.sh
}

list_tunnels() {
    active_tunnels=0
    echo -e "\n${YELLOW}Active VXLAN Tunnels:${NC}"
    echo "+-----+--------+-----------------+-----------------+----------+"
    echo -e "| ${CYAN}VNI${NC} | ${CYAN}Status${NC} | ${CYAN}Local IP${NC}     | ${CYAN}Remote IP${NC}    | ${CYAN}Port${NC}   |"
    echo "+-----+--------+-----------------+-----------------+----------+"
    
    for iface in $(ip -d link show | grep -o 'vxlan[0-9]\+' | sort -u); do
        vni=${iface#vxlan}
        status=$(ip link show $iface | grep -q 'UP' && echo -e "${GREEN}UP${NC}" || echo -e "${RED}DOWN${NC}")
        
        # Get local IP
        local_ip=$(ip addr show $iface 2>/dev/null | awk '/inet / {print $2}' | cut -d'/' -f1)
        [ -z "$local_ip" ] && local_ip="N/A"
        
        # Get remote IP and port
        remote_info=$(ip -d link show $iface 2>/dev/null | awk '/remote/ {print $3, $5}')
        remote_ip=$(echo $remote_info | awk '{print $1}')
        port=$(echo $remote_info | awk '{print $2}')
        
        # Load config if available
        CONFIG_FILE="/etc/vxlan-tunnel-${vni}.conf"
        if [ -f "$CONFIG_FILE" ]; then
            source "$CONFIG_FILE"
            remote_ip=$REMOTE_IP
            port=$DSTPORT
        fi
        
        printf "| %-3s | %-6s | %-15s | %-15s | %-8s |\n" \
               "$vni" "$status" "$local_ip" "$remote_ip" "$port"
        active_tunnels=1
    done
    
    if [ $active_tunnels -eq 0 ]; then
        echo -e "| ${RED}No active tunnels found${NC}                              |"
    fi
    echo "+-----+--------+-----------------+-----------------+----------+"
}

view_logs() {
    read -p "Enter VNI to view logs (0 to cancel): " VNI
    if [[ "$VNI" == "0" ]]; then
        return
    fi
    if [[ ! $VNI =~ ^[0-9]+$ ]] || (( VNI < 1 || VNI > 255 )); then
        echo -e "${RED}[x] Invalid VNI. Must be between 1-255.${NC}"
        return
    fi
    
    echo -e "\n${YELLOW}Last 10 log entries for tunnel $VNI:${NC}"
    journalctl -u vxlan-tunnel-${VNI}.service -n 10 --no-pager
}

# ---------------- MAIN ----------------
while true; do
    Lena_menu
    read -p "Enter your choice [0-4]: " main_action
    
    # Handle 0 to exit at any point
    if [[ "$main_action" == "0" ]]; then
        echo "Exiting..."
        exit 0
    fi
    
    case $main_action in
        1)
            break
            ;;
        2)
            while true; do
                echo -e "\n${YELLOW}Uninstall Options:${NC}"
                echo "1) Uninstall all tunnels"
                echo "2) Uninstall specific tunnel"
                echo "0) Back to main menu"
                read -p "Select option: " uninstall_opt
                
                if [[ "$uninstall_opt" == "0" ]]; then
                    break
                fi
                
                case $uninstall_opt in
                    1) 
                        uninstall_all_vxlan
                        read -p "Press Enter to continue..."
                        break
                        ;;
                    2) 
                        uninstall_single_vxlan
                        read -p "Press Enter to continue..."
                        break
                        ;;
                    *)
                        echo -e "${RED}Invalid option${NC}"
                        ;;
                esac
            done
            ;;
        3)
            install_bbr
            read -p "Press Enter to continue..."
            ;;
        4)
            list_tunnels
            if [ $active_tunnels -eq 1 ]; then
                view_logs
            fi
            read -p "Press Enter to continue..."
            ;;
        *)
            echo -e "${RED}[x] Invalid option. Try again.${NC}"
            sleep 1
            ;;
    esac
done

# Check if ip command is available
if ! command -v ip >/dev/null 2>&1; then
    echo -e "${RED}[x] iproute2 is not installed. Aborting.${NC}"
    exit 1
fi

# ------------- VARIABLES --------------
read -p "Enter unique VNI number (1-255, 0 to cancel): " VNI
if [[ "$VNI" == "0" ]]; then
    exit 0
fi
while [[ ! $VNI =~ ^[0-9]+$ ]] || (( VNI < 1 || VNI > 255 )); do
    echo -e "${RED}Invalid VNI. Must be between 1-255.${NC}"
    read -p "Enter unique VNI number (1-255, 0 to cancel): " VNI
    if [[ "$VNI" == "0" ]]; then
        exit 0
    fi
done

VXLAN_IF="vxlan${VNI}"

# --------- Choose Server Role ----------
echo "Choose server role:"
echo "1- Iran"
echo "2- Kharej"
echo "0- Cancel"
read -p "Enter choice (0-2): " role_choice

if [[ "$role_choice" == "0" ]]; then
    exit 0
elif [[ "$role_choice" == "1" ]]; then
    read -p "Enter IRAN IP: " IRAN_IP
    read -p "Enter Kharej IP: " KHAREJ_IP

    # Port validation loop
    while true; do
        read -p "Tunnel port (1 ~ 64435, 0 to cancel): " DSTPORT
        if [[ "$DSTPORT" == "0" ]]; then
            exit 0
        fi
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
        read -p "Tunnel port (1 ~ 64435, 0 to cancel): " DSTPORT
        if [[ "$DSTPORT" == "0" ]]; then
            exit 0
        fi
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
    echo -e "${RED}[x] Invalid role selected.${NC}"
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
iptables -I INPUT -p udp --dport $DSTPORT -j ACCEPT
iptables -I INPUT -s $REMOTE_IP -j ACCEPT
iptables -I INPUT -s ${VXLAN_IP%/*} -j ACCEPT

# Save tunnel config
CONFIG_FILE="/etc/vxlan-tunnel-${VNI}.conf"
echo "DSTPORT=$DSTPORT" > $CONFIG_FILE
echo "REMOTE_IP=$REMOTE_IP" >> $CONFIG_FILE
echo "VXLAN_IP=$VXLAN_IP" >> $CONFIG_FILE

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
