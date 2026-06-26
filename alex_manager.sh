#!/bin/bash

# ╔══════════════════════════════════════════════════════════╗
# ║                  ALEX TUNNEL MANAGER                    ║
# ║                  Version: 1.2.1                         ║
# ║              github.com/Alextaylorvhjnf                 ║
# ╚══════════════════════════════════════════════════════════╝

if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m╔════════════════════════════════════════════╗\033[0m"
    echo -e "\033[0;31m║  This script must be run as root!         ║\033[0m"
    echo -e "\033[0;31m╚════════════════════════════════════════════╝\033[0m"
    sleep 1
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

CONFIG_DIR="/root/alex-core"
SERVICE_DIR="/etc/systemd/system"
ALEX_BIN="${CONFIG_DIR}/alex"
SCRIPT_PATH="/usr/local/bin/ALEX"
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"

press_key() {
    echo
    read -rp "$(echo -e ${CYAN}Press any key to continue...${NC})"
}

show_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

show_error() {
    echo -e "${RED}❌ $1${NC}"
}

show_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

show_progress() {
    echo -e "${CYAN}⏳ $1...${NC}"
}

detect_network_interface() {
    local interface=$(ip link | grep -E '^[0-9]+: (eth[0-9]+|ens[0-9]+)' | awk '{print $2}' | cut -d':' -f1 | head -n 1)
    if [[ -z "$interface" ]]; then
        show_error "No network interface found."
        press_key
        exit 1
    fi
    echo "$interface"
}

install_dependencies() {
    local deps=("unzip" "jq" "curl" "iproute2" "bridge-utils" "haproxy")
    local missing=()
    
    for dep in unzip jq curl; do
        if ! command -v $dep &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if ! command -v ip &> /dev/null; then
        missing+=("iproute2")
    fi
    if ! command -v brctl &> /dev/null; then
        missing+=("bridge-utils")
    fi
    if ! command -v haproxy &> /dev/null; then
        missing+=("haproxy")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}📦 Installing dependencies: ${missing[*]}...${NC}"
        apt-get update -qq
        for pkg in "${missing[@]}"; do
            apt-get install -y -qq "$pkg" || {
                show_error "Failed to install $pkg"
                press_key
                exit 1
            }
        done
        show_success "Dependencies installed"
    fi
}

manual_download_instructions() {
    clear
    echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║     Failed to download ALEX core from GitHub            ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}📋 Manual Installation Steps:${NC}"
    echo
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${CYAN}Step 1:${NC} Download file from:"
    echo -e "${GREEN}https://github.com/Alextaylorvhjnf/ALEX-Tunnel/raw/main/core/ALEX-x86-64-linux.zip${NC}"
    echo
    echo -e "${CYAN}Step 2:${NC} Upload to server via SFTP to /root/"
    echo
    echo -e "${CYAN}Step 3:${NC} Run these commands:"
    echo
    echo -e "${YELLOW}  mkdir -p /root/alex-core${NC}"
    echo -e "${YELLOW}  unzip /root/ALEX-x86-64-linux.zip -d /root/alex-core${NC}"
    echo -e "${YELLOW}  mv /root/alex-core/rgt /root/alex-core/alex${NC}"
    echo -e "${YELLOW}  chmod +x /root/alex-core/alex${NC}"
    echo -e "${YELLOW}  rm /root/ALEX-x86-64-linux.zip${NC}"
    echo
    echo -e "${CYAN}Step 4:${NC} Re-run script with: ${GREEN}ALEX${NC}"
    echo
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    press_key
    exit 1
}

validate_zip_file() {
    local zip_file="$1"
    if [[ ! -f "$zip_file" ]]; then
        return 1
    fi
    if ! file "$zip_file" | grep -q "Zip archive data"; then
        return 1
    fi
    if [[ $(stat -c %s "$zip_file") -lt 1000 ]]; then
        return 1
    fi
    return 0
}

download_and_extract_alex() {
    if [[ -f "${ALEX_BIN}" ]] && [[ -x "${ALEX_BIN}" ]]; then
        show_success "ALEX core is already installed"
        sleep 1
        return 0
    fi
    
    DOWNLOAD_URL="https://raw.githubusercontent.com/Alextaylorvhjnf/ALEX-Tunnel/main/core/ALEX-x86-64-linux.zip"
    DOWNLOAD_DIR=$(mktemp -d)
    ZIP_FILE="$DOWNLOAD_DIR/alex.zip"
    
    echo -e "${CYAN}🌐 Downloading ALEX core...${NC}"
    echo
    
    if ! curl -sSL --connect-timeout 10 -o "$ZIP_FILE" "$DOWNLOAD_URL" 2>/dev/null; then
        rm -rf "$DOWNLOAD_DIR"
        manual_download_instructions
    fi
    
    if ! validate_zip_file "$ZIP_FILE"; then
        rm -rf "$DOWNLOAD_DIR"
        manual_download_instructions
    fi
    
    echo -e "${CYAN}📦 Extracting ALEX core...${NC}"
    mkdir -p "$CONFIG_DIR"
    
    if ! unzip -q "$ZIP_FILE" -d "$CONFIG_DIR"; then
        rm -rf "$DOWNLOAD_DIR"
        manual_download_instructions
    fi
    
    # ⭐ IMPORTANT: Rename rgt binary to alex
    if [[ -f "${CONFIG_DIR}/rgt" ]]; then
        mv "${CONFIG_DIR}/rgt" "${ALEX_BIN}"
        chmod +x "${ALEX_BIN}"
        rm -rf "$DOWNLOAD_DIR"
        show_success "ALEX core installed successfully"
        echo
        return 0
    fi
    
    # If alex file already exists in extracted files
    if [[ -f "${CONFIG_DIR}/alex" ]]; then
        mv "${CONFIG_DIR}/alex" "${ALEX_BIN}"
        chmod +x "${ALEX_BIN}"
        rm -rf "$DOWNLOAD_DIR"
        show_success "ALEX core installed successfully"
        echo
        return 0
    fi
    
    rm -rf "$DOWNLOAD_DIR"
    manual_download_instructions
}

update_script() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        Updating ALEX Manager Script        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo
    
    UPDATE_URL="https://raw.githubusercontent.com/Alextaylorvhjnf/ALEX-Tunnel/main/alex_manager.sh"
    TEMP_SCRIPT="/tmp/alex_manager.sh"
    
    show_progress "Downloading updated script"
    if ! curl -sSL -o "$TEMP_SCRIPT" "$UPDATE_URL"; then
        show_error "Failed to download updated script"
        rm -f "$TEMP_SCRIPT" 2>/dev/null
        press_key
        return 1
    fi
    
    if ! grep -q "ALEX TUNNEL MANAGER" "$TEMP_SCRIPT"; then
        show_error "Downloaded file is invalid"
        rm -f "$TEMP_SCRIPT" 2>/dev/null
        press_key
        return 1
    fi
    
    if ! mv "$TEMP_SCRIPT" "${SCRIPT_PATH}"; then
        show_error "Failed to update script"
        rm -f "$TEMP_SCRIPT" 2>/dev/null
        press_key
        return 1
    fi
    
    chmod +x "${SCRIPT_PATH}"
    show_success "ALEX Manager updated successfully!"
    echo -e "${YELLOW}Please re-run with: ${GREEN}ALEX${NC}"
    echo
    
    press_key
    exit 0
}

check_port() {
    local port=$1
    local transport=$2
    if [[ "$transport" == "tcp" ]]; then
        ss -tlnp "sport = :$port" | grep -q "$port" && return 0 || return 1
    elif [[ "$transport" == "udp" ]]; then
        ss -ulnp "sport = :$port" | grep -q "$port" && return 0 || return 1
    else
        return 1
    fi
}

check_ipv6() {
    local ip=$1
    ip="${ip#[}"
    ip="${ip%]}"
    ipv6_pattern="^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(:[0-9a-fA-F]{1,4}){1,6}|:((:[0-9a-fA-F]{1,4}){1,7}|:))$"
    [[ $ip =~ $ipv6_pattern ]] && return 0 || return 1
}

check_ipv4() {
    local ip=$1
    ipv4_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    if [[ $ip =~ $ipv4_pattern ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            [[ $octet -gt 255 ]] && return 1
        done
        return 0
    fi
    return 1
}

check_consecutive_errors() {
    local service_name="$1"
    local tunnel_name=$(echo "$service_name" | sed 's/ALEX-//;s/.service//')
    local logs=$(journalctl -u "$service_name" -n 50 --no-pager | tail -n 2)
    local error_count=$(echo "$logs" | grep -c "ERROR")
    if [[ $error_count -ge 2 ]]; then
        show_warning "Consecutive errors detected in $service_name. Restarting..."
        systemctl restart "$service_name"
        if [[ $? -eq 0 ]]; then
            show_success "Tunnel $tunnel_name restarted successfully"
        else
            show_error "Failed to restart tunnel $tunnel_name"
        fi
    fi
}

validate_vxlan_setup() {
    local local_ip=$1
    local remote_ip=$2
    local tunnel_port=$3
    local network_interface=$4
    local vxlan_id=$5

    if ! ip link show "$network_interface" up &> /dev/null; then
        show_error "Network interface $network_interface is not up"
        return 1
    fi

    if ! lsmod | grep -q vxlan; then
        show_progress "Loading VXLAN kernel module"
        modprobe vxlan || { show_error "Failed to load VXLAN module"; return 1; }
    fi

    if [[ "$local_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if ! ip -4 addr show dev "$network_interface" | grep -w "$local_ip" &> /dev/null; then
            show_error "IP address $local_ip is not assigned to interface $network_interface"
            return 1
        fi
    fi

    return 0
}

direct_server_configuration() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       Configure Direct Tunnel              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}Select Server Type:${NC}"
    echo -e "  ${GREEN}1)${NC} 🇮🇷 Iran Server"
    echo -e "  ${GREEN}2)${NC} 🌍 Kharej Server"
    echo
    read -p "$(echo -e ${YELLOW}Enter choice: ${NC})" server_type
    case $server_type in
        1) configure_direct_iran ;;
        2) configure_direct_kharej ;;
        *) show_error "Invalid option!" && press_key && return 1 ;;
    esac
}

update_haproxy_config() {
    local tunnel_name="$1"
    shift
    local ports=("$@")
    local kharej_bridge_ip="${ports[-1]}"
    unset 'ports[-1]'
    local tunnel_port="${ports[-1]}"
    unset 'ports[-1]'
    local haproxy_config="${HAPROXY_CFG:-/etc/haproxy/haproxy.cfg}"

    if [[ -z "$haproxy_config" ]]; then
        show_error "HAProxy configuration path is not defined"
        return 1
    fi

    local haproxy_dir=$(dirname "$haproxy_config")
    if [[ ! -d "$haproxy_dir" ]]; then
        mkdir -p "$haproxy_dir"
    fi

    if [[ ! -f "$haproxy_config" ]]; then
        cat << EOF > "$haproxy_config"
global
    maxconn 50000
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    timeout check 5000ms
EOF
    fi

    cp "$haproxy_config" "${haproxy_config}.bak" 2>/dev/null
    sed -i "/#start:$tunnel_port/,/#end:$tunnel_port/d" "$haproxy_config" 2>/dev/null

    cat << EOF >> "$haproxy_config"
#start:$tunnel_port
EOF
    for port in "${ports[@]}"; do
        cat << EOF >> "$haproxy_config"
frontend vless_frontend_${port}
    bind *:${port}
    mode tcp
    option tcplog
    default_backend vless_backend_${port}

backend vless_backend_${port}
    mode tcp
    option tcp-check
    server ALEX_server ${kharej_bridge_ip%/*}:${port} check inter 5000 rise 2 fall 3
EOF
    done
    cat << EOF >> "$haproxy_config"
#end:$tunnel_port
EOF

    if ! haproxy -c -f "$haproxy_config" >/dev/null 2>&1; then
        show_error "Invalid HAProxy configuration. Restoring backup."
        cp "${haproxy_config}.bak" "$haproxy_config" 2>/dev/null
        return 1
    fi

    systemctl restart haproxy >/dev/null 2>&1
    show_success "HAProxy configuration updated"
    return 0
}

configure_direct_iran() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}📋 Direct Tunnel - Iran Server Configuration${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    read -p "$(echo -e ${YELLOW}🔤 Tunnel name: ${NC})" tunnel_name
    tunnel_name=$(echo "$tunnel_name" | tr ' ' '-' | tr -d '[:space:]')
    if [[ -z "$tunnel_name" ]]; then
        show_error "Tunnel name cannot be empty"
        press_key
        return 1
    fi
    
    if [[ -f "${CONFIG_DIR}/direct-iran-${tunnel_name}.conf" ]]; then
        show_error "Tunnel '$tunnel_name' already exists"
        press_key
        return 1
    fi

    echo
    echo -e "${WHITE}IP Type:${NC}"
    echo -e "  ${GREEN}1)${NC} IPv4"
    echo -e "  ${GREEN}2)${NC} IPv6"
    read -p "$(echo -e ${YELLOW}Choice: ${NC})" ip_choice
    case $ip_choice in
        1) ip_type="ipv4" ;;
        2) ip_type="ipv6" ;;
        *) ip_type="ipv4" ;;
    esac

    if [[ "$ip_type" == "ipv4" ]]; then
        local_ip=$(ip -4 addr show $(detect_network_interface) | grep inet | awk '{print $2}' | cut -d'/' -f1)
    else
        local_ip=$(ip -6 addr show $(detect_network_interface) | grep inet6 | grep global | awk '{print $2}' | cut -d'/' -f1)
    fi
    
    echo -e "${GREEN}📍 Iran server IP: $local_ip${NC}"
    echo
    
    read -p "$(echo -e ${YELLOW}🌍 Kharej server IP: ${NC})" remote_ip
    [[ -z "$remote_ip" ]] && { show_error "IP cannot be empty"; press_key; return 1; }
    
    if check_ipv6 "$remote_ip"; then
        remote_ip="${remote_ip#[}"
        remote_ip="${remote_ip%]}"
    elif ! check_ipv4 "$remote_ip"; then
        show_error "Invalid IP format"
        press_key
        return 1
    fi

    while true; do
        read -p "$(echo -e ${YELLOW}🔌 Tunnel port (23-65535): ${NC})" tunnel_port
        if [[ "$tunnel_port" =~ ^[0-9]+$ ]] && [ "$tunnel_port" -gt 22 ] && [ "$tunnel_port" -le 65535 ]; then
            check_port "$tunnel_port" "udp" && show_error "Port $tunnel_port is in use" || break
        else
            show_error "Enter valid port (23-65535)"
        fi
    done

    while true; do
        read -p "$(echo -e ${YELLOW}🔢 VXLAN ID (1-16777215): ${NC})" vxlan_id
        if [[ "$vxlan_id" =~ ^[0-9]+$ ]] && [ "$vxlan_id" -ge 1 ] && [ "$vxlan_id" -le 16777215 ]; then
            ip link show "vxlan${vxlan_id}" >/dev/null 2>&1 && show_error "VXLAN ID $vxlan_id already in use" || break
        else
            show_error "Enter valid VXLAN ID"
        fi
    done

    network_interface=$(detect_network_interface)
    echo -e "${GREEN}🖧 Network interface: $network_interface${NC}"

    read -p "$(echo -e ${YELLOW}🏠 Iran bridge IP [10.0.10.1]: ${NC})" iran_bridge_ip
    [[ -z "$iran_bridge_ip" ]] && iran_bridge_ip="10.0.10.1"
    iran_bridge_ip="${iran_bridge_ip}/24"

    read -p "$(echo -e ${YELLOW}🌍 Kharej bridge IP [10.0.10.2]: ${NC})" kharej_bridge_ip
    [[ -z "$kharej_bridge_ip" ]] && kharej_bridge_ip="10.0.10.2"
    kharej_bridge_ip="${kharej_bridge_ip}/24"

    read -p "$(echo -e ${YELLOW}🔧 Service ports (e.g., 8080,40001): ${NC})" input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports
    
    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 22 ] && [ "$port" -le 65535 ]; then
            config_ports+=("$port")
        fi
    done
    
    if [[ ${#config_ports[@]} -eq 0 ]]; then
        show_error "No valid ports entered"
        sleep 2
        return 1
    fi

    echo
    show_progress "Creating VXLAN interface"
    ip link add vxlan${vxlan_id} type vxlan id "$vxlan_id" local "$local_ip" remote "$remote_ip" dstport "$tunnel_port" dev "$network_interface" || {
        show_error "Failed to create VXLAN interface"
        press_key
        return 1
    }
    
    show_progress "Creating bridge"
    ip link add name br${vxlan_id} type bridge
    ip link set vxlan${vxlan_id} master br${vxlan_id}
    ip link set br${vxlan_id} up
    ip link set vxlan${vxlan_id} up
    ip addr flush dev br${vxlan_id} 2>/dev/null
    ip addr add "$iran_bridge_ip" dev br${vxlan_id}

    config_file="${CONFIG_DIR}/direct-iran-${tunnel_name}.conf"
    cat << EOF > "$config_file"
vxlan_id=$vxlan_id
local_ip=$local_ip
remote_ip=$remote_ip
dstport=$tunnel_port
network_interface=$network_interface
iran_bridge_ip=$iran_bridge_ip
kharej_bridge_ip=$kharej_bridge_ip
ports=$input_ports
EOF

    service_file="${SERVICE_DIR}/ALEX-direct-iran-${tunnel_name}.service"
    cat << EOF > "$service_file"
[Unit]
Description=ALEX Direct Iran Tunnel $tunnel_name
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "ip link show vxlan${vxlan_id} >/dev/null 2>&1 || ip link add vxlan${vxlan_id} type vxlan id $vxlan_id local $local_ip remote $remote_ip dstport $tunnel_port dev $network_interface; ip link show br${vxlan_id} >/dev/null 2>&1 || ip link add name br${vxlan_id} type bridge; ip link set vxlan${vxlan_id} master br${vxlan_id}; ip link set br${vxlan_id} up; ip link set vxlan${vxlan_id} up; ip addr flush dev br${vxlan_id} 2>/dev/null; ip addr add $iran_bridge_ip dev br${vxlan_id}; systemctl restart haproxy"
ExecStop=/bin/bash -c "ip link delete vxlan${vxlan_id} 2>/dev/null; ip link delete br${vxlan_id} 2>/dev/null; systemctl restart haproxy"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "ALEX-direct-iran-${tunnel_name}.service" >/dev/null 2>&1
    systemctl start "ALEX-direct-iran-${tunnel_name}.service" >/dev/null 2>&1

    show_success "Direct tunnel '$tunnel_name' configured successfully!"
    echo -e "${GREEN}📍 Iran bridge IP: ${iran_bridge_ip}${NC}"
    echo -e "${GREEN}🌍 Kharej bridge IP: ${kharej_bridge_ip}${NC}"
    press_key
    return 0
}

configure_direct_kharej() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}📋 Direct Tunnel - Kharej Server Configuration${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    read -p "$(echo -e ${YELLOW}🔤 Tunnel name: ${NC})" tunnel_name
    tunnel_name=$(echo "$tunnel_name" | tr ' ' '-' | tr -d '[:space:]')
    [[ -z "$tunnel_name" ]] && { show_error "Tunnel name cannot be empty"; press_key; return 1; }
    [[ -f "${CONFIG_DIR}/direct-kharej-${tunnel_name}.conf" ]] && { show_error "Tunnel '$tunnel_name' already exists"; press_key; return 1; }

    echo -e "${WHITE}IP Type:${NC}"
    echo -e "  ${GREEN}1)${NC} IPv4"
    echo -e "  ${GREEN}2)${NC} IPv6"
    read -p "$(echo -e ${YELLOW}Choice: ${NC})" ip_choice
    
    if [[ "$ip_choice" == "2" ]]; then
        local_ip=$(ip -6 addr show $(detect_network_interface) | grep inet6 | grep global | awk '{print $2}' | cut -d'/' -f1)
    else
        local_ip=$(ip -4 addr show $(detect_network_interface) | grep inet | awk '{print $2}' | cut -d'/' -f1)
    fi
    
    echo -e "${GREEN}📍 Kharej server IP: $local_ip${NC}"
    
    read -p "$(echo -e ${YELLOW}🇮🇷 Iran server IP: ${NC})" remote_ip
    [[ -z "$remote_ip" ]] && { show_error "IP cannot be empty"; press_key; return 1; }
    
    if check_ipv6 "$remote_ip"; then
        remote_ip="${remote_ip#[}"
        remote_ip="${remote_ip%]}"
    elif ! check_ipv4 "$remote_ip"; then
        show_error "Invalid IP format"
        press_key
        return 1
    fi

    while true; do
        read -p "$(echo -e ${YELLOW}🔌 Tunnel port (23-65535): ${NC})" tunnel_port
        [[ "$tunnel_port" =~ ^[0-9]+$ ]] && [ "$tunnel_port" -gt 22 ] && [ "$tunnel_port" -le 65535 ] && break
        show_error "Enter valid port (23-65535)"
    done

    while true; do
        read -p "$(echo -e ${YELLOW}🔢 VXLAN ID (1-16777215): ${NC})" vxlan_id
        [[ "$vxlan_id" =~ ^[0-9]+$ ]] && [ "$vxlan_id" -ge 1 ] && [ "$vxlan_id" -le 16777215 ] && break
        show_error "Enter valid VXLAN ID"
    done

    network_interface=$(detect_network_interface)
    
    read -p "$(echo -e ${YELLOW}🌍 Kharej bridge IP [10.0.10.2]: ${NC})" bridge_ip
    [[ -z "$bridge_ip" ]] && bridge_ip="10.0.10.2"
    bridge_ip="${bridge_ip}/24"

    show_progress "Creating tunnel interfaces"
    ip link add vxlan${vxlan_id} type vxlan id $vxlan_id local "$local_ip" remote "$remote_ip" dstport "$tunnel_port" dev "$network_interface"
    ip link add name br${vxlan_id} type bridge
    ip link set vxlan${vxlan_id} master br${vxlan_id}
    ip link set br${vxlan_id} up
    ip link set vxlan${vxlan_id} up
    ip addr flush dev br${vxlan_id} 2>/dev/null
    ip addr add "${bridge_ip}" dev br${vxlan_id}

    config_file="${CONFIG_DIR}/direct-kharej-${tunnel_name}.conf"
    cat << EOF > "$config_file"
vxlan_id=$vxlan_id
local_ip=$local_ip
remote_ip=$remote_ip
dstport=$tunnel_port
network_interface=$network_interface
bridge_ip=$bridge_ip
EOF

    service_file="${SERVICE_DIR}/ALEX-direct-kharej-${tunnel_name}.service"
    cat << EOF > "$service_file"
[Unit]
Description=ALEX Direct Kharej Tunnel $tunnel_name
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "ip link show vxlan${vxlan_id} >/dev/null 2>&1 || ip link add vxlan${vxlan_id} type vxlan id ${vxlan_id} local $local_ip remote $remote_ip dstport $tunnel_port dev $network_interface; ip link show br${vxlan_id} >/dev/null 2>&1 || ip link add name br${vxlan_id} type bridge; ip link set vxlan${vxlan_id} master br${vxlan_id}; ip link set br${vxlan_id} up; ip link set vxlan${vxlan_id} up; ip addr flush dev br${vxlan_id} 2>/dev/null; ip addr add ${bridge_ip} dev br${vxlan_id}"
ExecStop=/bin/bash -c "ip link delete vxlan${vxlan_id} 2>/dev/null; ip link delete br${vxlan_id} 2>/dev/null"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "ALEX-direct-kharej-${tunnel_name}.service" >/dev/null 2>&1
    systemctl start "ALEX-direct-kharej-${tunnel_name}.service" >/dev/null 2>&1

    show_success "Direct tunnel '$tunnel_name' configured successfully!"
    echo -e "${GREEN}🌍 Bridge IP: ${bridge_ip}${NC}"
    press_key
    return 0
}

iran_server_configuration() {
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}📋 Reverse Tunnel - Iran Server Configuration${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    read -p "$(echo -e ${YELLOW}🔤 Tunnel name: ${NC})" tunnel_name
    tunnel_name=$(echo "$tunnel_name" | tr ' ' '-' | tr -d '[:space:]')
    [[ -z "$tunnel_name" ]] && { show_error "Tunnel name cannot be empty"; press_key; return 1; }
    [[ -f "${CONFIG_DIR}/iran-${tunnel_name}.toml" ]] && { show_error "Tunnel '$tunnel_name' already exists"; press_key; return 1; }

    local_ip="0.0.0.0"
    echo -e "${WHITE}IP Type:${NC}"
    echo -e "  ${GREEN}1)${NC} IPv4 (0.0.0.0)"
    echo -e "  ${GREEN}2)${NC} IPv6 ([::])"
    read -p "$(echo -e ${YELLOW}Choice: ${NC})" ip_choice
    [[ "$ip_choice" == "2" ]] && local_ip="[::]"

    while true; do
        read -p "$(echo -e ${YELLOW}🔌 Tunnel port (23-65535): ${NC})" tunnel_port
        if [[ "$tunnel_port" =~ ^[0-9]+$ ]] && [ "$tunnel_port" -gt 22 ] && [ "$tunnel_port" -le 65535 ]; then
            check_port "$tunnel_port" "tcp" && show_error "Port $tunnel_port is in use" || break
        else
            show_error "Enter valid port (23-65535)"
        fi
    done

    echo -e "${WHITE}Transport:${NC}"
    echo -e "  ${GREEN}1)${NC} TCP"
    echo -e "  ${GREEN}2)${NC} UDP"
    read -p "$(echo -e ${YELLOW}Choice: ${NC})" transport_choice
    local transport="tcp"
    [[ "$transport_choice" == "2" ]] && transport="udp"

    read -p "$(echo -e ${YELLOW}🔑 Security token [ALEX]: ${NC})" token
    [[ -z "$token" ]] && token="ALEX"
    local nodelay="true"
    local heartbeat="0"

    read -p "$(echo -e ${YELLOW}🔧 Service ports (e.g., 8008,8080): ${NC})" input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports
    for port in "${ports[@]}"; do
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 22 ] && [ "$port" -le 65535 ] && config_ports+=("$port")
    done
    [[ ${#config_ports[@]} -eq 0 ]] && { show_error "No valid ports"; sleep 2; return 1; }

    config_file="${CONFIG_DIR}/iran-${tunnel_name}.toml"
    cat << EOF > "$config_file"
[server]
bind_addr = "${local_ip}:${tunnel_port}"
default_token = "$token"
heartbeat_interval = $heartbeat

[server.transport]
type = "$transport"

[server.transport.$transport]
nodelay = $nodelay
keepalive_secs = 20
keepalive_interval = 8

EOF

    for port in "${config_ports[@]}"; do
        cat << EOF >> "$config_file"
[server.services.service${port}]
type = "$transport"
token = "$token"
bind_addr = "${local_ip}:${port}"
nodelay = $nodelay

EOF
    done

    service_file="${SERVICE_DIR}/ALEX-iran-${tunnel_name}.service"
    cat << EOF > "$service_file"
[Unit]
Description=ALEX Iran Tunnel $tunnel_name
After=network.target

[Service]
Type=simple
ExecStart=${ALEX_BIN} ${config_file}
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "ALEX-iran-${tunnel_name}.service" >/dev/null 2>&1

    show_success "Reverse tunnel '$tunnel_name' configured successfully!"
    press_key
    return 0
}

kharej_server_configuration() {
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}📋 Reverse Tunnel - Kharej Server Configuration${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    read -p "$(echo -e ${YELLOW}🔤 Tunnel name: ${NC})" tunnel_name
    tunnel_name=$(echo "$tunnel_name" | tr ' ' '-' | tr -d '[:space:]')
    [[ -z "$tunnel_name" ]] && { show_error "Tunnel name cannot be empty"; press_key; return 1; }
    [[ -f "${CONFIG_DIR}/kharej-${tunnel_name}.toml" ]] && { show_error "Tunnel '$tunnel_name' already exists"; press_key; return 1; }

    read -p "$(echo -e ${YELLOW}🇮🇷 Iran server IP: ${NC})" server_addr
    [[ -z "$server_addr" ]] && { show_error "IP cannot be empty"; press_key; return 1; }
    
    if check_ipv6 "$server_addr"; then
        server_addr="${server_addr#[}"
        server_addr="${server_addr%]}"
    elif ! check_ipv4 "$server_addr"; then
        show_error "Invalid IP format"
        press_key
        return 1
    fi

    while true; do
        read -p "$(echo -e ${YELLOW}🔌 Tunnel port (23-65535): ${NC})" tunnel_port
        [[ "$tunnel_port" =~ ^[0-9]+$ ]] && [ "$tunnel_port" -gt 22 ] && [ "$tunnel_port" -le 65535 ] && break
        show_error "Enter valid port (23-65535)"
    done

    echo -e "${WHITE}Transport:${NC}"
    echo -e "  ${GREEN}1)${NC} TCP"
    echo -e "  ${GREEN}2)${NC} UDP"
    read -p "$(echo -e ${YELLOW}Choice: ${NC})" transport_choice
    local transport="tcp"
    [[ "$transport_choice" == "2" ]] && transport="udp"

    read -p "$(echo -e ${YELLOW}🔑 Security token [ALEX]: ${NC})" token
    [[ -z "$token" ]] && token="ALEX"
    local nodelay="true"
    local heartbeat="0"
    local_ip="127.0.0.1"

    read -p "$(echo -e ${YELLOW}🔧 Service ports (e.g., 8008,8080): ${NC})" input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports
    for port in "${ports[@]}"; do
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 22 ] && [ "$port" -le 65535 ] && config_ports+=("$port")
    done
    [[ ${#config_ports[@]} -eq 0 ]] && { show_error "No valid ports"; sleep 2; return 1; }

    config_file="${CONFIG_DIR}/kharej-${tunnel_name}.toml"
    cat << EOF > "$config_file"
[client]
remote_addr = "${server_addr}:${tunnel_port}"
default_token = "$token"
heartbeat_timeout = $heartbeat

[client.transport]
type = "$transport"

[client.transport.$transport]
nodelay = $nodelay
keepalive_secs = 20
keepalive_interval = 8

EOF

    for port in "${config_ports[@]}"; do
        cat << EOF >> "$config_file"
[client.services.service${port}]
type = "$transport"
token = "$token"
local_addr = "${local_ip}:${port}"
nodelay = $nodelay

EOF
    done

    service_file="${SERVICE_DIR}/ALEX-kharej-${tunnel_name}.service"
    cat << EOF > "$service_file"
[Unit]
Description=ALEX Kharej Tunnel $tunnel_name
After=network.target

[Service]
Type=simple
ExecStart=${ALEX_BIN} ${config_file}
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "ALEX-kharej-${tunnel_name}.service" >/dev/null 2>&1

    show_success "Reverse tunnel '$tunnel_name' configured successfully!"
    press_key
    return 0
}

manage_tunnel() {
    clear
    local tunnel_found=0
    local index=1
    declare -a configs
    declare -a config_types
    declare -a tunnel_names
    declare -a service_names

    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           Manage Existing Tunnels          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo

    for config_path in "$CONFIG_DIR"/direct-iran-*.conf; do
        if [[ -f "$config_path" ]]; then
            tunnel_found=1
            tunnel_name=$(basename "$config_path" .conf | sed 's/^direct-iran-//')
            tunnel_type="direct-iran"
            service_name="ALEX-direct-iran-${tunnel_name}.service"
            tunnel_port=$(grep "^dstport=" "$config_path" 2>/dev/null | cut -d'=' -f2)
            [[ -z "$tunnel_port" ]] && tunnel_port="?"
            configs+=("$config_path"); config_types+=("$tunnel_type"); tunnel_names+=("$tunnel_name"); service_names+=("$service_name")
            echo -e "${GREEN}${index})${NC} 🔵 Direct Iran: ${WHITE}${tunnel_name}${NC} | Port: ${YELLOW}${tunnel_port}${NC}"
            ((index++))
        fi
    done

    for config_path in "$CONFIG_DIR"/direct-kharej-*.conf; do
        if [[ -f "$config_path" ]]; then
            tunnel_found=1
            tunnel_name=$(basename "$config_path" .conf | sed 's/^direct-kharej-//')
            tunnel_type="direct-kharej"
            service_name="ALEX-direct-kharej-${tunnel_name}.service"
            tunnel_port=$(grep "^dstport=" "$config_path" 2>/dev/null | cut -d'=' -f2)
            [[ -z "$tunnel_port" ]] && tunnel_port="?"
            configs+=("$config_path"); config_types+=("$tunnel_type"); tunnel_names+=("$tunnel_name"); service_names+=("$service_name")
            echo -e "${GREEN}${index})${NC} 🟢 Direct Kharej: ${WHITE}${tunnel_name}${NC} | Port: ${YELLOW}${tunnel_port}${NC}"
            ((index++))
        fi
    done

    for config_path in "$CONFIG_DIR"/iran-*.toml; do
        if [[ -f "$config_path" ]]; then
            tunnel_found=1
            tunnel_name=$(basename "$config_path" .toml | sed 's/^iran-//')
            tunnel_type="iran"
            service_name="ALEX-iran-${tunnel_name}.service"
            tunnel_port=$(grep "bind_addr" "$config_path" 2>/dev/null | head -n 1 | cut -d':' -f2 | cut -d'"' -f1)
            [[ -z "$tunnel_port" ]] && tunnel_port="?"
            configs+=("$config_path"); config_types+=("$tunnel_type"); tunnel_names+=("$tunnel_name"); service_names+=("$service_name")
            echo -e "${GREEN}${index})${NC} 🔴 Reverse Iran: ${WHITE}${tunnel_name}${NC} | Port: ${YELLOW}${tunnel_port}${NC}"
            ((index++))
        fi
    done

    for config_path in "$CONFIG_DIR"/kharej-*.toml; do
        if [[ -f "$config_path" ]]; then
            tunnel_found=1
            tunnel_name=$(basename "$config_path" .toml | sed 's/^kharej-//')
            tunnel_type="kharej"
            service_name="ALEX-kharej-${tunnel_name}.service"
            tunnel_port=$(grep "remote_addr" "$config_path" 2>/dev/null | cut -d':' -f2 | cut -d'"' -f1)
            [[ -z "$tunnel_port" ]] && tunnel_port="?"
            configs+=("$config_path"); config_types+=("$tunnel_type"); tunnel_names+=("$tunnel_name"); service_names+=("$service_name")
            echo -e "${GREEN}${index})${NC} 🟡 Reverse Kharej: ${WHITE}${tunnel_name}${NC} | Port: ${YELLOW}${tunnel_port}${NC}"
            ((index++))
        fi
    done

    echo
    if [[ $tunnel_found -eq 0 ]]; then
        show_warning "No tunnels found"
        press_key
        return 1
    fi

    read -p "$(echo -e ${YELLOW}Select tunnel (0 to return): ${NC})" choice
    [[ "$choice" == "0" ]] && return
    
    while ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice >= index )); do
        show_error "Invalid choice"
        read -p "$(echo -e ${YELLOW}Select tunnel (0 to return): ${NC})" choice
        [[ "$choice" == "0" ]] && return
    done

    selected_config="${configs[$((choice - 1))]}"
    tunnel_type="${config_types[$((choice - 1))]}"
    tunnel_name="${tunnel_names[$((choice - 1))]}"
    service_name="${service_names[$((choice - 1))]}"
    service_path="${SERVICE_DIR}/${service_name}"

    echo
    echo -e "${CYAN}═══ Managing: ${WHITE}${tunnel_name}${NC} ${CYAN}(${tunnel_type}) ═══${NC}"
    echo
    echo -e "  ${GREEN}1)${NC} ▶️  Start"
    echo -e "  ${GREEN}2)${NC} ⏹️  Stop"
    echo -e "  ${GREEN}3)${NC} 🔄 Restart"
    echo -e "  ${GREEN}4)${NC} 📊 Status"
    echo -e "  ${GREEN}5)${NC} 🗑️  Delete"
    echo -e "  ${GREEN}0)${NC} ↩️  Return"
    echo
    read -p "$(echo -e ${YELLOW}Choice: ${NC})" manage_choice

    case $manage_choice in
        1) systemctl start "$service_name" && show_success "Started" || show_error "Failed to start" ;;
        2) systemctl stop "$service_name" && show_success "Stopped" || show_error "Failed to stop" ;;
        3) systemctl restart "$service_name" && show_success "Restarted" || show_error "Failed to restart" ;;
        4) systemctl status "$service_name" ;;
        5)
            read -p "$(echo -e ${RED}Delete $tunnel_name? (y/n): ${NC})" confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                systemctl stop "$service_name" 2>/dev/null
                systemctl disable "$service_name" 2>/dev/null
                rm -f "$service_path" "$selected_config"
                systemctl daemon-reload
                show_success "Tunnel deleted"
            fi
            ;;
        0) return ;;
        *) show_error "Invalid option" ;;
    esac
    press_key
}

remove_core() {
    clear
    echo -e "${RED}╔════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║         Uninstall ALEX Core                ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════╝${NC}"
    echo
    
    if ls "$CONFIG_DIR"/*.toml "$CONFIG_DIR"/*.conf &> /dev/null; then
        show_warning "Remove all tunnels before uninstalling core"
        press_key
        return 1
    fi
    
    read -p "$(echo -e ${RED}Confirm removal? (y/n): ${NC})" confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        for service in $(ls "$SERVICE_DIR"/ALEX-*.service 2>/dev/null); do
            service_name=$(basename "$service")
            systemctl stop "$service_name" 2>/dev/null
            systemctl disable "$service_name" 2>/dev/null
            rm -f "$service"
        done
        rm -rf "$CONFIG_DIR"
        systemctl daemon-reload
        show_success "ALEX core removed"
    fi
    press_key
}

display_logo() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"

    ╔═══════════════════════════════════════════════╗
    ║                                               ║
    ║        █████╗ ██╗     ███████╗██╗  ██╗        ║
    ║       ██╔══██╗██║     ██╔════╝╚██╗██╔╝        ║
    ║       ███████║██║     █████╗   ╚███╔╝         ║
    ║       ██╔══██║██║     ██╔══╝   ██╔██╗         ║
    ║       ██║  ██║███████╗███████╗██╔╝ ██╗        ║
    ║       ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝        ║
    ║                                               ║
    ║          ALEX Tunnel Manager v1.2.1           ║
    ║       github.com/Alextaylorvhjnf              ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

display_server_info() {
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo
    echo -e "${BLUE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}  🌐 IP: ${GREEN}${SERVER_IP}${NC}"
    if [[ -f "${ALEX_BIN}" ]] && [[ -x "${ALEX_BIN}" ]]; then
        echo -e "${BLUE}│${NC}  📦 Core: ${GREEN}✓ Installed${NC}"
    else
        echo -e "${BLUE}│${NC}  📦 Core: ${RED}✗ Not Installed${NC}"
    fi
    echo -e "${BLUE}└─────────────────────────────────────────────┘${NC}"
    echo
}

display_menu() {
    display_logo
    display_server_info
    echo -e "${CYAN}  [1]${NC} 🚀 Setup New Tunnel"
    echo -e "${GREEN}  [2]${NC} 📋 Manage Tunnels"
    echo -e "${BLUE}  [3]${NC} 📦 Install ALEX Core"
    echo -e "${RED}  [4]${NC} 🗑️  Uninstall ALEX Core"
    echo -e "${YELLOW}  [5]${NC} 🔄 Update Script"
    echo -e "${MAGENTA}  [6]${NC} 🔧 ALEX Tools"
    echo -e "${WHITE}  [7]${NC} 🚪 Exit"
    echo
    echo -e "${BLUE}─────────────────────────────────────────────${NC}"
    echo
}

alex_tools() {
    clear
    echo -e "${MAGENTA}╔════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║             ALEX Tools Menu               ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════╝${NC}"
    echo
    echo -e "  ${GREEN}1)${NC} 📊 Check all tunnels bandwidth"
    echo -e "  ${GREEN}2)${NC} 🔍 View tunnel logs"
    echo -e "  ${GREEN}3)${NC} 🧹 Clean up unused configs"
    echo -e "  ${GREEN}0)${NC} ↩️  Return"
    echo
    read -p "$(echo -e ${YELLOW}Choice: ${NC})" tool_choice
    case $tool_choice in
        1) show_warning "Bandwidth tool - coming soon" ;;
        2) journalctl -u ALEX-* -n 50 --no-pager ;;
        3) show_warning "Cleanup tool - coming soon" ;;
        0) return ;;
        *) show_error "Invalid option" ;;
    esac
    press_key
}

# ═══════════════ MAIN ═══════════════

install_dependencies
mkdir -p "$CONFIG_DIR"

if [[ "$0" == "/dev/fd/"* || "$0" == "bash" ]]; then
    show_progress "Installing ALEX Manager"
    if ! curl -sSL -o "${SCRIPT_PATH}" "https://raw.githubusercontent.com/Alextaylorvhjnf/ALEX-Tunnel/main/alex_manager.sh"; then
        show_error "Failed to download script"
        press_key
        exit 1
    fi
    
    if ! grep -q "ALEX TUNNEL MANAGER" "${SCRIPT_PATH}"; then
        show_error "Downloaded script is incomplete"
        rm -f "${SCRIPT_PATH}"
        press_key
        exit 1
    fi
    
    chmod +x "${SCRIPT_PATH}"
    show_success "ALEX Manager installed! Run with: ${GREEN}ALEX${NC}"
    echo
    press_key
    exec "${SCRIPT_PATH}"
fi

if [[ ! -f "${SCRIPT_PATH}" ]]; then
    show_progress "Installing ALEX Manager"
    if ! curl -sSL -o "${SCRIPT_PATH}" "https://raw.githubusercontent.com/Alextaylorvhjnf/ALEX-Tunnel/main/alex_manager.sh"; then
        show_error "Failed to download script"
        press_key
        exit 1
    fi
    chmod +x "${SCRIPT_PATH}"
    show_success "ALEX Manager installed! Run with: ${GREEN}ALEX${NC}"
    echo
    press_key
    exec "${SCRIPT_PATH}"
fi

while true; do
    display_menu
    read -p "$(echo -e ${WHITE}Enter choice: ${NC})" choice
    case $choice in
        1)
            clear
            echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║           Select Tunnel Type               ║${NC}"
            echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
            echo
            echo -e "  ${GREEN}1)${NC} 🔗 Direct Tunnel"
            echo -e "  ${GREEN}2)${NC} 🔄 Reverse Tunnel"
            echo
            read -p "$(echo -e ${YELLOW}Choice: ${NC})" tunnel_type
            case $tunnel_type in
                1) direct_server_configuration ;;
                2)
                    clear
                    echo -e "  ${GREEN}1)${NC} 🇮🇷 Iran Server"
                    echo -e "  ${GREEN}2)${NC} 🌍 Kharej Server"
                    read -p "$(echo -e ${YELLOW}Choice: ${NC})" server_type
                    case $server_type in
                        1) iran_server_configuration ;;
                        2) kharej_server_configuration ;;
                        *) show_error "Invalid option!" && sleep 1 ;;
                    esac
                    ;;
                *) show_error "Invalid option!" && sleep 1 ;;
            esac
            ;;
        2) manage_tunnel ;;
        3) download_and_extract_alex ;;
        4) remove_core ;;
        5) update_script ;;
        6) alex_tools ;;
        7) 
            echo -e "${GREEN}👋 Goodbye!${NC}"
            exit 0 
            ;;
        *) show_error "Invalid option!" && sleep 1 ;;
    esac
done
