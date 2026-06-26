#!/bin/bash

DATA_DIR="/root/bandwidth"
PORTS_FILE="$DATA_DIR/ports.txt"
CONFIG_DIR="/root/rgt-core"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

colorize() {
    local color=$1
    local message=$2
    local bold=$3
    [[ "$bold" == "bold" ]] && local bold_flag="\033[1m"
    echo -e "${bold_flag}${!color}${message}${NC}"
}

# Ensure data directory and ports file exist
mkdir -p "$DATA_DIR"
touch "$PORTS_FILE"

# Function to check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        colorize red "This script must be run as root"
        exit 1
    fi
}

# Function to save port to monitor
save_port() {
    local port=$1
    local proto=$2
    grep -q "^$port $proto$" "$PORTS_FILE" || echo "$port $proto" >> "$PORTS_FILE"
}

# Function to install monitor service
install() {
    check_root
    colorize cyan "Installing RGT Port Monitor..." bold
    if [[ ! -s "$PORTS_FILE" ]]; then
        colorize red "No ports to monitor. Please add ports using 'addport' command."
        exit 1
    fi
    create_service
    systemctl daemon-reload
    systemctl enable rgt-port-monitor.service
    systemctl restart rgt-port-monitor.service
    colorize green "Installation complete. Monitoring started."
}

# Function to add a port to monitor
add_port() {
    check_root
    local port=$1
    local proto=$2
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 23 ] || [ "$port" -gt 65535 ]; then
        colorize red "Invalid port number. Must be between 23-65535."
        exit 1
    fi
    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        colorize red "Invalid protocol. Must be 'tcp' or 'udp'."
        exit 1
    fi
    save_port "$port" "$proto"
    iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT
    iptables -C OUTPUT -p "$proto" --sport "$port" -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p "$proto" --sport "$port" -j ACCEPT
    colorize green "Port $port ($proto) added."
}

# Function to show bandwidth usage for a specific port
show_port() {
    check_root
    local port=$1
    local proto=$2
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 23 ] || [ "$port" -gt 65535 ]; then
        colorize red "Invalid port number. Must be between 23-65535."
        exit 1
    fi
    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        colorize red "Invalid protocol. Must be 'tcp' or 'udp'."
        exit 1
    fi
    local usage_file="$DATA_DIR/port_${port}_${proto}_usage.txt"
    if [[ -f "$usage_file" ]]; then
        read saved_rx saved_tx < "$usage_file"
        rx_bytes=$(iptables -L -v -n -x | grep "$proto.*dpt:$port" | awk '{sum+=$2} END {print sum+0}')
        tx_bytes=$(iptables -L -v -n -x | grep "$proto.*spt:$port" | awk '{sum+=$2} END {print sum+0}')
        total_rx=$((saved_rx + rx_bytes))
        total_tx=$((saved_tx + tx_bytes))
        colorize green "Bandwidth usage for port $port ($proto):"
        colorize green "$(printf "Received: %.2f MB" "$(echo "$total_rx / 1024 / 1024" | bc -l)")"
        colorize green "$(printf "Transmitted: %.2f MB" "$(echo "$total_tx / 1024 / 1024" | bc -l)")"
    else
        colorize red "No bandwidth data found for port $port ($proto)."
    fi
}

# Function to reset all usage data
reset_all_usage() {
    check_root
    for f in "$DATA_DIR"/port_*_usage.txt; do
        [ -f "$f" ] && echo "0 0" > "$f"
    done
    colorize green "All usage data reset."
}

# Function to reset usage for a specific port
reset_port_usage() {
    check_root
    local port=$1
    local proto=$2
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 23 ] || [ "$port" -gt 65535 ]; then
        colorize red "Invalid port number. Must be between 23-65535."
        exit 1
    fi
    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        colorize red "Invalid protocol. Must be 'tcp' or 'udp'."
        exit 1
    fi
    local usage_file="$DATA_DIR/port_${port}_${proto}_usage.txt"
    if grep -q "^$port $proto$" "$PORTS_FILE"; then
        # Stop any process locking the file
        sudo pkill -f "rgt-port-monitor.sh.*port_${port}_${proto}_usage.txt" 2>/dev/null
        # Ensure file is writable
        if [[ -f "$usage_file" ]]; then
            sudo chmod 644 "$usage_file" 2>/dev/null
            echo "0 0" | sudo tee "$usage_file" > /dev/null
            if [[ $? -eq 0 ]]; then
                colorize green "Bandwidth usage for port $port ($proto) reset successfully."
            else
                colorize red "Failed to reset bandwidth usage for port $port ($proto)."
            fi
        else
            colorize yellow "Bandwidth file $usage_file not found, creating it."
            sudo mkdir -p "$DATA_DIR"
            echo "0 0" | sudo tee "$usage_file" > /dev/null
            sudo chmod 644 "$usage_file" 2>/dev/null
            colorize green "Bandwidth usage for port $port ($proto) reset successfully."
        fi
    else
        colorize red "Port $port ($proto) is not being monitored."
        exit 1
    fi
}

# Function to remove a monitored port
remove_port() {
    check_root
    local port=$1
    local proto=$2
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 23 ] || [ "$port" -gt 65535 ]; then
        colorize red "Invalid port number. Must be between 23-65535."
        exit 1
    fi
    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        colorize red "Invalid protocol. Must be 'tcp' or 'udp'."
        exit 1
    fi
    if grep -q "^$port $proto$" "$PORTS_FILE"; then
        sed -i "/^$port $proto$/d" "$PORTS_FILE"
        rm -f "$DATA_DIR/port_${port}_${proto}_usage.txt"
        iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
        iptables -D OUTPUT -p "$proto" --sport "$port" -j ACCEPT 2>/dev/null
        colorize green "Port $port ($proto) removed."
    else
        colorize red "Port $port ($proto) is not being monitored."
        exit 1
    fi
}

# Function to uninstall monitor service
uninstall() {
    check_root
    colorize red "Uninstalling RGT Port Monitor..." bold
    while read -r port proto; do
        remove_port "$port" "$proto"
    done < "$PORTS_FILE"
    rm -f /etc/systemd/system/rgt-port-monitor.service
    systemctl daemon-reload
    rm -rf "$DATA_DIR"
    colorize green "Uninstalled."
}

# Function to run monitor loop
run_monitor_loop() {
    check_root
    while true; do
        while read -r port proto; do
            usage_file="$DATA_DIR/port_${port}_${proto}_usage.txt"
            [ -f "$usage_file" ] || echo "0 0" > "$usage_file"
            read saved_rx saved_tx < "$usage_file"
            rx_bytes=$(iptables -L -v -n -x | grep "$proto.*dpt:$port" | awk '{sum+=$2} END {print sum+0}')
            tx_bytes=$(iptables -L -v -n -x | grep "$proto.*spt:$port" | awk '{sum+=$2} END {print sum+0}')
            echo "$((saved_rx + rx_bytes)) $((saved_tx + tx_bytes))" > "$usage_file"
        done < "$PORTS_FILE"
        iptables -Z
        sleep 10
    done
}

# Function to create systemd service
create_service() {
    cat <<EOF > /etc/systemd/system/rgt-port-monitor.service
[Unit]
Description=RGT Port Monitor
After=network.target

[Service]
ExecStart=/bin/bash ${CONFIG_DIR}/tools/rgt-port-monitor.sh run
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

# Main execution
case "$1" in
    install) install ;;
    addport) add_port "$2" "$3" ;;
    show_port) show_port "$2" "$3" ;;
    reset) reset_all_usage ;;
    resetport) reset_port_usage "$2" "$3" ;;
    removeport) remove_port "$2" "$3" ;;
    uninstall) uninstall ;;
    run) run_monitor_loop ;;
    *)
        colorize red "Usage:"
        colorize red "  rgt-port-monitor.sh install                     # Install and setup the monitor service"
        colorize red "  rgt-port-monitor.sh addport <port> <tcp|udp>   # Add a port to monitor"
        colorize red "  rgt-port-monitor.sh show_port <port> <tcp|udp> # Show usage for specific port"
        colorize red "  rgt-port-monitor.sh reset                       # Reset all usage data"
        colorize red "  rgt-port-monitor.sh resetport <port> <tcp|udp>  # Reset specific port"
        colorize red "  rgt-port-monitor.sh removeport <port> <tcp|udp> # Remove specific port"
        colorize red "  rgt-port-monitor.sh uninstall                   # Remove service and iptables rules"
        colorize red "  rgt-port-monitor.sh run                         # Run monitor loop (used by systemd service)"
        exit 1
        ;;
esac
