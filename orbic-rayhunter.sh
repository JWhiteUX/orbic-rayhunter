#!/bin/bash
# orbic-rayhunter - Control script for Rayhunter notifications via local ntfy
# https://github.com/EFForg/rayhunter

VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")

# Defaults (can be overridden via environment variables)
NTFY_PORT="${ORBIC_NTFY_PORT:-8080}"
NTFY_TOPIC="${ORBIC_NTFY_TOPIC:-rayhunter}"
ORBIC_GATEWAY="${ORBIC_GATEWAY:-192.168.1.1}"
RAYHUNTER_PORT="${ORBIC_RAYHUNTER_PORT:-8080}"
ORBIC_ADMIN_PORT="${ORBIC_ADMIN_PORT:-80}"
NTFY_PID_FILE="/tmp/orbic-rayhunter-ntfy.pid"
NTFY_LOG_FILE="/tmp/orbic-rayhunter-ntfy.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

print_error() { echo -e "${RED}Error: $1${NC}" >&2; }
print_warn()  { echo -e "${YELLOW}$1${NC}"; }
print_ok()    { echo -e "${GREEN}$1${NC}"; }
print_info()  { echo -e "${CYAN}$1${NC}"; }

# Find the USB tethering interface connected to Orbic
find_usb_interface() {
    local iface
    for iface in /sys/class/net/usb* /sys/class/net/enp*u* /sys/class/net/eth*; do
        [ -e "$iface" ] || continue
        iface=$(basename "$iface")
        # Check if this interface has a route to the Orbic gateway
        if ip route show dev "$iface" 2>/dev/null | grep -q "$ORBIC_GATEWAY"; then
            echo "$iface"
            return 0
        fi
        # Fallback: check if interface is up and has an IP in 192.168.1.x range
        if ip addr show "$iface" 2>/dev/null | grep -q "inet 192\.168\.1\."; then
            echo "$iface"
            return 0
        fi
    done
    # Last resort: return usb0 if it exists
    [ -e /sys/class/net/usb0 ] && echo "usb0" && return 0
    return 1
}

# Get IP address of an interface
get_iface_ip() {
    ip addr show "$1" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1
}

# Get the primary LAN interface (non-USB, non-loopback, has IP)
find_lan_interface() {
    local iface
    for iface in /sys/class/net/*; do
        iface=$(basename "$iface")
        [[ "$iface" == "lo" ]] && continue
        [[ "$iface" == usb* ]] && continue
        [[ "$iface" == *mon* ]] && continue
        if ip addr show "$iface" 2>/dev/null | grep -q "inet "; then
            echo "$iface"
            return 0
        fi
    done
    return 1
}

check_orbic_reachable() {
    ping -c 1 -W 2 "$ORBIC_GATEWAY" &>/dev/null
}

check_rayhunter_running() {
    curl -s --connect-timeout 2 "http://$ORBIC_GATEWAY:$RAYHUNTER_PORT" &>/dev/null
}

is_ntfy_running() {
    [ -f "$NTFY_PID_FILE" ] && kill -0 "$(cat "$NTFY_PID_FILE")" 2>/dev/null
}

check_dependencies() {
    local missing=()
    command -v ntfy &>/dev/null || missing+=("ntfy")
    command -v curl &>/dev/null || missing+=("curl")
    command -v ip &>/dev/null || missing+=("iproute2")
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing[*]}"
        echo "Install ntfy from: https://github.com/binwiederhier/ntfy/releases"
        return 1
    fi
    return 0
}

# ============================================================================
# Commands
# ============================================================================

cmd_start() {
    echo -e "${BOLD}=== Orbic Rayhunter Setup ===${NC}"
    echo ""
    
    # Check dependencies
    check_dependencies || exit 1
    
    # Find USB interface
    local usb_iface
    usb_iface=$(find_usb_interface)
    if [ -z "$usb_iface" ]; then
        print_error "No USB tethering interface found"
        echo "Ensure Orbic is connected via USB and tethering is enabled"
        exit 1
    fi
    
    local usb_ip
    usb_ip=$(get_iface_ip "$usb_iface")
    if [ -z "$usb_ip" ]; then
        print_warn "USB interface $usb_iface has no IP, requesting DHCP..."
        sudo dhclient "$usb_iface" 2>/dev/null || sudo dhcpcd "$usb_iface" 2>/dev/null
        sleep 2
        usb_ip=$(get_iface_ip "$usb_iface")
        if [ -z "$usb_ip" ]; then
            print_error "Failed to obtain IP on $usb_iface"
            exit 1
        fi
    fi
    print_ok "USB interface: $usb_iface ($usb_ip)"
    
    # Check Orbic connectivity
    if check_orbic_reachable; then
        print_ok "Orbic reachable: $ORBIC_GATEWAY"
    else
        print_error "Cannot reach Orbic at $ORBIC_GATEWAY"
        exit 1
    fi
    
    # Check Rayhunter
    if check_rayhunter_running; then
        print_ok "Rayhunter responding: http://$ORBIC_GATEWAY:$RAYHUNTER_PORT"
    else
        print_warn "Rayhunter not responding (may still be starting)"
    fi
    
    # Start ntfy if not running
    if is_ntfy_running; then
        print_warn "ntfy already running (PID: $(cat "$NTFY_PID_FILE"))"
    else
        print_info "Starting ntfy server on port $NTFY_PORT..."
        ntfy serve --listen-http ":$NTFY_PORT" --behind-proxy --no-log-dates &>"$NTFY_LOG_FILE" &
        echo $! > "$NTFY_PID_FILE"
        sleep 1
        
        if is_ntfy_running; then
            print_ok "ntfy started (PID: $(cat "$NTFY_PID_FILE"))"
        else
            print_error "Failed to start ntfy. Check $NTFY_LOG_FILE"
            exit 1
        fi
    fi
    
    # Get LAN interface for phone subscription
    local lan_iface lan_ip
    lan_iface=$(find_lan_interface)
    lan_ip=$(get_iface_ip "$lan_iface")
    
    echo ""
    echo -e "${BOLD}=== Configuration ===${NC}"
    echo ""
    echo -e "${BOLD}Rayhunter ntfy URL:${NC}"
    echo -e "  ${CYAN}http://$usb_ip:$NTFY_PORT/$NTFY_TOPIC${NC}"
    echo ""
    if [ -n "$lan_ip" ]; then
        echo -e "${BOLD}Phone subscription URL:${NC}"
        echo -e "  ${CYAN}http://$lan_ip:$NTFY_PORT/$NTFY_TOPIC${NC}"
        echo ""
    fi
    echo -e "${BOLD}Test command:${NC}"
    echo -e "  curl -d 'test' http://$usb_ip:$NTFY_PORT/$NTFY_TOPIC"
    echo ""
    echo -e "Run '${BOLD}$SCRIPT_NAME tunnel${NC}' for remote UI access commands"
    echo ""
}

cmd_stop() {
    echo -e "${BOLD}=== Stopping Orbic Rayhunter ===${NC}"
    
    if [ -f "$NTFY_PID_FILE" ]; then
        local pid
        pid=$(cat "$NTFY_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            print_info "Stopping ntfy (PID: $pid)..."
            kill "$pid"
            rm -f "$NTFY_PID_FILE"
            print_ok "ntfy stopped"
        else
            print_warn "ntfy not running, cleaning up stale PID file"
            rm -f "$NTFY_PID_FILE"
        fi
    else
        print_warn "ntfy not running"
    fi
}

cmd_status() {
    echo -e "${BOLD}=== Orbic Rayhunter Status ===${NC}"
    echo ""
    
    # USB Interface
    local usb_iface usb_ip
    usb_iface=$(find_usb_interface)
    if [ -n "$usb_iface" ]; then
        usb_ip=$(get_iface_ip "$usb_iface")
        if [ -n "$usb_ip" ]; then
            echo -e "USB Interface:  ${GREEN}$usb_iface ($usb_ip)${NC}"
        else
            echo -e "USB Interface:  ${YELLOW}$usb_iface (no IP)${NC}"
        fi
    else
        echo -e "USB Interface:  ${RED}Not found${NC}"
    fi
    
    # Orbic
    if check_orbic_reachable; then
        echo -e "Orbic Gateway:  ${GREEN}$ORBIC_GATEWAY${NC}"
    else
        echo -e "Orbic Gateway:  ${RED}Unreachable ($ORBIC_GATEWAY)${NC}"
    fi
    
    # Rayhunter
    if check_rayhunter_running; then
        echo -e "Rayhunter:      ${GREEN}http://$ORBIC_GATEWAY:$RAYHUNTER_PORT${NC}"
    else
        echo -e "Rayhunter:      ${RED}Not responding${NC}"
    fi
    
    # ntfy
    if is_ntfy_running; then
        echo -e "ntfy Server:    ${GREEN}Running (PID: $(cat "$NTFY_PID_FILE"))${NC}"
    else
        echo -e "ntfy Server:    ${RED}Not running${NC}"
    fi
    
    # URLs
    if is_ntfy_running && [ -n "$usb_ip" ]; then
        local lan_iface lan_ip
        lan_iface=$(find_lan_interface)
        lan_ip=$(get_iface_ip "$lan_iface")
        
        echo ""
        echo -e "${BOLD}URLs:${NC}"
        echo -e "  Rayhunter config: ${CYAN}http://$usb_ip:$NTFY_PORT/$NTFY_TOPIC${NC}"
        [ -n "$lan_ip" ] && echo -e "  Phone subscribe:  ${CYAN}http://$lan_ip:$NTFY_PORT/$NTFY_TOPIC${NC}"
    fi
    echo ""
}

cmd_test() {
    local usb_iface usb_ip
    usb_iface=$(find_usb_interface)
    usb_ip=$(get_iface_ip "$usb_iface")
    
    if [ -z "$usb_ip" ]; then
        print_error "USB interface not ready"
        exit 1
    fi
    
    if ! is_ntfy_running; then
        print_error "ntfy server not running. Run '$SCRIPT_NAME start' first."
        exit 1
    fi
    
    print_info "Sending test notification..."
    local response
    response=$(curl -s -d "Rayhunter test $(date '+%Y-%m-%d %H:%M:%S')" "http://$usb_ip:$NTFY_PORT/$NTFY_TOPIC")
    
    if echo "$response" | grep -q '"id"'; then
        print_ok "Notification sent! Check your ntfy app."
    else
        print_error "Failed to send notification"
        echo "$response"
        exit 1
    fi
}

cmd_logs() {
    if [ -f "$NTFY_LOG_FILE" ]; then
        tail -f "$NTFY_LOG_FILE"
    else
        print_error "No log file found at $NTFY_LOG_FILE"
        exit 1
    fi
}

cmd_tunnel() {
    local lan_iface lan_ip
    lan_iface=$(find_lan_interface)
    lan_ip=$(get_iface_ip "$lan_iface")
    
    if [ -z "$lan_ip" ]; then
        print_error "Could not detect LAN IP address"
        exit 1
    fi
    
    local user="${ORBIC_SSH_USER:-$(whoami)}"
    
    echo -e "${BOLD}=== SSH Tunnel Commands ===${NC}"
    echo ""
    echo "Run one of these commands from another computer on your network"
    echo "to access the Orbic web interfaces through this host."
    echo ""
    echo -e "${BOLD}Rayhunter UI only:${NC}"
    echo -e "  ${CYAN}ssh -L 8080:$ORBIC_GATEWAY:$RAYHUNTER_PORT $user@$lan_ip${NC}"
    echo -e "  Then open: ${GREEN}http://localhost:8080${NC}"
    echo ""
    echo -e "${BOLD}Orbic OEM Admin only:${NC}"
    echo -e "  ${CYAN}ssh -L 8081:$ORBIC_GATEWAY:$ORBIC_ADMIN_PORT $user@$lan_ip${NC}"
    echo -e "  Then open: ${GREEN}http://localhost:8081${NC}"
    echo ""
    echo -e "${BOLD}Both interfaces:${NC}"
    echo -e "  ${CYAN}ssh -L 8080:$ORBIC_GATEWAY:$RAYHUNTER_PORT -L 8081:$ORBIC_GATEWAY:$ORBIC_ADMIN_PORT $user@$lan_ip${NC}"
    echo -e "  Then open:"
    echo -e "    Rayhunter:   ${GREEN}http://localhost:8080${NC}"
    echo -e "    OEM Admin:   ${GREEN}http://localhost:8081${NC}"
    echo ""
    echo -e "${BOLD}Background tunnel (add -fN):${NC}"
    echo -e "  ${CYAN}ssh -fN -L 8080:$ORBIC_GATEWAY:$RAYHUNTER_PORT -L 8081:$ORBIC_GATEWAY:$ORBIC_ADMIN_PORT $user@$lan_ip${NC}"
    echo ""
}

cmd_install() {
    local install_path="/usr/local/bin/orbic-rayhunter"
    local script_path
    script_path=$(realpath "$0")
    
    if [ "$EUID" -ne 0 ]; then
        echo "Installing to $install_path (requires sudo)..."
        sudo cp "$script_path" "$install_path"
        sudo chmod +x "$install_path"
    else
        cp "$script_path" "$install_path"
        chmod +x "$install_path"
    fi
    
    print_ok "Installed to $install_path"
    echo "You can now run: orbic-rayhunter start"
}

cmd_uninstall() {
    local install_path="/usr/local/bin/orbic-rayhunter"
    
    if [ -f "$install_path" ]; then
        if [ "$EUID" -ne 0 ]; then
            sudo rm -f "$install_path"
        else
            rm -f "$install_path"
        fi
        print_ok "Removed $install_path"
    else
        print_warn "Not installed at $install_path"
    fi
}

show_help() {
    cat <<EOF
${BOLD}orbic-rayhunter${NC} - Rayhunter notification bridge via local ntfy

${BOLD}USAGE:${NC}
    $SCRIPT_NAME <command> [options]

${BOLD}COMMANDS:${NC}
    start       Start ntfy server and display configuration URLs
    stop        Stop ntfy server
    status      Show status of all components
    test        Send a test notification
    logs        Tail the ntfy server logs
    tunnel      Show SSH tunnel commands for remote UI access
    install     Install script to /usr/local/bin
    uninstall   Remove script from /usr/local/bin

${BOLD}OPTIONS:${NC}
    -h, --help      Show this help message
    -v, --version   Show version

${BOLD}ENVIRONMENT VARIABLES:${NC}
    ORBIC_NTFY_PORT       ntfy server port (default: 8080)
    ORBIC_NTFY_TOPIC      Notification topic (default: rayhunter)
    ORBIC_GATEWAY         Orbic gateway IP (default: 192.168.1.1)
    ORBIC_RAYHUNTER_PORT  Rayhunter web UI port (default: 8080)
    ORBIC_ADMIN_PORT      Orbic OEM admin port (default: 80)
    ORBIC_SSH_USER        SSH username for tunnel command (default: current user)

${BOLD}EXAMPLES:${NC}
    $SCRIPT_NAME start                      # Start and show config URLs
    $SCRIPT_NAME status                     # Check component status
    $SCRIPT_NAME test                       # Send test notification
    $SCRIPT_NAME tunnel                     # Show SSH tunnel commands
    ORBIC_NTFY_TOPIC=alerts $SCRIPT_NAME start  # Use custom topic

${BOLD}SETUP:${NC}
    1. Connect Orbic to host via USB, enable USB tethering on Orbic
    2. Run '$SCRIPT_NAME start'
    3. Run '$SCRIPT_NAME tunnel' to get SSH command for remote access
    4. From another computer, run the SSH tunnel command
    5. Open http://localhost:8080 to access Rayhunter UI
    6. Copy the Rayhunter ntfy URL into Rayhunter's settings
    7. Subscribe to the Phone URL in the ntfy app on your phone
    8. Run '$SCRIPT_NAME test' to verify

${BOLD}MORE INFO:${NC}
    https://github.com/EFForg/rayhunter
    https://ntfy.sh

EOF
}

show_version() {
    echo "orbic-rayhunter $VERSION"
}

# ============================================================================
# Main
# ============================================================================

case "${1:-}" in
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    status)     cmd_status ;;
    test)       cmd_test ;;
    logs)       cmd_logs ;;
    tunnel)     cmd_tunnel ;;
    install)    cmd_install ;;
    uninstall)  cmd_uninstall ;;
    -h|--help|help)
        show_help
        ;;
    -v|--version|version)
        show_version
        ;;
    "")
        show_help
        exit 1
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Run '$SCRIPT_NAME --help' for usage"
        exit 1
        ;;
esac
