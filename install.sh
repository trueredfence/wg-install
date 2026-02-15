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
    apt -y install git python3 python3-pip wireguard net-tools curl firewalld unzip
}

# ========= INSTALL =========
install_wg_dashboard() {
    msg i "Installing WGDashboard to $WG_BASE"

    rm -rf $WG_BASE
    git clone https://github.com/WGDashboard/WGDashboard.git $WG_BASE

    cd $SRC_DIR
    chmod +x wgd.sh
    ./wgd.sh install

    configure_dashboard
    create_service
    configure_firewall

    msg s "Installation completed successfully."
    echo "Access: http://$(hostname -I | awk '{print $1}'):$PORT"
}

# ========= CONFIGURATION =========
configure_dashboard() {
    msg i "Configuring wg-dashboard.ini"

    cp $WG_BASE/templates/wg-dashboard.ini.template $SRC_DIR/wg-dashboard.ini
    # APP_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
    sed -i "s/^app_ip.*/app_ip = $APP_IP/" "$SRC_DIR/wg-dashboard.ini"
    sed -i "s/^app_port.*/app_port = $PORT/" "$SRC_DIR/wg-dashboard.ini"
}

# ========= SYSTEMD SERVICE =========
create_service() {
    msg i "Creating systemd service"

cat > $SERVICE_FILE <<EOF
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
    msg i "Opening firewall port $PORT"
    systemctl start firewalld || true
    firewall-cmd --add-port=${PORT}/tcp --permanent || true
    firewall-cmd --reload || true
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
main_menu() {
    echo ""
    echo "===== Enterprise WGDashboard Manager ====="
    echo "1) Install WGDashboard"
    echo "2) Uninstall WGDashboard"
    echo "3) Service Status"
    echo "4) Exit"
    echo ""

    read -p "Select option: " option

    case $option in
        1)
            install_dependencies
            install_wg_dashboard
            ;;
        2)
            uninstall_wg_dashboard
            ;;
        3)
            status_dashboard
            ;;
        4)
            exit 0
            ;;
        *)
            msg e "Invalid option."
            ;;
    esac
}

# ========= EXECUTION =========
require_root
check_ubuntu
main_menu
