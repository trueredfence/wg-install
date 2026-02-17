#!/bin/bash
set -e

#############################################
# Enterprise WGDashboard Installer
# Ubuntu 22.04+
#############################################

# ========= GLOBAL VARIABLES =========
WG_BASE="/usr/share/WGDashboard"
SRC_DIR="$WG_BASE/src"
SERVICE_FILE="/etc/systemd/system/wgdashboard.service"
PORT=5000
APP_IP="0.0.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========= LOGGER =========
msg() {
    case "$1" in
        i) echo -e "${YELLOW}[INFO]${NC} $2" ;;
        s) echo -e "${GREEN}[SUCCESS]${NC} $2" ;;
        e) echo -e "${RED}[ERROR]${NC} $2" ;;
        *) echo -e "${CYAN}$1${NC}" ;;
    esac
}

# ========= VALIDATION =========
require_root() {
    if [[ $EUID -ne 0 ]]; then
        msg e "Run this script as root."
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -qi ubuntu /etc/os-release; then
        msg e "This installer supports Ubuntu only."
        exit 1
    fi
}

# ========= DEPENDENCIES =========
install_dependencies() {
    msg i "Installing required packages..."
    apt update
    apt -y install git python3 python3-pip wireguard net-tools curl firewalld unzip needrestart
    sed -i "s/^#\?\$nrconf{restart}.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf

}

create_wg1_conf() {
    local WG_CONF="/etc/wireguard/wg1.conf"

    # Ensure root
    if [[ $EUID -ne 0 ]]; then
        echo "Run as root."
        return 1
    fi

    # Detect default outbound interface
    DEFAULT_IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)

    if [[ -z "$DEFAULT_IFACE" ]]; then
        echo "Could not detect default network interface."
        return 1
    fi

    mkdir -p /etc/wireguard

    cat > "$WG_CONF" <<EOF
[Interface]
Address = 10.0.0.1/24
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE
ListenPort = 443
PrivateKey = gPAQ1rA0e/0QFWZM96rtxDqR39BWcovjocKNGItRgHQ=
EOF

    chmod 600 "$WG_CONF"

    echo "wg1.conf created with interface: $DEFAULT_IFACE"
}



# ========= INSTALL =========
install_wg_dashboard() {
    msg i "Installing WGDashboard to $WG_BASE"

    rm -rf $WG_BASE
    git clone https://github.com/WGDashboard/WGDashboard.git $WG_BASE
    configure_dashboard    
    create_wg1_conf
    cd $SRC_DIR
    chmod +x wgd.sh
    msg i "Running WGDashboard installer (auto-select default mirror)"
    printf "1\n" | ./wgd.sh install
    ./wgd.sh start && \
    ./wgd.sh stop  
    
    create_service
    configure_firewall

    msg s "Installation completed successfully."
    echo "Access: http://$(hostname -I | awk '{print $1}'):$PORT"
}


# ========= CONFIGURATION =========
configure_dashboard() {
    msg i "Configuring wg-dashboard.ini"
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null && sudo sysctl -p
    cp $WG_BASE/templates/wg-dashboard.ini.template $SRC_DIR/wg-dashboard.ini
    # APP_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
    sed -i "s/^app_ip.*/app_ip = $APP_IP/" "$SRC_DIR/wg-dashboard.ini"
    sed -i "s/^app_port.*/app_port = $PORT/" "$SRC_DIR/wg-dashboard.ini"
}

# ========= SYSTEMD SERVICE =========
create_service() {
    msg i "Creating systemd service"

cat > "$SERVICE_FILE" <<EOF
[Unit]
After=syslog.target network-online.target
Wants=wg-quick.target
ConditionPathIsDirectory=/etc/wireguard

[Service]
Type=forking
PIDFile=$SRC_DIR/gunicorn.pid
WorkingDirectory=$SRC_DIR
ExecStart=$SRC_DIR/wgd.sh start
ExecStop=$SRC_DIR/wgd.sh stop
ExecReload=$SRC_DIR/wgd.sh restart
TimeoutSec=120
PrivateTmp=yes
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wgdashboard
    systemctl restart wgdashboard
}

# ========= FIREWALL =========
configure_firewall() {
    echo "Firewall configuration"
    #msg i "Opening firewall port $PORT"
    #systemctl start firewalld || true
    #firewall-cmd --add-port=${PORT}/tcp --permanent || true
    #firewall-cmd --reload || true
}

# ========= UNINSTALL =========
uninstall_wg_dashboard() {
    msg e "Uninstalling WGDashboard"

    systemctl stop wgdashboard || true
    systemctl disable wgdashboard || true
    rm -f $SERVICE_FILE
    rm -rf $WG_BASE
    systemctl daemon-reload

    msg s "WGDashboard removed successfully."
}

# ========= STATUS =========
status_dashboard() {
    systemctl status wgdashboard
}

# ========= MENU =========
handle_arguments() {
    case "$1" in
        install)
            install_dependencies
            install_wg_dashboard
            ;;
        uninstall)
            uninstall_wg_dashboard
            ;;
        status)
            status_dashboard
            ;;
        *)
            echo ""
            echo "Usage:"
            echo "  $0 install"
            echo "  $0 uninstall"
            echo "  $0 status"
            echo ""
            exit 1
            ;;
    esac
}


# ========= EXECUTION =========
require_root
check_ubuntu
handle_arguments $1
