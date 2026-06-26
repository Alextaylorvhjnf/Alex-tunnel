#!/bin/bash
# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    sleep 1
    exit 1
fi

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

# Define paths
CONFIG_DIR="/root/alex-core"
SERVICE_DIR="/etc/systemd/system"
ALEX_BIN="${CONFIG_DIR}/alex"
SCRIPT_PATH="/usr/local/bin/ALEX"

# Function to press key to continue
press_key() {
    echo
    read -rp "Press any key to continue..."
}

# Function to colorize text
colorize() {
    local color="$1"
    local text="$2"
    local style="${3:-normal}"
    local black="\033[30m"
    local red="\033[31m"
    local green="\033[32m"
    local yellow="\033[33m"
    local blue="\033[34m"
    local magenta="\033[35m"
    local cyan="\033[36m"
    local white="\033[37m"
    local reset="\033[0m"
    local normal="\033[0m"
    local bold="\033[1m"
    local underline="\033[4m"
    local color_code
    case $color in
        black) color_code=$black ;;
        red) color_code=$red ;;
        green) color_code=$green ;;
        yellow) color_code=$yellow ;;
        blue) color_code=$blue ;;
        magenta) color_code=$magenta ;;
        cyan) color_code=$cyan ;;
        white) color_code=$white ;;
        *) color_code=$reset ;;
    esac
    local style_code
    case $style in
        bold) style_code=$bold ;;
        underline) style_code=$underline ;;
        normal | *) style_code=$normal ;;
    esac
    echo -e "${style_code}${color_code}${text}${reset}"
}

# Function to detect network interface
detect_network_interface() {
    local interface=$(ip link | grep -E '^[0-9]+: (eth[0-9]+|ens[0-9]+)' | awk '{print $2}' | cut -d':' -f1 | head -n 1)
    if [[ -z "$interface" ]]; then
        colorize red "No network interface found."
        press_key
        exit 1
    fi
    echo "$interface"
}

# Function to install dependencies
install_dependencies() {
    if ! command -v unzip &> /dev/null; then
        colorize yellow "Installing unzip..."
        apt-get update
        apt-get install -y unzip || { colorize red "Failed to install unzip"; press_key; exit 1; }
    fi
    if ! command -v jq &> /dev/null; then
        colorize yellow "Installing jq..."
        apt-get update
        apt-get install -y jq || { colorize red "Failed to install jq"; press_key; exit 1; }
    fi
    if ! command -v curl &> /dev/null; then
        colorize yellow "Installing curl..."
        apt-get update
        apt-get install -y curl || { colorize red "Failed to install curl"; press_key; exit 1; }
    fi
    if ! command -v ip &> /dev/null; then
        colorize yellow "Installing iproute2..."
        apt-get update
        apt-get install -y iproute2 || { colorize red "Failed to install iproute2"; press_key; exit 1; }
    fi
    if ! command -v brctl &> /dev/null; then
        colorize yellow "Installing bridge-utils..."
        apt-get update
        apt-get install -y bridge-utils || { colorize red "Failed to install bridge-utils"; press_key; exit 1; }
    fi
    if ! command -v haproxy &> /dev/null; then
        colorize yellow "Installing haproxy..."
        apt-get update
        apt-get install -y haproxy || { colorize red "Failed to install haproxy"; press_key; exit 1; }
    fi
}

# Function to display manual download instructions
manual_download_instructions() {
    colorize red "Failed to download ALEX core from GitHub due to network restrictions."
    echo
    colorize yellow "Please follow these steps to manually download and install ALEX core:"
    echo
    echo "1. Download the 'ALEX-x86-64-linux.zip' file from the following URL:"
    echo
    colorize yellow "   https://github.com/Alextaylorvhjnf/Alex-tunnel/raw/main/core/ALEX-x86-64-linux.zip"
    echo
    echo "   You can use a browser or wget on a system with access:"
    echo "   wget https://github.com/Alextaylorvhjnf/Alex-tunnel/raw/main/core/ALEX-x86-64-linux.zip"
    echo
    echo "2. Upload the downloaded file to /root/ on the server using SFTP."
    echo
    echo "3. Log in to the server via SSH and extract the file:"
    echo
    echo "   mkdir -p /root/alex-core"
    echo "   unzip /root/ALEX-x86-64-linux.zip -d /root/alex-core"
    echo "   mv /root/alex-core/alex /root/alex-core/alex"
    echo "   chmod +x /root/alex-core/alex"
    echo "   rm /root/ALEX-x86-64-linux.zip"
    echo
    echo "4. Re-run the script to continue setup."
    press_key
    exit 1
}

# Function to validate downloaded zip file
validate_zip_file() {
    local zip_file="$1"
    if [[ ! -f "$zip_file" ]]; then
        colorize red "Downloaded file does not exist."
        return 1
    fi
    if ! file "$zip_file" | grep -q "Zip archive data"; then
        colorize red "Downloaded file is not a valid zip archive."
        return 1
    fi
    if [[ $(stat -c %s "$zip_file") -lt 1000 ]]; then
        colorize red "Downloaded file is too small and not valid."
        return 1
    fi
    return 0
}

download_and_extract_alex() {
    if [[ -f "${ALEX_BIN}" ]] && [[ -x "${ALEX_BIN}" ]]; then
        colorize green "ALEX is already installed and executable." bold
        sleep 1
        return 0
    fi
    DOWNLOAD_URL="https://github.com/Alextaylorvhjnf/Alex-tunnel/raw/main/core/ALEX-x86-64-linux.zip"
    DOWNLOAD_DIR=$(mktemp -d)
    ZIP_FILE="$DOWNLOAD_DIR/alex.zip"
    colorize yellow "Downloading ALEX core..."
    if ! curl -sSL -o "$ZIP_FILE" "$DOWNLOAD_URL"; then
        rm -rf "$DOWNLOAD_DIR"
        colorize red "Failed to download ALEX core."
        manual_download_instructions
    fi
    if ! validate_zip_file "$ZIP_FILE"; then
        rm -rf "$DOWNLOAD_DIR"
        manual_download_instructions
    fi
    colorize yellow "Extracting ALEX..."
    mkdir -p "$CONFIG_DIR"
    if ! unzip -q "$ZIP_FILE" -d "$CONFIG_DIR"; then
        colorize red "Failed to extract ALEX"
        rm -rf "$DOWNLOAD_DIR"
        manual_download_instructions
    fi
    if [[ ! -f "${CONFIG_DIR}/alex" ]]; then
        colorize red "ALEX binary not found in zip file"
        rm -rf "$DOWNLOAD_DIR"
        manual_download_instructions
    fi
    mv "${CONFIG_DIR}/alex" "${ALEX_BIN}"
    chmod +x "${ALEX_BIN}"
    rm -rf "$DOWNLOAD_DIR"
    if [[ ! -x "${ALEX_BIN}" ]]; then
        colorize red "ALEX binary is not executable"
        manual_download_instructions
    fi
    colorize green "ALEX installed successfully." bold

    # Download alex-port-monitor.sh
    MONITOR_SCRIPT_URL="https://raw.githubusercontent.com/Alextaylorvhjnf/Alex-tunnel/main/tools/alex-port-monitor.sh"
    MONITOR_SCRIPT_PATH="${CONFIG_DIR}/tools/alex-port-monitor.sh"
    colorize yellow "Downloading alex-port-monitor.sh..."
    mkdir -p "${CONFIG_DIR}/tools"
    if ! curl -sSL -o "$MONITOR_SCRIPT_PATH" "$MONITOR_SCRIPT_URL"; then
        colorize red "Failed to download alex-port-monitor.sh."
        press_key
        return 1
    fi
    if ! grep -q "alex-port-monitor.sh" "$MONITOR_SCRIPT_PATH"; then
        colorize red "Downloaded alex-port-monitor.sh is invalid."
        rm -f "$MONITOR_SCRIPT_PATH"
        press_key
        return 1
    fi
    chmod +x "$MONITOR_SCRIPT_PATH"
    colorize green "alex-port-monitor.sh installed successfully." bold
}

# Function to update script
update_script() {
    clear
    colorize cyan "Updating ALEX Manager Script" bold
    echo
    UPDATE_URL="https://github.com/Alextaylorvhjnf/Alex-tunnel/raw/main/alex_manager.sh"
    TEMP_SCRIPT="/tmp/alex_manager.sh"
    colorize yellow "Downloading updated script..."
    if ! curl -sSL -o "$TEMP_SCRIPT" "$UPDATE_URL"; then
        colorize red "Failed to download updated script. Please check network or URL."
        rm -f "$TEMP_SCRIPT" 2>/dev/null
        press_key
        return 1
    fi
    if ! grep -q "ALEX Tunnel" "$TEMP_SCRIPT"; then
        colorize red "Downloaded file does not appear to be a valid ALEX script."
        rm -f "$TEMP_SCRIPT" 2>/dev/null
        press_key
        return 1
    fi
    if ! mv "$TEMP_SCRIPT" "${SCRIPT_PATH}"; then
        colorize red "Failed to move updated script to ${SCRIPT_PATH}."
        rm -f "$TEMP_SCRIPT" 2>/dev/null
        press_key
        return 1
    fi
    chmod +x "${SCRIPT_PATH}" || {
        colorize red "Failed to set execute permissions on ${SCRIPT_PATH}."
        press_key
        return 1
    }
    colorize green "ALEX Manager Script updated successfully."
    colorize yellow "Please re-run the script with 'ALEX' command to use the updated version."

    # Update alex-port-monitor.sh
    MONITOR_SCRIPT_URL="https://raw.githubusercontent.com/Alextaylorvhjnf/Alex-tunnel/main/tools/alex-port-monitor.sh"
    MONITOR_SCRIPT_PATH="${CONFIG_DIR}/tools/alex-port-monitor.sh"
    colorize yellow "Downloading updated alex-port-monitor.sh..."
    # Ensure the tools directory exists and has correct permissions
    if ! mkdir -p "${CONFIG_DIR}/tools"; then
        colorize red "Failed to create directory ${CONFIG_DIR}/tools."
        press_key
        return 1
    fi
    if ! chown root:root "${CONFIG_DIR}/tools" || ! chmod 755 "${CONFIG_DIR}/tools"; then
        colorize red "Failed to set permissions for ${CONFIG_DIR}/tools."
        press_key
        return 1
    fi
    # Check if the destination file is locked or in use
    if [[ -f "$MONITOR_SCRIPT_PATH" ]] && lsof "$MONITOR_SCRIPT_PATH" >/dev/null 2>&1; then
        colorize yellow "File ${MONITOR_SCRIPT_PATH} is in use. Attempting to stop processes..."
        pkill -f "alex-port-monitor.sh" 2>/dev/null || {
            colorize red "Failed to stop processes using ${MONITOR_SCRIPT_PATH}."
            press_key
            return 1
        }
    fi
    # Use a temporary file for downloading
    temp_monitor_file=$(mktemp)
    if ! curl -sSL -o "$temp_monitor_file" "$MONITOR_SCRIPT_URL"; then
        colorize red "Failed to download updated alex-port-monitor.sh. Check network or URL."
        rm -f "$temp_monitor_file" 2>/dev/null
        press_key
        return 1
    fi
    if ! grep -q "alex-port-monitor.sh" "$temp_monitor_file"; then
        colorize red "Downloaded alex-port-monitor.sh is invalid."
        rm -f "$temp_monitor_file" 2>/dev/null
        press_key
        return 1
    fi
    # Move the downloaded file to destination
    if ! mv "$temp_monitor_file" "$MONITOR_SCRIPT_PATH"; then
        colorize red "Failed to move downloaded file to ${MONITOR_SCRIPT_PATH}."
        rm -f "$temp_monitor_file" 2>/dev/null
        press_key
        return 1
    fi
    if ! chmod +x "$MONITOR_SCRIPT_PATH"; then
        colorize red "Failed to set execute permissions on ${MONITOR_SCRIPT_PATH}."
        press_key
        return 1
    fi
    colorize green "alex-port-monitor.sh updated successfully."

    press_key
    exit 0
}

# Function to check if a port is in use
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

# Function to validate IPv6 address
check_ipv6() {
    local ip=$1
    ip="${ip#[}"
    ip="${ip%]}"
    ipv6_pattern="^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(:[0-9a-fA-F]{1,4}){1,6}|:((:[0-9a-fA-F]{1,4}){1,7}|:))$"
    [[ $ip =~ $ipv6_pattern ]] && return 0 || return 1
}

# Function to validate IPv4 address
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

# Function to check for consecutive errors and restart
check_consecutive_errors() {
    local service_name="$1"
    local tunnel_name=$(echo "$service_name" | sed 's/ALEX-//;s/.service//')
    local logs=$(journalctl -u "$service_name" -n 50 --no-pager | tail -n 2)
    local error_count=$(echo "$logs" | grep -c "ERROR")
    if [[ $error_count -ge 2 ]]; then
        colorize yellow "Two consecutive errors detected in $service_name logs. Restarting..."
        systemctl restart "$service_name"
        if [[ $? -eq 0 ]]; then
            colorize green "Tunnel $tunnel_name restarted successfully due to consecutive errors."
        else
            colorize red "Failed to restart tunnel $tunnel_name."
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
        colorize red "Network interface $network_interface is not up."
        return 1
    fi

    if ! lsmod | grep -q vxlan; then
        colorize yellow "Loading VXLAN kernel module..."
        modprobe vxlan || { colorize red "Failed to load VXLAN module"; return 1; }
    fi

    if [[ "$local_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if ! ip -4 addr show dev "$network_interface" | grep -w "$local_ip" &> /dev/null; then
            colorize red "IP address $local_ip is not assigned to interface $network_interface."
            return 1
        fi
    elif [[ "$local_ip" =~ ^[0-9a-fA-F:]+$ ]]; then
        if ! ip -6 addr show dev "$network_interface" | grep -w "$local_ip" &> /dev/null; then
            colorize red "IP address $local_ip is not assigned to interface $network_interface."
            return 1
        fi
    else
        colorize red "Invalid IP address format: $local_ip"
        return 1
    fi

    return 0
}

# Function to configure Direct tunnel
direct_server_configuration() {
    clear
    colorize cyan "Configuring Direct Tunnel" bold
    echo
    colorize cyan "Select Server Type:" bold
    echo "1) Iran Server"
    echo "2) Kharej Server"
    read -p "Enter choice: " server_type
    case $server_type in
        1) configure_direct_iran ;;
        2) configure_direct_kharej ;;
        *) colorize red "Invalid option!" && press_key && return 1 ;;
    esac
}

# Function to update HAProxy configuration
update_haproxy_config() {
    local tunnel_name="$1"
    shift
    local ports=("$@")
    local kharej_bridge_ip="${ports[-1]}"
    unset 'ports[-1]'
    local haproxy_config="${HAPROXY_CFG:-/etc/haproxy/haproxy.cfg}"

    if [[ -z "$haproxy_config" ]]; then
        colorize red "HAProxy configuration path is not defined."
        return 1
    fi

    local haproxy_dir
    haproxy_dir=$(dirname "$haproxy_config")
    if [[ ! -d "$haproxy_dir" ]]; then
        mkdir -p "$haproxy_dir" || {
            colorize red "Failed to create HAProxy directory $haproxy_dir."
            return 1
        }
        chown haproxy:haproxy "$haproxy_dir" 2>/dev/null || {
            colorize yellow "Failed to set permissions for $haproxy_dir."
        }
    fi

    if [[ ! -f "$haproxy_config" ]]; then
        colorize yellow "HAProxy config file $haproxy_config not found. Creating with default settings..."
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
        if [[ ! -f "$haproxy_config" ]]; then
            colorize red "Failed to create HAProxy config file $haproxy_config."
            return 1
        fi
        chown haproxy:haproxy "$haproxy_config" 2>/dev/null || {
            colorize yellow "Failed to set permissions for $haproxy_config."
        }
    fi

    if ! cp "$haproxy_config" "${haproxy_config}.bak" 2>/dev/null; then
        colorize yellow "Failed to backup HAProxy config $haproxy_config."
    fi

    if ! sed -i "/#start:$tunnel_port/,/#end:$tunnel_port/d" "$haproxy_config" 2>/dev/null; then
        colorize yellow "Failed to remove existing HAProxy config for tunnel $tunnel_name."
    fi

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
        colorize red "Invalid HAProxy configuration. Restoring backup."
        if [[ -f "${haproxy_config}.bak" ]]; then
            cp "${haproxy_config}.bak" "$haproxy_config" 2>/dev/null || {
                colorize red "Failed to restore HAProxy backup."
            }
        fi
        return 1
    fi

    if ! systemctl restart haproxy >/dev/null 2>&1; then
        colorize red "Failed to restart HAProxy."
        if [[ -f "${haproxy_config}.bak" ]]; then
            cp "${haproxy_config}.bak" "$haproxy_config" 2>/dev/null || {
                colorize red "Failed to restore HAProxy backup."
            }
        fi
        return 1
    fi

    colorize green "HAProxy configuration updated successfully."
    return 0
}

# Function to remove HAProxy configuration for a tunnel
remove_haproxy_config() {
    local tunnel_name="$1"
    local haproxy_config="$HAPROXY_CFG"

    cp "$haproxy_config" "${haproxy_config}.bak" 2>/dev/null || { colorize yellow "Failed to backup HAProxy config"; }

    sed -i "/#start:$tunnel_port/,/#end:$tunnel_port/d" "$haproxy_config" 2>/dev/null

    if [[ -f "$haproxy_config" ]] && ! haproxy -c -f "$haproxy_config" >/dev/null 2>&1; then
        colorize red "Invalid HAProxy configuration after removal. Restoring backup."
        cp "${haproxy_config}.bak" "$haproxy_config" 2>/dev/null
        return 1
    fi

    systemctl restart haproxy || { colorize red "Failed to restart HAProxy"; return 1; }
    colorize green "HAProxy configuration for tunnel $tunnel_name removed."
    return 0
}

# Function to configure Direct tunnel for Iran server
configure_direct_iran() {
    read -p "[*] Enter tunnel name (e.g., direct-tunnel): " tunnel_name
    tunnel_name=$(echo "$tunnel_name" | tr ' ' '-' | tr -d '[:space:]')
    if [[ -z "$tunnel_name" ]]; then
        colorize red "Tunnel name cannot be empty."
        press_key
        return 1
    fi
    if [[ -f "${CONFIG_DIR}/direct-iran-${tunnel_name}.conf" ]]; then
        colorize red "Tunnel with name '$tunnel_name' already exists."
        press_key
        return 1
    fi

    echo "Iran server address type:"
    echo "1) IPv4"
    echo "2) IPv6"
    read -p "Enter choice: " ip_choice
    case $ip_choice in
        1) ip_type="ipv4" ;;
        2) ip_type="ipv6" ;;
        *) colorize red "Invalid option! Defaulting to IPv4"; ip_type="ipv4" ;;
    esac

    if [[ "$ip_type" == "ipv4" ]]; then
        local_ip=$(ip -4 addr show $(detect_network_interface) | grep inet | awk '{print $2}' | cut -d'/' -f1)
    else
        local_ip=$(ip -6 addr show $(detect_network_interface) | grep inet6 | grep global | awk '{print $2}' | cut -d'/' -f1)
    fi
    if [[ -z "$local_ip" ]]; then
        colorize red "Server IP could not be detected."
        press_key
        return 1
    fi
    colorize green "Iran server address: $local_ip"

    read -p "[*] Enter Kharej server IP (IPv4 or [IPv6]): " remote_ip
    if [[ -z "$remote_ip" ]]; then
        colorize red "Server address cannot be empty."
        press_key
        return 1
    fi
    if check_ipv6 "$remote_ip"; then
        remote_ip="${remote_ip#[}"
        remote_ip="${remote_ip%]}"
    elif ! check_ipv4 "$remote_ip"; then
        colorize red "Invalid IP address format."
        press_key
        return 1
    fi

    while true; do
        read -p "[*] Enter tunnel port (e.g., 4790): " tunnel_port
        if [[ "$tunnel_port" =~ ^[0-9]+$ ]] && [ "$tunnel_port" -gt 22 ] && [ "$tunnel_port" -le 65535 ]; then
            if check_port "$tunnel_port" "udp"; then
                colorize red "Port $tunnel_port is in use."
            else
                break
            fi
        else
            colorize red "Enter a valid port (23-65535)"
        fi
    done

    while true; do
        read -p "[*] Enter VXLAN ID (1-16777215): " vxlan_id
        if [[ "$vxlan_id" =~ ^[0-9]+$ ]] && [ "$vxlan_id" -ge 1 ] && [ "$vxlan_id" -le 16777215 ]; then
            if ip link show "vxlan${vxlan_id}" >/dev/null 2>&1; then
                colorize red "VXLAN ID $vxlan_id is already in use."
            else
                break
            fi
        else
            colorize red "Enter a valid VXLAN ID (1-16777215)"
        fi
    done

    network_interface=$(detect_network_interface)
    colorize green "Detected network interface: $network_interface"

    read -p "[*] Enter Iran bridge IP address (default: 10.0.10.1): " iran_bridge_ip
    if [[ -z "$iran_bridge_ip" ]]; then
        iran_bridge_ip="10.0.10.1"
    fi
    if [[ ! "$iran_bridge_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        colorize red "Invalid bridge IP address (must be in format 10.0.10.x)."
        press_key
        return 1
    fi
    iran_bridge_ip="${iran_bridge_ip}/24"
    colorize green "Iran bridge IP: $iran_bridge_ip"

    read -p "[*] Enter Kharej bridge IP address (default: 10.0.10.2): " kharej_bridge_ip
    if [[ -z "$kharej_bridge_ip" ]]; then
        kharej_bridge_ip="10.0.10.2"
    fi
    if [[ ! "$kharej_bridge_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        colorize red "Invalid bridge IP address (must be in format 10.0.10.x)."
        press_key
        return 1
    fi
    kharej_bridge_ip="${kharej_bridge_ip}/24"
    colorize green "Kharej bridge IP: $kharej_bridge_ip"

    ip link delete "vxlan${vxlan_id}" 2>/dev/null
    ip link delete "br${vxlan_id}" 2>/dev/null
    ip addr flush dev "br${vxlan_id}" 2>/dev/null

    if ! validate_vxlan_setup "$local_ip" "$remote_ip" "$tunnel_port" "$network_interface" "$vxlan_id"; then
        press_key
        return 1
    fi

    read -p "[*] Enter service ports (e.g., 8080,40001): " input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports
    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 22 ] && [ "$port" -le 65535 ]; then
            if check_port "$port" "tcp"; then
                colorize red "Port $port is in use."
            else
                config_ports+=("$port")
                colorize green "Port $port added."
            fi
        else
            colorize red "Port $port is invalid. Must be between 23-65535."
        fi
    done
    if [[ ${#config_ports[@]} -eq 0 ]]; then
        colorize red "No valid ports entered. Exiting..."
        sleep 2
        return 1
    fi

    ip link add vxlan${vxlan_id} type vxlan id "$vxlan_id" local "$local_ip" remote "$remote_ip" dstport "$tunnel_port" dev "$network_interface" || {
        colorize red "Failed to create VXLAN interface."
        press_key
        return 1
    }
    ip link add name br${vxlan_id} type bridge || {
        colorize red "Failed to create bridge."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        press_key
        return 1
    }
    ip link set vxlan${vxlan_id} master br${vxlan_id} || {
        colorize red "Failed to attach VXLAN to bridge."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        ip link delete br${vxlan_id} 2>/dev/null
        press_key
        return 1
    }
    ip link set br${vxlan_id} up || {
        colorize red "Failed to bring up bridge."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        ip link delete br${vxlan_id} 2>/dev/null
        press_key
        return 1
    }
    ip link set vxlan${vxlan_id} up || {
        colorize red "Failed to bring up VXLAN."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        ip link delete br${vxlan_id} 2>/dev/null
        press_key
        return 1
    }
    ip addr flush dev br${vxlan_id} 2>/dev/null
    ip addr add "$iran_bridge_ip" dev br${vxlan_id} || {
        colorize red "Failed to assign IP to bridge."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        ip link delete br${vxlan_id} 2>/dev/null
        press_key
        return 1
    }

    if ! update_haproxy_config "$tunnel_name" "${config_ports[@]}" "$kharej_bridge_ip"; then
        colorize red "Failed to update HAProxy configuration."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        ip link delete br${vxlan_id} 2>/dev/null
        press_key
        return 1
    fi

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

    systemctl daemon-reload || {
        colorize red "Failed to reload systemd"
        press_key
        return 1
    }
    systemctl enable "ALEX-direct-iran-${tunnel_name}.service" || {
        colorize red "Failed to enable service"
        press_key
        return 1
    }
    systemctl start "ALEX-direct-iran-${tunnel_name}.service" || {
        colorize red "Failed to start service. Check 'systemctl status ALEX-direct-iran-${tunnel_name}.service' for details"
        press_key
        return 1
    }

    # Start bandwidth monitoring for direct tunnel port (Iran server only)
    if [[ -f "${CONFIG_DIR}/tools/alex-port-monitor.sh" ]]; then
        ${CONFIG_DIR}/tools/alex-port-monitor.sh addport "$tunnel_port" "udp"
        ${CONFIG_DIR}/tools/alex-port-monitor.sh install
    fi

    colorize green "Direct tunnel configuration for Iran server '$tunnel_name' completed."
    colorize green "Iran bridge IP: ${iran_bridge_ip}"
    colorize green "Kharej bridge IP to use: ${kharej_bridge_ip}"
    press_key
    return 0
}

# Function to configure Direct tunnel for Kharej server
configure_direct_kharej() {
    read -p "[*] Enter tunnel name (e.g., direct-tunnel): " tunnel_name
    tunnel_name=$(echo "$tunnel_name" | tr ' ' '-' | tr -d '[:space:]')
    if [[ -z "$tunnel_name" ]]; then
        colorize red "Tunnel name cannot be empty."
        press_key
        return 1
    fi
    if [[ -f "${CONFIG_DIR}/direct-kharej-${tunnel_name}.conf" ]]; then
        colorize red "Tunnel with name '$tunnel_name' already exists."
        press_key
        return 1
    fi

    echo "Kharej server address type:"
    echo "1) IPv4"
    echo "2) IPv6"
    read -p "Enter choice: " ip_choice
    case $ip_choice in
        1) ip_type="ipv4" ;;
        2) ip_type="ipv6" ;;
        *) colorize red "Invalid option! Defaulting to IPv4"; ip_type="ipv4" ;;
    esac

    if [[ "$ip_type" == "ipv4" ]]; then
        local_ip=$(ip -4 addr show $(detect_network_interface) | grep inet | awk '{print $2}' | cut -d'/' -f1)
    else
        local_ip=$(ip -6 addr show $(detect_network_interface) | grep inet6 | grep global | awk '{print $2}' | cut -d'/' -f1)
    fi
    if [[ -z "$local_ip" ]]; then
        colorize red "Server IP could not be detected."
        press_key
        return 1
    fi
    colorize green "Kharej server address: $local_ip"

    read -p "[*] Enter Iran server IP (IPv4 or [IPv6]): " remote_ip
    [[ -z "$remote_ip" ]] && { colorize red "Server address cannot be empty."; press_key; return 1; }
    if check_ipv6 "$remote_ip"; then
        remote_ip="${remote_ip#[}"
        remote_ip="${remote_ip%]}"
    elif ! check_ipv4 "$remote_ip"; then
        colorize red "Invalid IP address format."
        press_key
        return 1
    fi

    while true; do
        read -p "[*] Enter tunnel port (e.g., 4790): " tunnel_port
        if [[ "$tunnel_port" =~ ^[0-9]+$ ]] && [ "$tunnel_port" -gt 22 ] && [ "$tunnel_port" -le 65535 ]; then
            if check_port "$tunnel_port" "udp"; then
                colorize red "Port $tunnel_port is in use."
            else
                break
            fi
        else
            colorize red "Enter a valid port (23-65535)"
        fi
    done

    while true; do
        read -p "[*] Enter VXLAN ID (1-16777215): " vxlan_id
        if [[ "$vxlan_id" =~ ^[0-9]+$ ]] && [ "$vxlan_id" -ge 1 ] && [ "$vxlan_id" -le 16777215 ]; then
            if ip link show "vxlan${vxlan_id}" >/dev/null 2>&1; then
                colorize red "VXLAN ID $vxlan_id is already in use."
            else
                break
            fi
        else
            colorize red "Enter a valid VXLAN ID (1-16777215)"
        fi
    done

    network_interface=$(detect_network_interface)
    colorize green "Detected network interface: $network_interface"

    read -p "[*] Enter Kharej bridge IP address (default: 10.0.10.2): " bridge_ip
    [[ -z "$bridge_ip" ]] && bridge_ip="10.0.10.2"
    if [[ ! "$bridge_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        colorize red "Invalid bridge IP address (must be in format 10.0.10.x)."
        press_key
        return 1
    fi
    bridge_ip="${bridge_ip}/24"
    colorize green "Kharej bridge IP: $bridge_ip"

    ip link delete "vxlan${vxlan_id}" 2>/dev/null
    ip link delete "br${vxlan_id}" 2>/dev/null
    ip addr flush dev "br${vxlan_id}" 2>/dev/null

    if ! validate_vxlan_setup "$local_ip" "$remote_ip" "$tunnel_port" "$network_interface" "$vxlan_id"; then
        press_key
        return 1
    fi

    ip link add vxlan${vxlan_id} type vxlan id $vxlan_id local "$local_ip" remote "$remote_ip" dstport "$tunnel_port" dev "$network_interface" || {
        colorize red "Failed to create VXLAN interface."
        press_key
        return 1
    }
    ip link add name br${vxlan_id} type bridge || {
        colorize red "Failed to create bridge."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        press_key
        return 1
    }
    ip link set vxlan${vxlan_id} master br${vxlan_id} || {
        colorize red "Failed to attach VXLAN to bridge."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        ip link delete br${vxlan_id} 2>/dev/null
        press_key
        return 1
    }
    ip link set br${vxlan_id} up || {
        colorize red "Failed to bring up bridge."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        ip link delete br${vxlan_id} 2>/dev/null
        press_key
        return 1
    }
    ip link set vxlan${vxlan_id} up || {
        colorize red "Failed to bring up VXLAN."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        ip link delete br${vxlan_id} 2>/dev/null
        press_key
        return 1
    }
    ip addr flush dev br${vxlan_id} 2>/dev/null
    ip addr add "${bridge_ip}" dev br${vxlan_id} || {
        colorize red "Failed to assign IP to bridge."
        ip link delete vxlan${vxlan_id} 2>/dev/null
        ip link delete br${vxlan_id} 2>/dev/null
        press_key
        return 1
    }

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

    systemctl daemon-reload || { colorize red "Failed to reload systemd"; press_key; return 1; }
    systemctl enable "ALEX-direct-kharej-${tunnel_name}.service" || { colorize red "Failed to enable service"; press_key; return 1; }
    systemctl start "ALEX-direct-kharej-${tunnel_name}.service" || { colorize red "Failed to start service. Check 'systemctl status ALEX-direct-kharej-${tunnel_name}.service' for details"; press_key; return 1; }
    colorize green "Direct tunnel configuration for Kharej server '$tunnel_name' completed."
    colorize green "Bridge IP assigned: ${bridge_ip}"
    press_key
    return 0
}

# Function to configure Iran server
iran_server_configuration() {
    clear
    colorize cyan "Configuring Iran Server" bold
    echo

    read -p "[*] Enter tunnel name (e.g., main-tunnel): " tunnel_name
    tunnel_name=$(echo "$tunnel_name" | tr ' ' '-' | tr -d '[:space:]')
    if [[ -z "$tunnel_name" ]]; then
        colorize red "Tunnel name cannot be empty."
        press_key
        return 1
    fi
    if [[ -f "${CONFIG_DIR}/iran-${tunnel_name}.toml" ]]; then
        colorize red "Tunnel with name '$tunnel_name' already exists."
        press_key
        return 1
    fi

    local_ip="0.0.0.0"
    echo "Iran server address:"
    echo "1) IPv4"
    echo "2) IPv6"
    read -p "Enter choice: " ip_choice
    case $ip_choice in
        1) colorize yellow "IPv4 enabled" ;;
        2) colorize yellow "IPv6 enabled"; local_ip="[::]" ;;
        *) colorize red "Invalid option! Defaulting to IPv4"; local_ip="0.0.0.0" ;;
    esac

    while true; do
        read -p "[*] Enter tunnel port (e.g., 443): " tunnel_port
        if [[ "$tunnel_port" =~ ^[0-9]+$ ]] && [ "$tunnel_port" -gt 22 ] && [ "$tunnel_port" -le 65535 ]; then
            if check_port "$tunnel_port" "tcp"; then
                colorize red "Port $tunnel_port is in use."
            else
                break
            fi
        else
            colorize red "Enter a valid port (23-65535)"
        fi
    done

    local transport=""
    echo "Transport type:"
    echo "1) TCP"
    echo "2) UDP"
    read -p "Enter choice: " transport_choice
    case $transport_choice in
        1) transport="tcp" ;;
        2) transport="udp" ;;
        *) colorize red "Invalid option! Defaulting to TCP"; transport="tcp" ;;
    esac

    local nodelay=""
    read -p "[*] Enable TCP_NODELAY (true/false, press enter for true): " nodelay
    [[ -z "$nodelay" ]] && nodelay="true"
    while [[ "$nodelay" != "true" && "$nodelay" != "false" ]]; do
        read -p "[*] Enable TCP_NODELAY (true/false): " nodelay
        [[ -z "$nodelay" ]] && nodelay="true"
        [[ "$nodelay" != "true" && "$nodelay" != "false" ]] && colorize red "Enter true or false"
    done

    local heartbeat="0"
    colorize yellow "Heartbeat disabled for high connection stability."

    read -p "[-] Security token (press enter for default 'ALEX'): " token
    [[ -z "$token" ]] && token="ALEX"

    read -p "[*] Enter service ports (e.g., 8008,8080): " input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports
    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 22 ] && [ "$port" -le 65535 ]; then
            if check_port "$port" "$transport"; then
                colorize red "Port $port is in use."
            else
                config_ports+=("$port")
                colorize green "Port $port added."
            fi
        else
            colorize red "Port $port is invalid. Must be between 23-65535."
        fi
    done
    [[ ${#config_ports[@]} -eq 0 ]] && { colorize red "No valid ports entered. Exiting..."; sleep 2; return 1; }

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
    systemctl enable --now "ALEX-iran-${tunnel_name}.service" || { colorize red "Failed to enable service"; return 1; }

    # Start bandwidth monitoring for reverse tunnel port (Iran server only)
    if [[ -f "${CONFIG_DIR}/tools/alex-port-monitor.sh" ]]; then
        ${CONFIG_DIR}/tools/alex-port-monitor.sh addport "$tunnel_port" "$transport"
        ${CONFIG_DIR}/tools/alex-port-monitor.sh install
    fi

    colorize green "Iran server configuration for tunnel '$tunnel_name' completed."
    press_key
    return 0
}

# Function to configure Kharej server
kharej_server_configuration() {
    clear
    colorize cyan "Configuring Kharej Server" bold
    echo

    read -p "[*] Enter tunnel name (e.g., main-tunnel): " tunnel_name
    tunnel_name=$(echo "$tunnel_name" | tr ' ' '-' | tr -d '[:space:]')
    if [[ -z "$tunnel_name" ]]; then
        colorize red "Tunnel name cannot be empty."
        press_key
        return 1
    fi
    if [[ -f "${CONFIG_DIR}/kharej-${tunnel_name}.toml" ]]; then
        colorize red "Tunnel with name '$tunnel_name' already exists."
        press_key
        return 1
    fi

    read -p "[*] Enter Iran server IP (IPv4 or [IPv6]): " server_addr
    [[ -z "$server_addr" ]] && { colorize red "Server address cannot be empty."; press_key; return 1; }
    if check_ipv6 "$server_addr"; then
        server_addr="${server_addr#[}"
        server_addr="${server_addr%]}"
    elif ! check_ipv4 "$server_addr"; then
        colorize red "Invalid IP address format."
        press_key
        return 1
    fi

    while true; do
        read -p "[*] Enter tunnel port (e.g., 443): " tunnel_port
        if [[ "$tunnel_port" =~ ^[0-9]+$ ]] && [ "$tunnel_port" -gt 22 ] && [ "$tunnel_port" -le 65535 ]; then
            break
        else
            colorize red "Enter a valid port (23-65535)"
        fi
    done

    local transport=""
    echo "Transport type:"
    echo "1) TCP"
    echo "2) UDP"
    read -p "Enter choice: " transport_choice
    case $transport_choice in
        1) transport="tcp" ;;
        2) transport="udp" ;;
        *) colorize red "Invalid option! Defaulting to TCP"; transport="tcp" ;;
    esac

    local nodelay=""
    read -p "[*] Enable TCP_NODELAY (true/false, press enter for true): " nodelay
    [[ -z "$nodelay" ]] && nodelay="true"
    while [[ "$nodelay" != "true" && "$nodelay" != "false" ]]; do
        read -p "[*] Enable TCP_NODELAY (true/false): " nodelay
        [[ -z "$nodelay" ]] && nodelay="true"
        [[ "$nodelay" != "true" && "$nodelay" != "false" ]] && colorize red "Enter true or false"
    done

    local heartbeat="0"
    colorize yellow "Heartbeat disabled for high connection stability."

    read -p "[-] Security token (press enter for default 'ALEX'): " token
    [[ -z "$token" ]] && token="ALEX"

    read -p "[*] Enter service ports (e.g., 8008,8080): " input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports
    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 22 ] && [ "$port" -le 65535 ]; then
            config_ports+=("$port")
            colorize green "Port $port added."
        else
            colorize red "Port $port is invalid. Must be between 23-65535."
        fi
    done
    [[ ${#config_ports[@]} -eq 0 ]] && { colorize red "No valid ports entered. Exiting..."; sleep 2; return 1; }

    local_ip="127.0.0.1"

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
    systemctl enable --now "ALEX-kharej-${tunnel_name}.service" || { colorize red "Failed to enable service"; return 1; }
    colorize green "Kharej server configuration for tunnel '$tunnel_name' completed."
    press_key
    return 0
}

# Function to edit tunnel
edit_tunnel() {
    local config_path="$1"
    local tunnel_type="$2"
    local tunnel_name=$(basename "${config_path%.toml}" "${config_path%.conf}" | sed 's/iran-//;s/kharej-//;s/direct-iran-//;s/direct-kharej-//')
    clear
    colorize cyan "Editing tunnel $tunnel_name ($tunnel_type)" bold
    echo
    if [[ "$tunnel_type" == "iran" ]]; then
        echo "1) Edit tunnel port"
        echo "2) Edit tunnel service ports"
        echo "3) Edit security token"
        echo "4) Add new ports to tunnel"
    elif [[ "$tunnel_type" == "kharej" ]]; then
        echo "1) Edit tunnel port"
        echo "2) Edit tunnel service ports"
        echo "3) Edit security token"
        echo "4) Add new ports to tunnel"
        echo "5) Edit Iran IP"
    elif [[ "$tunnel_type" == "direct-iran" ]]; then
        echo "1) Edit tunnel port"
        echo "2) Edit remote server IP"
        echo "3) Edit HAProxy ports"
        echo "4) Edit Iran bridge IP"
        echo "5) Edit Kharej bridge IP"
    else
        echo "1) Edit tunnel port"
        echo "2) Edit remote server IP"
        echo "3) Edit Kharej bridge IP"
    fi
    read -p "Enter choice (0 to return): " edit_choice
    case $edit_choice in
        1) edit_tunnel_port "$config_path" "$tunnel_type" "$tunnel_name" ;;
        2) [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "direct-kharej" ]] && edit_remote_ip "$config_path" "$tunnel_type" "$tunnel_name" || edit_config_port "$config_path" "$tunnel_type" "$tunnel_name" ;;
        3) [[ "$tunnel_type" == "direct-iran" ]] && edit_haproxy_ports "$config_path" "$tunnel_type" "$tunnel_name" || [[ "$tunnel_type" == "direct-kharej" ]] && edit_kharej_bridge_ip "$config_path" "$tunnel_type" "$tunnel_name" || edit_security_token "$config_path" "$tunnel_type" "$tunnel_name" ;;
        4) [[ "$tunnel_type" == "direct-iran" ]] && edit_iran_bridge_ip "$config_path" "$tunnel_type" "$tunnel_name" || add_new_ports "$config_path" "$tunnel_type" "$tunnel_name" ;;
        5) [[ "$tunnel_type" == "direct-iran" ]] && edit_kharej_bridge_ip "$config_path" "$tunnel_type" "$tunnel_name" || [[ "$tunnel_type" == "kharej" ]] && edit_iran_ip "$config_path" "$tunnel_name" || { colorize red "Invalid option!"; sleep 1; } ;;
        0) return ;;
        *) colorize red "Invalid option!" && sleep 1 ;;
    esac
    service_name="ALEX-${tunnel_type}-${tunnel_name}.service"
    systemctl restart "$service_name" || { colorize red "Failed to restart service after edit"; press_key; return 1; }
    if [[ "$tunnel_type" == "direct-iran" ]] && [[ -f "/etc/haproxy/haproxy-${tunnel_name}.cfg" ]]; then
        systemctl restart haproxy || { colorize red "Failed to restart HAProxy"; return 1; }
    fi
}

# Function to edit tunnel port
edit_tunnel_port() {
    local config_path="$1"
    local tunnel_type="$2"
    local tunnel_name="$3"
    while true; do
        read -p "[*] Enter new tunnel port (e.g., 4789): " new_port
        if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -gt 22 ] && [ "$new_port" -le 65535 ]; then
            if [[ "$tunnel_type" == "iran" || "$tunnel_type" == "direct-iran" || "$tunnel_type" == "direct-kharej" ]] && check_port "$new_port" "udp"; then
                colorize red "Port $new_port is in use."
            else
                break
            fi
        else
            colorize red "Enter a valid port (23-65535)"
        fi
    done
    if [[ "$tunnel_type" == "iran" ]]; then
        local_ip=$(grep "bind_addr = " "$config_path" | head -n 1 | cut -d'"' -f2 | cut -d':' -f1)
        sed -i "s/bind_addr = \".*:.*\"/bind_addr = \"${local_ip}:${new_port}\"/" "$config_path" || { colorize red "Failed to update tunnel port"; return 1; }
    elif [[ "$tunnel_type" == "kharej" ]]; then
        server_addr=$(grep "remote_addr = " "$config_path" | cut -d'"' -f2 | cut -d':' -f1)
        sed -i "s/remote_addr = \".*\"/remote_addr = \"${server_addr}:${new_port}\"/" "$config_path" || { colorize red "Failed to update tunnel port"; return 1; }
    else
        sed -i "s/dstport=.*/dstport=$new_port/" "$config_path" || { colorize red "Failed to update tunnel port"; return 1; }
        vxlan_id=$(grep "^vxlan_id=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
        local_ip=$(grep "^local_ip=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
        remote_ip=$(grep "^remote_ip=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
        network_interface=$(grep "^network_interface=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
        bridge_ip=$(grep "^\(iran_bridge_ip\|kharej_bridge_ip\|bridge_ip\)=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
        service_file="${SERVICE_DIR}/ALEX-${tunnel_type}-${tunnel_name}.service"
        cat << EOF > "$service_file"
[Unit]
Description=ALEX ${tunnel_type} Tunnel $tunnel_name
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "ip link show vxlan${vxlan_id} >/dev/null 2>&1 || ip link add vxlan${vxlan_id} type vxlan id ${vxlan_id} local $local_ip remote $remote_ip dstport $new_port dev $network_interface; ip link show br${vxlan_id} >/dev/null 2>&1 || ip link add name br${vxlan_id} type bridge; ip link set vxlan${vxlan_id} master br${vxlan_id}; ip link set br${vxlan_id} up; ip link set vxlan${vxlan_id} up; ip addr flush dev br${vxlan_id} 2>/dev/null; ip addr add ${bridge_ip} dev br${vxlan_id}$([[ "$tunnel_type" == "direct-iran" ]] && echo "; systemctl restart haproxy" || echo "")"
ExecStop=/bin/bash -c "ip link delete vxlan${vxlan_id} 2>/dev/null; ip link delete br${vxlan_id} 2>/dev/null$([[ "$tunnel_type" == "direct-iran" ]] && echo "; systemctl restart haproxy" || echo "")"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi
    colorize green "Tunnel port updated to $new_port."
    press_key
}

# Function to edit config port
edit_config_port() {
    local config_path="$1"
    local tunnel_type="$2"
    local tunnel_name=$(basename "${config_path%.toml}" | sed 's/iran-//;s/kharej-//')
    read -p "[*] Enter current service port to edit (e.g., 8008): " old_port
    if ! grep -q "service${old_port}" "$config_path"; then
        colorize red "Service port $old_port not found."
        press_key
        return 1
    fi
    read -p "[*] Enter new service port (e.g., 8080): " new_port
    if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -gt 22 ] && [ "$new_port" -le 65535 ]; then
        if [[ "$tunnel_type" == "iran" ]] && check_port "$new_port" "tcp"; then
            colorize red "Port $new_port is in use."
            press_key
            return 1
        fi
    else
        colorize red "Port $new_port is invalid."
        press_key
        return 1
    fi
    if [[ "$tunnel_type" == "iran" ]]; then
        sed -i "s/\[server\.services\.service${old_port}\]/\[server\.services\.service${new_port}\]/" "$config_path"
        sed -i "s/bind_addr = \".*:${old_port}\"/bind_addr = \"${local_ip}:${new_port}\"/" "$config_path"
    else
        sed -i "s/\[client\.services\.service${old_port}\]/\[client\.services\.service${new_port}\]/" "$config_path"
        sed -i "s/local_addr = \".*:${old_port}\"/local_addr = \"${local_ip}:${new_port}\"/" "$config_path"
    fi
    colorize green "Service port updated from $old_port to $new_port."
    press_key
}

# Function to edit security token
edit_security_token() {
    local config_path="$1"
    local tunnel_type="$2"
    local tunnel_name=$(basename "${config_path%.toml}" | sed 's/iran-//;s/kharej-//')
    read -p "[*] Enter new security token (press enter for default 'ALEX'): " new_token
    [[ -z "$new_token" ]] && new_token="ALEX"
    sed -i "s/default_token = \".*\"/default_token = \"$new_token\"/" "$config_path"
    sed -i "s/token = \".*\"/token = \"$new_token\"/" "$config_path"
    colorize green "Security token updated to $new_token."
    press_key
}

# Function to edit remote IP for direct tunnel
edit_remote_ip() {
    local config_path="$1"
    local tunnel_type="$2"
    local tunnel_name=$(basename "${config_path%.conf}" | sed 's/direct-iran-//;s/direct-kharej-//')
    read -p "[*] Enter new remote server IP (IPv4 or [IPv6]): " new_ip
    [[ -z "$new_ip" ]] && { colorize red "Server address cannot be empty."; press_key; return 1; }
    if check_ipv6 "$new_ip"; then
        new_ip="${new_ip#[}"
        new_ip="${new_ip%]}"
    elif ! check_ipv4 "$new_ip"; then
        colorize red "Invalid IP address format."
        press_key
        return 1
    fi
    sed -i "s/remote_ip=.*/remote_ip=$new_ip/" "$config_path" || { colorize red "Failed to update remote server IP"; return 1; }
    vxlan_id=$(grep "^vxlan_id=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    local_ip=$(grep "^local_ip=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    dstport=$(grep "^dstport=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    network_interface=$(grep "^network_interface=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    bridge_ip=$(grep "^\(iran_bridge_ip\|kharej_bridge_ip\|bridge_ip\)=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    service_file="${SERVICE_DIR}/ALEX-${tunnel_type}-${tunnel_name}.service"
    cat << EOF > "$service_file"
[Unit]
Description=ALEX ${tunnel_type} Tunnel $tunnel_name
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "ip link show vxlan${vxlan_id} >/dev/null 2>&1 || ip link add vxlan${vxlan_id} type vxlan id ${vxlan_id} local $local_ip remote $new_ip dstport $dstport dev $network_interface; ip link show br${vxlan_id} >/dev/null 2>&1 || ip link add name br${vxlan_id} type bridge; ip link set vxlan${vxlan_id} master br${vxlan_id}; ip link set br${vxlan_id} up; ip link set vxlan${vxlan_id} up; ip addr flush dev br${vxlan_id} 2>/dev/null; ip addr add ${bridge_ip} dev br${vxlan_id}$([[ "$tunnel_type" == "direct-iran" ]] && echo "; systemctl restart haproxy" || echo "")"
ExecStop=/bin/bash -c "ip link delete vxlan${vxlan_id} 2>/dev/null; ip link delete br${vxlan_id} 2>/dev/null$([[ "$tunnel_type" == "direct-iran" ]] && echo "; systemctl restart haproxy" || echo "")"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    colorize green "Remote server IP updated to $new_ip."
    press_key
}

# Function to edit HAProxy ports (Iran only)
edit_haproxy_ports() {
    local config_path="$1"
    local tunnel_type="$2"
    local tunnel_name=$(basename "${config_path%.conf}" | sed 's/direct-iran-//')
    if [[ "$tunnel_type" != "direct-iran" ]]; then
        colorize red "This option is only available for direct Iran tunnels."
        press_key
        return 1
    fi
    read -p "[*] Enter new HAProxy ports (e.g., 8008,8080): " input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports
    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 22 ] && [ "$port" -le 65535 ]; then
            if check_port "$port" "tcp"; then
                colorize red "Port $port is in use."
            else
                config_ports+=("$port")
                colorize green "Port $port added."
            fi
        else
            colorize red "Port $port is invalid. Must be between 23-65535."
        fi
    done
    if [[ ${#config_ports[@]} -eq 0 ]]; then
        colorize red "No valid ports entered."
        sleep 2
        return 1
    fi
    kharej_bridge_ip=$(grep "kharej_bridge_ip" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    if ! update_haproxy_config "$tunnel_name" "${config_ports[@]}" "$kharej_bridge_ip"; then
        colorize red "Failed to update HAProxy configuration."
        return 1
    fi
    sed -i "s/ports=.*/ports=${input_ports}/" "$config_path" || {
        colorize red "Failed to update ports in config"
        return 1
    }
    colorize green "HAProxy ports updated successfully."
    press_key
    return 0
}

# Function to edit Iran bridge IP (Iran only)
edit_iran_bridge_ip() {
    local config_path="$1"
    local tunnel_type="$2"
    local tunnel_name=$(basename "${config_path%.conf}" | sed 's/direct-iran-//')
    read -p "[*] Enter new Iran bridge IP address (default: 10.0.10.1): " new_bridge_ip
    [[ -z "$new_bridge_ip" ]] && new_bridge_ip="10.0.10.1"
    if [[ ! "$new_bridge_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        colorize red "Invalid bridge IP address (must be in format 10.0.10.x)."
        press_key
        return 1
    fi
    new_bridge_ip="${new_bridge_ip}/24"
    sed -i "s/iran_bridge_ip=.*/iran_bridge_ip=$new_bridge_ip/" "$config_path" || { colorize red "Failed to update Iran bridge IP"; return 1; }
    vxlan_id=$(grep "^vxlan_id=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    local_ip=$(grep "^local_ip=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    remote_ip=$(grep "^remote_ip=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    dstport=$(grep "^dstport=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    network_interface=$(grep "^network_interface=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    service_file="${SERVICE_DIR}/ALEX-${tunnel_type}-${tunnel_name}.service"
    cat << EOF > "$service_file"
[Unit]
Description=ALEX ${tunnel_type} Tunnel $tunnel_name
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "ip link show vxlan${vxlan_id} >/dev/null 2>&1 || ip link add vxlan${vxlan_id} type vxlan id ${vxlan_id} local $local_ip remote $remote_ip dstport $dstport dev $network_interface; ip link show br${vxlan_id} >/dev/null 2>&1 || ip link add name br${vxlan_id} type bridge; ip link set vxlan${vxlan_id} master br${vxlan_id}; ip link set br${vxlan_id} up; ip link set vxlan${vxlan_id} up; ip addr flush dev br${vxlan_id} 2>/dev/null; ip addr add ${new_bridge_ip} dev br${vxlan_id}; systemctl restart haproxy"
ExecStop=/bin/bash -c "ip link delete vxlan${vxlan_id} 2>/dev/null; ip link delete br${vxlan_id} 2>/dev/null; systemctl restart haproxy"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    colorize green "Iran bridge IP updated to $new_bridge_ip."
    press_key
}

# Function to edit Kharej bridge IP
edit_kharej_bridge_ip() {
    local config_path="$1"
    local tunnel_type="$2"
    local tunnel_name=$(basename "${config_path%.conf}" | sed 's/direct-iran-//;s/direct-kharej-//')
    local ip_key="bridge_ip"
    local default_bridge_ip="10.0.10.2"
    if [[ "$tunnel_type" == "direct-iran" ]]; then
        ip_key="kharej_bridge_ip"
        default_bridge_ip="10.0.10.2"
    fi
    read -p "[*] Enter new Kharej bridge IP address (default: $default_bridge_ip): " new_bridge_ip
    [[ -z "$new_bridge_ip" ]] && new_bridge_ip="$default_bridge_ip"
    if [[ ! "$new_bridge_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        colorize red "Invalid bridge IP address (must be in format 10.0.10.x)."
        press_key
        return 1
    fi
    new_bridge_ip="${new_bridge_ip}/24"
    sed -i "s/${ip_key}=.*/${ip_key}=$new_bridge_ip/" "$config_path" || { colorize red "Failed to update Kharej bridge IP"; return 1; }
    vxlan_id=$(grep "^vxlan_id=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    local_ip=$(grep "^local_ip=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    remote_ip=$(grep "^remote_ip=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    dstport=$(grep "^dstport=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    network_interface=$(grep "^network_interface=" "$config_path" | cut -d'=' -f2 | tr -d ' ')
    service_file="${SERVICE_DIR}/ALEX-${tunnel_type}-${tunnel_name}.service"
    cat << EOF > "$service_file"
[Unit]
Description=ALEX ${tunnel_type} Tunnel $tunnel_name
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "ip link show vxlan${vxlan_id} >/dev/null 2>&1 || ip link add vxlan${vxlan_id} type vxlan id ${vxlan_id} local $local_ip remote $remote_ip dstport $dstport dev $network_interface; ip link show br${vxlan_id} >/dev/null 2>&1 || ip link add name br${vxlan_id} type bridge; ip link set vxlan${vxlan_id} master br${vxlan_id}; ip link set br${vxlan_id} up; ip link set vxlan${vxlan_id} up; ip addr flush dev br${vxlan_id} 2>/dev/null; ip addr add ${new_bridge_ip} dev br${vxlan_id}$([[ "$tunnel_type" == "direct-iran" ]] && echo "; systemctl restart haproxy" || echo "")"
ExecStop=/bin/bash -c "ip link delete vxlan${vxlan_id} 2>/dev/null; ip link delete br${vxlan_id} 2>/dev/null$([[ "$tunnel_type" == "direct-iran" ]] && echo "; systemctl restart haproxy" || echo "")"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    colorize green "Kharej bridge IP updated to $new_bridge_ip."
    if [[ "$tunnel_type" == "direct-iran" ]]; then
        haproxy_config="/etc/haproxy/haproxy-${tunnel_name}.cfg"
        if [[ -f "$haproxy_config" ]]; then
            sed -i "s/server ALEX_server .*:.* check/server ALEX_server ${new_bridge_ip%/*}:%PORT% check/" "$haproxy_config" || { colorize red "Failed to update HAProxy config"; return 1; }
            systemctl restart haproxy || { colorize red "Failed to restart HAProxy"; return 1; }
        fi
    fi
    press_key
}

# Function to add new ports
add_new_ports() {
    local config_path="$1"
    local tunnel_type="$2"
    local tunnel_name=$(basename "${config_path%.toml}" | sed 's/iran-//;s/kharej-//')
    read -p "[*] Enter new service ports to add (e.g., 8081,8082): " input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports
    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 22 ] && [ "$port" -le 65535 ]; then
            if check_port "$port" "tcp"; then
                colorize red "Port $port is in use."
            else
                config_ports+=("$port")
                colorize green "Port $port added."
            fi
        else
            colorize red "Port $port is invalid. Must be between 23-65535."
        fi
    done
    [[ ${#config_ports[@]} -eq 0 ]] && { colorize red "No valid ports added."; sleep 2; return 1; }
    transport=$(grep "type = " "$config_path" | head -n 1 | cut -d'"' -f2)
    token=$(grep "default_token = " "$config_path" | cut -d'"' -f2)
    nodelay=$(grep "nodelay = " "$config_path" | head -n 1 | cut -d'=' -f2 | tr -d ' ')
    if [[ "$tunnel_type" == "iran" ]]; then
        local_ip=$(grep "bind_addr = " "$config_path" | head -n 1 | cut -d'"' -f2 | cut -d':' -f1)
        for port in "${config_ports[@]}"; do
            cat << EOF >> "$config_path"
[server.services.service${port}]
type = "$transport"
token = "$token"
bind_addr = "${local_ip}:${port}"
nodelay = $nodelay

EOF
        done
    else
        local_ip=$(grep "local_addr = " "$config_path" | head -n 1 | cut -d'"' -f2 | cut -d':' -f1)
        for port in "${config_ports[@]}"; do
            cat << EOF >> "$config_path"
[client.services.service${port}]
type = "$transport"
token = "$token"
local_addr = "${local_ip}:${port}"
nodelay = $nodelay

EOF
        done
    fi
    colorize green "New ports added successfully."
    press_key
}

# Function to edit Iran IP (Kharej only)
edit_iran_ip() {
    local config_path="$1"
    local tunnel_name=$(basename "${config_path%.toml}" | sed 's/kharej-//')
    read -p "[*] Enter new Iran server IP (IPv4 or [IPv6]): " new_ip
    [[ -z "$new_ip" ]] && { colorize red "Server address cannot be empty."; press_key; return 1; }
    if check_ipv6 "$new_ip"; then
        new_ip="${new_ip#[}"
        new_ip="${new_ip%]}"
    elif ! check_ipv4 "$new_ip"; then
        colorize red "Invalid IP address format."
        press_key
        return 1
    fi
    tunnel_port=$(grep "remote_addr = " "$config_path" | cut -d':' -f2 | cut -d'"' -f1)
    sed -i "s/remote_addr = \".*\"/remote_addr = \"${new_ip}:${tunnel_port}\"/" "$config_path" || { colorize red "Failed to update Iran server IP"; return 1; }
    colorize green "Iran server IP updated to $new_ip."
    press_key
}

# Function to manage tunnels
manage_tunnel() {
    clear
    local tunnel_found=0
    colorize cyan "List of existing tunnels:" bold
    echo
    local index=1
    declare -a configs
    declare -a config_types
    declare -a tunnel_names
    declare -a service_names

    # List Direct Iran tunnels
    for config_path in "$CONFIG_DIR"/direct-iran-*.conf; do
        if [[ -f "$config_path" ]]; then
            tunnel_found=1
            tunnel_name=$(basename "$config_path" .conf | sed 's/^direct-iran-//')
            tunnel_type="direct-iran"
            service_name="ALEX-direct-iran-${tunnel_name}.service"
            tunnel_port=$(grep "^dstport=" "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
            config_ports=$(grep "^ports=" "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
            bridge_ip=$(grep "^kharej_bridge_ip=" "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
            [[ -z "$tunnel_port" ]] && tunnel_port="Unknown"
            [[ -z "$config_ports" ]] && config_ports="None"
            [[ -z "$bridge_ip" ]] && bridge_ip="10.0.10.1/24"
            configs+=("$config_path")
            config_types+=("$tunnel_type")
            tunnel_names+=("$tunnel_name")
            service_names+=("$service_name")
            echo -e "${CYAN}${index}${NC}) ${GREEN}Direct Iran Tunnel ${tunnel_name}${NC} (Tunnel Port: ${YELLOW}${tunnel_port}${NC}, HAProxy Ports: ${YELLOW}${config_ports}${NC}, Bridge IP: ${YELLOW}${bridge_ip}${NC})"
            ((index++))
        fi
    done

    # List Direct Kharej tunnels
    for config_path in "$CONFIG_DIR"/direct-kharej-*.conf; do
        if [[ -f "$config_path" ]]; then
            tunnel_found=1
            tunnel_name=$(basename "$config_path" .conf | sed 's/^direct-kharej-//')
            tunnel_type="direct-kharej"
            service_name="ALEX-direct-kharej-${tunnel_name}.service"
            tunnel_port=$(grep "^dstport=" "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
            bridge_ip=$(grep "^bridge_ip=" "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
            [[ -z "$tunnel_port" ]] && tunnel_port="Unknown"
            [[ -z "$bridge_ip" ]] && bridge_ip="10.0.10.2/24"
            configs+=("$config_path")
            config_types+=("$tunnel_type")
            tunnel_names+=("$tunnel_name")
            service_names+=("$service_name")
            echo -e "${CYAN}${index}${NC}) ${GREEN}Direct Kharej Tunnel ${tunnel_name}${NC} (Tunnel Port: ${YELLOW}${tunnel_port}${NC}, Bridge IP: ${YELLOW}${bridge_ip}${NC})"
            ((index++))
        fi
    done

    # List Iran tunnels (Reverse)
    for config_path in "$CONFIG_DIR"/iran-*.toml; do
        if [[ -f "$config_path" ]]; then
            tunnel_found=1
            tunnel_name=$(basename "$config_path" .toml | sed 's/^iran-//')
            tunnel_type="iran"
            service_name="ALEX-iran-${tunnel_name}.service"
            tunnel_port=$(grep "bind_addr" "$config_path" 2>/dev/null | head -n 1 | cut -d':' -f2 | cut -d'"' -f1)
            config_ports=$(grep "bind_addr.*:[0-9]" "$config_path" 2>/dev/null | grep -v "bind_addr.*:${tunnel_port}" | cut -d':' -f2 | cut -d'"' -f1 | tr '\n' ',' | sed 's/,$//')
            [[ -z "$tunnel_port" ]] && tunnel_port="Unknown"
            [[ -z "$config_ports" ]] && config_ports="None"
            configs+=("$config_path")
            config_types+=("$tunnel_type")
            tunnel_names+=("$tunnel_name")
            service_names+=("$service_name")
            echo -e "${CYAN}${index}${NC}) ${GREEN}Iran Tunnel ${tunnel_name}${NC} (Tunnel Port: ${YELLOW}${tunnel_port}${NC}, Service Ports: ${YELLOW}${config_ports}${NC})"
            ((index++))
        fi
    done

    # List Kharej tunnels (Reverse)
    for config_path in "$CONFIG_DIR"/kharej-*.toml; do
        if [[ -f "$config_path" ]]; then
            tunnel_found=1
            tunnel_name=$(basename "$config_path" .toml | sed 's/^kharej-//')
            tunnel_type="kharej"
            service_name="ALEX-kharej-${tunnel_name}.service"
            tunnel_port=$(grep "remote_addr" "$config_path" 2>/dev/null | cut -d':' -f2 | cut -d'"' -f1)
            config_ports=$(grep "local_addr" "$config_path" 2>/dev/null | cut -d':' -f2 | cut -d'"' -f1 | tr '\n' ',' | sed 's/,$//')
            [[ -z "$tunnel_port" ]] && tunnel_port="Unknown"
            [[ -z "$config_ports" ]] && config_ports="None"
            configs+=("$config_path")
            config_types+=("$tunnel_type")
            tunnel_names+=("$tunnel_name")
            service_names+=("$service_name")
            echo -e "${CYAN}${index}${NC}) ${GREEN}Kharej Tunnel ${tunnel_name}${NC} (Tunnel Port: ${YELLOW}${tunnel_port}${NC}, Service Ports: ${YELLOW}${config_ports}${NC})"
            ((index++))
        fi
    done

    echo
    if [[ $tunnel_found -eq 0 ]]; then
        colorize red "No tunnels found." bold
        press_key
        return 1
    fi

    read -p "Enter choice (0 to return): " choice
    [[ "$choice" == "0" ]] && return
    while ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice >= index )); do
        colorize red "Invalid choice. Enter a number between 1 and $((index-1)) or 0 to return."
        read -p "Enter choice: " choice
        [[ "$choice" == "0" ]] && return
    done

    # Get selected tunnel details
    selected_config="${configs[$((choice - 1))]}"
    tunnel_type="${config_types[$((choice - 1))]}"
    tunnel_name="${tunnel_names[$((choice - 1))]}"
    service_name="${service_names[$((choice - 1))]}"
    service_path="${SERVICE_DIR}/${service_name}"

    # Verify config and service files
    if [[ ! -f "$selected_config" ]]; then
        colorize red "Config file $selected_config not found. Please check configuration."
        press_key
        return 1
    fi
    if [[ ! -f "$service_path" ]]; then
        colorize red "Service file $service_path not found. Please check configuration."
        press_key
        return 1
    fi

    # Check for consecutive errors
    check_consecutive_errors "$service_name"

    echo
    colorize cyan "Manage Tunnel: $tunnel_name ($tunnel_type)" bold
    echo "1) Start tunnel"
    echo "2) Stop tunnel"
    echo "3) Restart tunnel"
    echo "4) Check tunnel status"
    echo "5) Edit tunnel configuration"
    echo "6) Delete tunnel"
    if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "iran" ]]; then
        echo "7) Show bandwidth usage"
        echo "8) Reset bandwidth usage"
    fi
    echo "9) Set cron job for tunnel restart"
    read -p "Enter choice (0 to return): " manage_choice

    case $manage_choice in
        1)
            systemctl start "$service_name"
            if [[ $? -eq 0 ]]; then
                colorize green "Tunnel $tunnel_name started successfully."
            else
                colorize red "Failed to start tunnel $tunnel_name. Check 'systemctl status $service_name' for details."
            fi
            if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "direct-kharej" ]]; then
                systemctl restart haproxy
                if [[ $? -eq 0 ]]; then
                    colorize green "HAProxy restarted successfully."
                else
                    colorize red "Failed to restart HAProxy."
                fi
            fi
            ;;
        2)
            systemctl stop "$service_name"
            if [[ $? -eq 0 ]]; then
                colorize green "Tunnel $tunnel_name stopped successfully."
            else
                colorize red "Failed to stop tunnel $tunnel_name. Check 'systemctl status $service_name' for details."
            fi
            if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "direct-kharej" ]]; then
                systemctl restart haproxy
                if [[ $? -eq 0 ]]; then
                    colorize green "HAProxy restarted successfully."
                else
                    colorize red "Failed to restart HAProxy."
                fi
            fi
            ;;
        3)
            systemctl restart "$service_name"
            if [[ $? -eq 0 ]]; then
                colorize green "Tunnel $tunnel_name restarted successfully."
            else
                colorize red "Failed to restart tunnel $tunnel_name. Check 'systemctl status $service_name' for details."
            fi
            if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "direct-kharej" ]]; then
                systemctl restart haproxy
                if [[ $? -eq 0 ]]; then
                    colorize green "HAProxy restarted successfully."
                else
                    colorize red "Failed to restart HAProxy."
                fi
            fi
            ;;
        4)
            systemctl status "$service_name"
            if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "direct-kharej" ]]; then
                systemctl status haproxy
            fi
            ;;
        5)
            edit_tunnel "$selected_config" "$tunnel_type" "$tunnel_name"
            ;;
        6)
            read -p "Are you sure you want to delete tunnel $tunnel_name? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                systemctl stop "$service_name" 2>/dev/null
                systemctl disable "$service_name" 2>/dev/null
                rm -f "$service_path"
                if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "direct-kharej" ]]; then
                    vxlan_id=$(grep "^vxlan_id=" "$selected_config" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
                    tunnel_port=$(grep "^dstport=" "$selected_config" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
                    ip link delete "vxlan${vxlan_id}" 2>/dev/null
                    ip link delete "br${vxlan_id}" 2>/dev/null
                    if [[ "$tunnel_type" == "direct-iran" ]]; then
                        haproxy_config="/etc/haproxy/haproxy.cfg"
                        if [[ -f "$haproxy_config" ]]; then
                            cp "$haproxy_config" "${haproxy_config}.bak" 2>/dev/null || {
                                colorize yellow "Failed to backup HAProxy config."
                                press_key
                            }
                            if ! sed -i "/^[[:space:]]*#start:$tunnel_port[[:space:]]*$/,/^[[:space:]]*#end:$tunnel_port[[:space:]]*$/d" "$haproxy_config" 2>/dev/null; then
                                colorize yellow "No configuration found for port $tunnel_port in HAProxy."
                                press_key
                            else
                                systemctl restart haproxy 2>/dev/null
                                if [[ $? -eq 0 ]]; then
                                    colorize green "Tunnel section removed and HAProxy restarted."
                                else
                                    colorize red "Failed to restart HAProxy."
                                    if [[ -f "${haproxy_config}.bak" ]]; then
                                        cp "${haproxy_config}.bak" "$haproxy_config" 2>/dev/null
                                        colorize yellow "Restored HAProxy backup."
                                    fi
                                    press_key
                                    rm -f "$selected_config"
                                    return 1
                                fi
                            fi
                        fi
                    fi
                fi
                # Clean up bandwidth monitoring data and iptables rules for direct-iran and iran tunnels
                if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "iran" ]]; then
                    if [[ -f "${CONFIG_DIR}/tools/alex-port-monitor.sh" ]]; then
                        if [[ "$tunnel_type" == "direct-iran" ]]; then
                            proto="udp"
                        else
                            proto=$(grep "type = " "$selected_config" | head -n 1 | cut -d'"' -f2)
                            [[ -z "$proto" ]] && proto="tcp"
                        fi
                        tunnel_port=$(grep "^dstport=" "$selected_config" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
                        [[ -z "$tunnel_port" && "$tunnel_type" == "iran" ]] && tunnel_port=$(grep "bind_addr" "$selected_config" | head -n 1 | cut -d':' -f2 | cut -d'"' -f1)
                        if [[ -n "$tunnel_port" && "$tunnel_port" =~ ^[0-9]+$ && "$proto" =~ ^(tcp|udp)$ ]]; then
                            sudo pkill -f "alex-port-monitor.sh.*port_${tunnel_port}_${proto}_usage.txt" 2>/dev/null
                            sudo ${CONFIG_DIR}/tools/alex-port-monitor.sh removeport "$tunnel_port" "$proto"
                            colorize green "Removed port $tunnel_port ($proto) from monitoring"
                            while sudo iptables -D INPUT -p "$proto" --dport "$tunnel_port" -j ACCEPT 2>/dev/null; do :; done
                            while sudo iptables -D OUTPUT -p "$proto" --sport "$tunnel_port" -j ACCEPT 2>/dev/null; do :; done
                            while sudo ip6tables -D INPUT -p "$proto" --dport "$tunnel_port" -j ACCEPT 2>/dev/null; do :; done
                            while sudo ip6tables -D OUTPUT -p "$proto" --sport "$tunnel_port" -j ACCEPT 2>/dev/null; do :; done
                            colorize green "Removed iptables/ip6tables rules for port $tunnel_port ($proto)"
                            bandwidth_file="/root/bandwidth/port_${tunnel_port}_${proto}_usage.txt"
                            if [[ -f "$bandwidth_file" ]]; then
                                sudo chmod 644 "$bandwidth_file" 2>/dev/null
                                sudo rm -f "$bandwidth_file" || colorize red "Failed to remove bandwidth file: $bandwidth_file"
                                colorize green "Removed bandwidth file: $bandwidth_file"
                            else
                                colorize yellow "Bandwidth file $bandwidth_file is Deleted."
                            fi
                            ports_file="/root/bandwidth/ports.txt"
                            if [[ -f "$ports_file" ]]; then
                                temp_ports_file=$(mktemp)
                                sudo grep -v "^${tunnel_port} ${proto}$" "$ports_file" > "$temp_ports_file"
                                sudo mv "$temp_ports_file" "$ports_file"
                                sudo chmod 644 "$ports_file"
                                colorize green "Removed port ${tunnel_port} ${proto} from $ports_file"
                            else
                                colorize yellow "Warning: $ports_file not found, skipping port cleanup."
                            fi
                        else
                            colorize yellow "Warning: Could not determine valid tunnel port or protocol for $tunnel_type tunnel."
                        fi
                    else
                        colorize yellow "Warning: alex-port-monitor.sh not found, skipping port monitoring cleanup."
                    fi
                fi
                rm -f "$selected_config"
                systemctl daemon-reload
                colorize green "Tunnel $tunnel_name deleted successfully."
            else
                colorize yellow "Tunnel deletion canceled."
            fi
            ;;
        7)
            if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "iran" ]]; then
                if [[ -f "${CONFIG_DIR}/tools/alex-port-monitor.sh" ]]; then
                    if [[ "$tunnel_type" == "direct-iran" ]]; then
                        proto="udp"
                    else
                        proto=$(grep "type = " "$selected_config" | head -n 1 | cut -d'"' -f2)
                        [[ -z "$proto" ]] && proto="tcp"
                    fi
                    tunnel_port=$(grep "^dstport=" "$selected_config" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
                    [[ -z "$tunnel_port" && "$tunnel_type" == "iran" ]] && tunnel_port=$(grep "bind_addr" "$selected_config" | head -n 1 | cut -d':' -f2 | cut -d'"' -f1)
                    if [[ -n "$tunnel_port" ]]; then
                        ${CONFIG_DIR}/tools/alex-port-monitor.sh show_port "$tunnel_port" "$proto"
                    else
                        colorize red "Could not determine tunnel port for $tunnel_name."
                    fi
                else
                    colorize red "alex-port-monitor.sh not found."
                fi
            else
                colorize red "Bandwidth monitoring is only available for Iran server tunnels."
            fi
            ;;
        8)
            if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "iran" ]]; then
                if [[ -f "${CONFIG_DIR}/tools/alex-port-monitor.sh" ]]; then
                    if [[ "$tunnel_type" == "direct-iran" ]]; then
                        proto="udp"
                    else
                        proto=$(grep "type = " "$selected_config" | head -n 1 | cut -d'"' -f2)
                        [[ -z "$proto" ]] && proto="tcp"
                    fi
                    tunnel_port=$(grep "^dstport=" "$selected_config" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
                    [[ -z "$tunnel_port" && "$tunnel_type" == "iran" ]] && tunnel_port=$(grep "bind_addr" "$selected_config" | head -n 1 | cut -d':' -f2 | cut -d'"' -f1)
                    if [[ -n "$tunnel_port" && "$tunnel_port" =~ ^[0-9]+$ && "$proto" =~ ^(tcp|udp)$ ]]; then
                        sudo ${CONFIG_DIR}/tools/alex-port-monitor.sh resetport "$tunnel_port" "$proto"
                    else
                        colorize red "Could not determine valid tunnel port or protocol for $tunnel_name."
                    fi
                else
                    colorize red "alex-port-monitor.sh not found."
                fi
            else
                colorize red "Bandwidth monitoring is only available for Iran server tunnels."
            fi
            ;;
        9)
            colorize cyan "Set Cron Job for Auto-Restart of Tunnel: $tunnel_name" bold
            echo "Select restart interval:"
            echo "1) 5 minutes"
            echo "2) 10 minutes"
            echo "3) 15 minutes"
            echo "4) 30 minutes"
            echo "5) 1 hour"
            echo "6) 2 hours"
            echo "7) 4 hours"
            echo "8) 12 hours"
            echo "9) 24 hours"
            read -p "Enter choice (0 to return): " cron_choice
            case $cron_choice in
                0)
                    return
                    ;;
                1|2|3|4|5|6|7|8|9)
                    local interval cron_schedule
                    case $cron_choice in
                        1) interval="5 minutes"; cron_schedule="*/5 * * * *" ;;
                        2) interval="10 minutes"; cron_schedule="*/10 * * * *" ;;
                        3) interval="15 minutes"; cron_schedule="*/15 * * * *" ;;
                        4) interval="30 minutes"; cron_schedule="*/30 * * * *" ;;
                        5) interval="1 hour"; cron_schedule="0 * * * *" ;;
                        6) interval="2 hours"; cron_schedule="0 */2 * * *" ;;
                        7) interval="4 hours"; cron_schedule="0 */4 * * *" ;;
                        8) interval="12 hours"; cron_schedule="0 */12 * * *" ;;
                        9) interval="24 hours"; cron_schedule="0 0 * * *" ;;
                    esac
                    crontab -l | grep -v "systemctl restart $service_name" > /tmp/crontab_tmp
                    local cron_command="/usr/bin/systemctl restart $service_name"
                    if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "direct-kharej" ]]; then
                        cron_command="$cron_command && /usr/bin/systemctl restart haproxy"
                    fi
                    echo "$cron_schedule $cron_command" >> /tmp/crontab_tmp
                    crontab /tmp/crontab_tmp
                    rm -f /tmp/crontab_tmp
                    colorize green "Cron job set for restarting tunnel $tunnel_name every $interval."
                    ;;
                *)
                    colorize red "Invalid choice! Please select a number between 1 and 9 or 0 to return."
                    ;;
            esac
            ;;
        0)
            return
            ;;
        *)
            colorize red "Invalid option!"
            ;;
    esac
    press_key
}

destroy_tunnel() {
    local config_path="$1"
    local tunnel_type="$2"
    tunnel_name=$(basename "${config_path%.toml}" "${config_path%.conf}" | sed 's/iran-//;s/kharej-//;s/direct-iran-//;s/direct-kharej-//')
    service_name="ALEX-${tunnel_type}-${tunnel_name}.service"
    service_path="${SERVICE_DIR}/${service_name}"

    if [[ ! -f "$service_path" ]]; then
        colorize red "Service file $service_path not found."
        press_key
        return 1
    fi

    if systemctl is-active "$service_name" &> /dev/null; then
        systemctl stop "$service_name" || { colorize yellow "Failed to stop service $service_name."; press_key; return 1; }
    fi
    if systemctl is-enabled "$service_name" &> /dev/null; then
        systemctl disable "$service_name" || { colorize yellow "Failed to disable service $service_name."; press_key; return 1; }
    fi

    rm -f "$service_path" || { colorize yellow "Failed to remove service file $service_path."; press_key; return 1; }

    if [[ -f "$config_path" ]]; then
        rm -f "$config_path" || { colorize yellow "Failed to remove config file $config_path."; press_key; return 1; }
    else
        colorize yellow "Config file $config_path not found."
    fi

    if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "direct-kharej" ]]; then
        vxlan_id=$(grep "^vxlan_id=" "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
        if [[ -n "$vxlan_id" ]]; then
            ip link delete "vxlan${vxlan_id}" 2>/dev/null || colorize yellow "Failed to delete VXLAN interface vxlan${vxlan_id}."
            ip link delete "br${vxlan_id}" 2>/dev/null || colorize yellow "Failed to delete bridge interface br${vxlan_id}."
        fi
        if [[ "$tunnel_type" == "direct-iran" ]]; then
            remove_haproxy_config "$tunnel_name" || { colorize yellow "Failed to remove HAProxy configuration."; press_key; return 1; }
        fi
    fi

    if [[ "$tunnel_type" == "direct-iran" || "$tunnel_type" == "iran" ]]; then
        if [[ -f "${CONFIG_DIR}/tools/alex-port-monitor.sh" ]]; then
            if [[ "$tunnel_type" == "direct-iran" ]]; then
                proto="udp"
            else
                proto=$(grep "type = " "$config_path" | head -n 1 | cut -d'"' -f2)
                [[ -z "$proto" ]] && proto="tcp"
            fi
            tunnel_port=$(grep "^dstport=" "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
            [[ -z "$tunnel_port" && "$tunnel_type" == "iran" ]] && tunnel_port=$(grep "bind_addr" "$config_path" | head -n 1 | cut -d':' -f2 | cut -d'"' -f1)
            if [[ -n "$tunnel_port" && "$tunnel_port" =~ ^[0-9]+$ && "$proto" =~ ^(tcp|udp)$ ]]; then
                sudo ${CONFIG_DIR}/tools/alex-port-monitor.sh removeport "$tunnel_port" "$proto"
                colorize green "Removed port $tunnel_port ($proto) from monitoring"
                while sudo iptables -D INPUT -p "$proto" --dport "$tunnel_port" -j ACCEPT 2>/dev/null; do :; done
                while sudo iptables -D OUTPUT -p "$proto" --sport "$tunnel_port" -j ACCEPT 2>/dev/null; do :; done
                while sudo ip6tables -D INPUT -p "$proto" --dport "$tunnel_port" -j ACCEPT 2>/dev/null; do :; done
                while sudo ip6tables -D OUTPUT -p "$proto" --sport "$tunnel_port" -j ACCEPT 2>/dev/null; do :; done
                colorize green "Removed iptables/ip6tables rules for port $tunnel_port ($proto)"
                bandwidth_file="/root/bandwidth/port_${tunnel_port}_${proto}_usage.txt"
                if [[ -f "$bandwidth_file" && -w "$bandwidth_file" ]]; then
                    sudo rm -f "$bandwidth_file" || colorize red "Failed to remove bandwidth file: $bandwidth_file"
                    colorize green "Removed bandwidth file: $bandwidth_file"
                else
                    colorize yellow "Bandwidth file $bandwidth_file not found or not writable, skipping."
                fi
                ports_file="/root/bandwidth/ports.txt"
                if [[ -f "$ports_file" ]]; then
                    temp_ports_file=$(mktemp)
                    sudo grep -v "^${tunnel_port} ${proto}$" "$ports_file" > "$temp_ports_file"
                    sudo mv "$temp_ports_file" "$ports_file"
                    sudo chmod 644 "$ports_file"
                    colorize green "Removed port ${tunnel_port} ${proto} from $ports_file"
                else
                    colorize yellow "Warning: $ports_file not found, skipping port cleanup."
                fi
            else
                colorize yellow "Warning: Could not determine valid tunnel port or protocol for $tunnel_type tunnel."
            fi
        else
            colorize yellow "Warning: alex-port-monitor.sh not found, skipping port monitoring cleanup."
        fi
    fi

    systemctl daemon-reload || { colorize yellow "Failed to reload systemd."; press_key; return 1; }

    colorize green "Tunnel $tunnel_name deleted successfully."
    press_key
    return 0
}

# Function to restart service
restart_service() {
    local service_name="$1"
    colorize yellow "Restarting $service_name..." bold
    if systemctl list-units --type=service | grep -q "$service_name"; then
        systemctl restart "$service_name" || colorize red "Failed to restart service $service_name."
        if [[ "$service_name" =~ direct-iran || "$service_name" =~ direct-kharej ]]; then
            systemctl restart haproxy || colorize red "Failed to restart HAProxy."
        fi
        colorize green "Tunnel restarted successfully."
    else
        colorize red "Tunnel $service_name not found."
    fi
    press_key
}

# Function to view tunnel logs
view_tunnel_logs() {
    clear
    journalctl -u "$1" --no-pager
    press_key
}

# Function to view tunnel status
view_tunnel_status() {
    clear
    systemctl status "$1"
    press_key
}

# Modified remove_core to handle HAProxy config cleanup
remove_core() {
    clear
    if ls "$CONFIG_DIR"/*.toml "$CONFIG_DIR"/*.conf &> /dev/null; then
        colorize red "Remove all tunnels before removing ALEX core."
        press_key
        return 1
    fi
    read -p "Confirm removal of ALEX core? (y/n): " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        for vxlan in $(ip link show | grep -oP 'vxlan\d+'); do
            ip link delete "$vxlan" 2>/dev/null || colorize yellow "Failed to delete VXLAN interface $vxlan."
        done
        for bridge in $(ip link show | grep -oP 'br\d+'); do
            ip link delete "$bridge" 2>/dev/null || colorize yellow "Failed to delete bridge interface $bridge."
        done
        for service in $(ls "$SERVICE_DIR"/ALEX-*.service 2>/dev/null); do
            service_name=$(basename "$service")
            systemctl stop "$service_name" 2>/dev/null
            systemctl disable "$service_name" 2>/dev/null
            rm -f "$service" || colorize yellow "Failed to remove service file $service."
        done
        if [[ -f "$HAPROXY_CFG" ]]; then
            cp "$HAPROXY_CFG" "${HAPROXY_CFG}.bak" 2>/dev/null
            sed -i '/#start:/,/#end:/d' "$HAPROXY_CFG" 2>/dev/null
            if haproxy -c -f "$HAPROXY_CFG" >/dev/null 2>&1; then
                systemctl restart haproxy 2>/dev/null || colorize yellow "Failed to restart HAProxy."
            else
                colorize yellow "Invalid HAProxy configuration after cleanup. Restoring backup."
                cp "${HAPROXY_CFG}.bak" "$HAPROXY_CFG" 2>/dev/null
            fi
        fi
        if [[ -f "${CONFIG_DIR}/tools/alex-port-monitor.sh" ]]; then
            ${CONFIG_DIR}/tools/alex-port-monitor.sh uninstall
            rm -rf "${CONFIG_DIR}/tools"
        fi
        rm -rf "$CONFIG_DIR" || colorize yellow "Failed to remove ALEX core directory $CONFIG_DIR."
        systemctl daemon-reload
        colorize green "ALEX core removed."
    else
        colorize yellow "Removal canceled."
    fi
    press_key
}

# Function to display logo
display_logo() {
    echo -e "${BLUE}"
    cat << "EOF"
╭───────────────────────────────────────────╮
│                                           │
│       █████╗ ██╗     ███████╗██╗  ██╗     │
│      ██╔══██╗██║     ██╔════╝╚██╗██╔╝     │
│      ███████║██║     █████╗   ╚███╔╝      │
│      ██╔══██║██║     ██╔══╝   ██╔██╗      │
│      ██║  ██║███████╗███████╗██╔╝ ██╗     │
│      ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝     │
│                                           │
│         ALEX Tunnel Manager v1.2          │
│      @Alextaylorvhjnf / Alex-tunnel       │
│                                           │
├───────────────────────────────────────────┤
│  https://github.com/Alextaylorvhjnf       │
│              /Alex-tunnel                 │
╰───────────────────────────────────────────╯
EOF
    echo -e "${NC}"
}

# Function to display server info
display_server_info() {
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "${BLUE}◆ IP Address:${NC} $SERVER_IP"
    if [[ -f "${ALEX_BIN}" ]]; then
        echo -e "${BLUE}◆ Core Installed:${NC} ${GREEN}✓ Yes${NC}"
    else
        echo -e "${BLUE}◆ Core Installed:${NC} ${RED}✗ No${NC}"
    fi
    echo -e "${BLUE}─────────────────────────────────────────${NC}"
}

# Function to display menu
display_menu() {
    clear
    display_logo
    display_server_info
    colorize cyan "1) Setup New Tunnel" bold
    colorize green "2) Manage Tunnels" bold
    colorize blue "3) Install ALEX Core" bold
    colorize red "4) Uninstall ALEX Core" bold
    colorize yellow "5) Update Script" bold
    colorize magenta "6) ALEX Tools" bold
    colorize yellow "7) Exit" bold
    echo -e "${BLUE}─────────────────────────────────────────${NC}"
    echo
}

# Main loop
install_dependencies
mkdir -p "$CONFIG_DIR"

# Check if the script is running from a pipe (e.g., curl | bash)
if [[ "$0" == "/dev/fd/"* || "$0" == "bash" ]]; then
    # Script is running from a pipe, download it directly to SCRIPT_PATH
    colorize yellow "Detected piped execution. Downloading script to ${SCRIPT_PATH}..."
    if ! curl -sSL -o "${SCRIPT_PATH}" "https://raw.githubusercontent.com/Alextaylorvhjnf/Alex-tunnel/main/alex_manager.sh"; then
        colorize red "Failed to download script to ${SCRIPT_PATH}."
        press_key
        exit 1
    fi
    # Verify the downloaded script is complete
    if ! grep -q "function display_menu" "${SCRIPT_PATH}" || ! grep -q "function install_dependencies" "${SCRIPT_PATH}"; then
        colorize red "Downloaded script at ${SCRIPT_PATH} is incomplete."
        rm -f "${SCRIPT_PATH}"
        press_key
        exit 1
    fi
    # Verify the script size to ensure it's not truncated
    if [[ $(stat -c %s "${SCRIPT_PATH}") -lt 1000 ]]; then
        colorize red "Downloaded script at ${SCRIPT_PATH} is too small and likely incomplete."
        rm -f "${SCRIPT_PATH}"
        press_key
        exit 1
    fi
    chmod +x "${SCRIPT_PATH}"
    colorize green "Script is now executable as 'ALEX' command." bold
    colorize yellow "Starting ALEX manager..."
    exec "${SCRIPT_PATH}"
fi

# If script is already installed and complete, proceed
if [[ ! -f "${SCRIPT_PATH}" ]] || ! grep -q "function display_menu" "${SCRIPT_PATH}"; then
    colorize yellow "Installing script to ${SCRIPT_PATH}..."
    if ! curl -sSL -o "${SCRIPT_PATH}" "https://raw.githubusercontent.com/Alextaylorvhjnf/Alex-tunnel/main/alex_manager.sh"; then
        colorize red "Failed to download script to ${SCRIPT_PATH}."
        press_key
        exit 1
    fi
    # Verify the downloaded script is complete
    if ! grep -q "function display_menu" "${SCRIPT_PATH}" || ! grep -q "function install_dependencies" "${SCRIPT_PATH}"; then
        colorize red "Downloaded script at ${SCRIPT_PATH} is incomplete."
        rm -f "${SCRIPT_PATH}"
        press_key
        exit 1
    fi
    # Verify the script size
    if [[ $(stat -c %s "${SCRIPT_PATH}") -lt 1000 ]]; then
        colorize red "Downloaded script at ${SCRIPT_PATH} is too small and likely incomplete."
        rm -f "${SCRIPT_PATH}"
        press_key
        exit 1
    fi
    chmod +x "${SCRIPT_PATH}"
    colorize green "Script is now executable as 'ALEX' command." bold
    colorize yellow "Starting ALEX manager..."
    exec "${SCRIPT_PATH}"
fi

while true; do
    display_menu
    read -p "Enter a choice: " choice
    case $choice in
        1)
            clear
            colorize cyan "Select tunnel type:" bold
            echo "1) Direct"
            echo "2) Reverse"
            read -p "Enter choice: " tunnel_type
            case $tunnel_type in
                1)
                    direct_server_configuration
                    ;;
                2)
                    clear
                    colorize cyan "Select server location:" bold
                    echo "1) Iran Server"
                    echo "2) Kharej Server"
                    read -p "Enter choice: " server_type
                    case $server_type in
                        1) iran_server_configuration ;;
                        2) kharej_server_configuration ;;
                        *) colorize red "Invalid option!" && sleep 1 ;;
                    esac
                    ;;
                *) colorize red "Invalid option!" && sleep 1 ;;
            esac
            ;;
        2) manage_tunnel ;;
        3) download_and_extract_alex ;;
        4) remove_core ;;
        5) update_script ;;
        6) alex_tools ;;
        7) exit 0 ;;
        *) colorize red "Invalid option!" && sleep 1 ;;
    esac
done
