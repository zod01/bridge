#!/bin/bash

source /etc/os-release

# Define color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
GRAY="\033[1;30m"
BOLD="\033[1m"
DIM="\033[2m"
NC="\033[0m" # No Color

# Logging Helpers
log_info() {
  echo -e "${CYAN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[ OK ]${NC} $1"
}

log_error() {
  echo -e "${RED}[FAIL]${NC} $1"
}

log_step() {
  echo -e "${BLUE}[$1/$2]${NC} $3"
}

# Banner
clear
echo -e "${BOLD}${BLUE}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║                                                        ║"
echo "║        Linux Bridge Configuration Script               ║"
echo "║              Network Bridge Setup                      ║"
echo "║                                                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# OS Detection
is_ubuntu() {
  [[ "$ID" == "ubuntu" ]]
}

is_rhel_basedos() {
  major_version="${VERSION_ID%%.*}"
  [[ "$ID" =~ ^(almalinux|rocky|centos)$ ]] && [[ "$major_version" -ge 8 ]]
}

validate_os() {

  if is_ubuntu || is_rhel_basedos; then
    log_success "Supported OS detected: $PRETTY_NAME"
  else
    log_error "Unsupported operating system"
    log_info "Detected OS: $PRETTY_NAME"
    exit 1
  fi

}

# checking if the script runs as root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}--- The scipt must be run as root ---${NC} "
  exit 1
fi

validate_os

# Detect Network Interface and IP netmask and gateway
IFACE=$(ip route show default | awk '{print $5}')

if [[ "$IFACE" == "viifbr0" ]]; then
  echo -e "${BLUE}--- The bridge interface is already UP/online ---${NC}"
  exit 1
fi

IP_NET=$(ip -4 addr show $IFACE | grep inet | grep -v '127.0.0.1' | awk '{print $2}') # this commmand retrive IP/prefix

IP=$(ip -4 addr show $IFACE | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1) # only IP

GW=$(ip route show default | awk '{print $3}')

log_info "Detected interface: $IFACE"

log_info "IPv4 address: $IP_NET"

log_info "Gateway: $GW"

# IPv6 check
log_step 1 5 "Checking IPv6 configuration"
IPV6_ADDR=""
IPV6_GW=""

IPV6=$(ip -6 addr show dev $IFACE scope global | grep -w inet6 | awk '{print $2}')
if [[ -n "$IPV6" ]]; then
  IPV6_ADDR=$IPV6
  IPV6_GW=$(ip -6 route | awk '/default via/ {print $3; exit}')

  log_success "IPv6 detected"
  log_info "IPv6 address: $IPV6_ADDR"
  log_info "IPv6 gateway: $IPV6_GW"
else
  log_warn "IPv6 not detected"
fi

# INstall ipcalc command
log_step 2 5 "Checking ipcalc dependency"
if ! command -v ipcalc >/dev/null; then
  log_warn "ipcalc is not installed"

  # Install ipcalc
  if is_ubuntu; then
    log_info "Installing ipcalc...."
    if apt-get update -y && apt-get install ipcalc -y >/dev/null 2>&1; then
      log_success "ipcalc installed successfully"
    else
      log_error "Failed to install ipcalc!"
      log_info "Manual installation required:"
      log_info "sudo apt-get update && sudo apt-get install ipcalc"
      exit 1
    fi
  elif is_rhel_basedos; then
    log_info "Installing ipcalc..."
    if dnf install ipcalc -y >/dev/null 2>&1; then
      log_success "ipcalc installed successfully"
    else
      log_error "Failed to install ipcalc"
      log_info "Manual installation required:"
      log_info "sudo dnf install ipcalc"
      exit 1
    fi
  fi

fi

# check server provider
ISP=$(curl -s --max-time 5 ipinfo.io/org 2>/dev/null | tr '[:upper:]' '[:lower:]')

case "$ISP" in
*ovh*)
  PROVIDER="OVH"
  ;;
*hetzner*)
  PROVIDER="Hetzner"
  ;;
*)
  PROVIDER="unknown"
  ;;
esac
log_info "Server provider: $PROVIDER "

# Hetzner netmask
if [[ $PROVIDER == "hetzner" ]]; then
  echo -e "${CYAN}${BOLD} Hetzner configuration required "
  echo -e "${YELLOW}Hetzner servers require manual netmask configuration.${NC}"
  echo -e "${DIM}Please find the correct netmask in your Hetzner Cloud Console.${NC}"

  while true; do
    echo -n -e "${CYAN}Enter netmask (e.g., 255.255.255.0): ${NC}"
    read -r NETMASK
    if [[ "$NETMASK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      CIDR=$(ipcalc $IP $NETMASK | awk '/Netmask/ {print $4}')
      if [[ $? -eq 0 && -n "$CIDR" ]]; then
        echo -e "${GREEN} Valid netmask $NETMASK (CIDR: /$CIDR) "
        break
      else
        echo -e "${RED} Failed to calculate CIDR from $NETMASK ${NC}"
        echo -e "${DIM}255.255.255.0  (/24)${NC}"
        echo -e "${DIM}255.255.0.0    (/16)${NC}"
        echo -e "${DIM}255.0.0.0      (/8)${NC}"
      fi
    fi
  done
fi

# Get MAC address
MAC=$(cat /sys/class/net/$IFACE/address)

BACKUP() {
  NETPLAN=$(ls /etc/netplan/ 2>/dev/null | head -n1)

  # create backup
  echo -e "${GRAY} Backing up current netplan config: $NETPLAN "
  if ! cp /etc/netplan/$NETPLAN /etc/netplan/$NETPLAN-bak; then
    echo -e "${ERROR} Failed to backup $NETPLAN "
    exit 1
  fi
}

###########################################
# Ubuntu Bridge Setup using Netplan
###########################################
setup_bridge_ubuntu() {
  echo -e "${CYAN}${BOLD} Starting Ubuntu bridge with Netplan..."
  BACKUP
  # Create temporary config file for validation

  TEMP_CONFIG="/tmp/netplan-config.yaml"
  cat >"$TEMP_CONFIG" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
  bridges:
    viifbr0:
      addresses:
        - $IP_NET
        ${IPV6_ADDR:+- $IPV6_ADDR}
      interfaces: [ $IFACE ]
      gateway4: $GW
      ${IPV6_GW:+gateway6: $IPV6_GW}
      macaddress: $MAC
      nameservers:
         addresses:
           - 8.8.8.8
           - 8.8.4.4
EOF
  # Validate YAML syntax
  if ! python3 -c "import yaml; yaml.safe_load(open('$TEMP_CONFIG'))" 2>/dev/null; then
    echo -e "${RED} Generated netplan configuration has invalid YAML syntax"
    rm -f "$TEMP_CONFIG"
    exit 1
  fi

  # apply netplan
  if cp $TEMP_CONFIG /etc/netplan/$NETPLAN; then
    echo -e "${GREEN} Netplan config created ${NC}"
    rm -rf $TEMP_CONFIG

    echo -e "${YELLOW}Applying netplan configuration...${NC}"
    if netplan apply 2>/dev/null; then
      echo -e "${GREEN} Applied netplan configuration successfully"
    else
      echo -e "${RED} Failed to apply netplan configuration"
    fi
  else
    echo -e "${RED} Failed to apply netplan"
    rm -f "$TEMP_CONFIG"
    exit 1
  fi

  echo -e "${GREEN} Bridge created successfully on $ID $VERSION"

}

hetzner() {
  echo -e "${CYAN}${BOLD} Starting Ubuntu bridge with Netplan..."
  BACKUP
  # Create temporary config file for validation

  TEMP_CONFIG="/tmp/netplan-config.yaml"
  cat >"$TEMP_CONFIG" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
  bridges:
    viifbr0:
      addresses:
        - $IP/$CIDR
        ${IPV6_ADDR:+- $IPV6_ADDR}
      interfaces: [ $IFACE ]
      route:
	- on-link: true
	  to: 0.0.0.0/0
	  via: $GW 
      ${IPV6_GW:+gateway6: $IPV6_GW}
      macaddress: $MAC
      nameservers:
         addresses:
           - 8.8.8.8
           - 8.8.4.4
EOF
  # Validate YAML syntax
  if ! python3 -c "import yaml; yaml.safe_load(open('$TEMP_CONFIG'))" 2>/dev/null; then
    echo -e "${RED} Generated netplan configuration has invalid YAML syntax"
    rm -f "$TEMP_CONFIG"
    exit 1
  fi

  # apply netplan
  if cp $TEMP_CONFIG /etc/netplan/$NETPLAN; then
    echo -e "${GREEN} Netplan config created ${NC}"
    rm -rf $TEMP_CONFIG

    echo -e "${YELLOW}Applying netplan configuration...${NC}"
    if netplan apply 2>/dev/null; then
      echo -e "${GREEN} Applied netplan configuration successfully"
    else
      echo -e "${RED} Failed to apply netplan configuration"
    fi
  else
    echo -e "${RED} Failed to apply netplan"
    rm -f "$TEMP_CONFIG"
    exit 1
  fi

  echo -e "${GREEN} Bridge created successfully on $ID $VERSION"

}

ovh() {
  echo -e "${CYAN}${BOLD} Starting Ubuntu bridge with Netplan..."
  BACKUP
  # Create temporary config file for validation

  TEMP_CONFIG="/tmp/netplan-config.yaml"
  cat >"$TEMP_CONFIG" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
  bridges:
    viifbr0:
      addresses:
        - $IP_NET
        ${IPV6_ADDR:+- $IPV6_ADDR}
      interfaces: [ $IFACE ]
      route:
	- on-link: true
	  to: 0.0.0.0/0
	  via: $GW 
      ${IPV6_GW:+gateway6: $IPV6_GW}
      macaddress: $MAC
      nameservers:
         addresses:
           - 8.8.8.8
           - 8.8.4.4
EOF
  # Validate YAML syntax
  if ! python3 -c "import yaml; yaml.safe_load(open('$TEMP_CONFIG'))" 2>/dev/null; then
    echo -e "${RED} Generated netplan configuration has invalid YAML syntax"
    rm -f "$TEMP_CONFIG"
    exit 1
  fi

  # apply netplan
  if cp $TEMP_CONFIG /etc/netplan/$NETPLAN; then
    echo -e "${GREEN} Netplan config created ${NC}"
    rm -rf $TEMP_CONFIG

    echo -e "${YELLOW}Applying netplan configuration...${NC}"
    if netplan apply 2>/dev/null; then
      echo -e "${GREEN} Applied netplan configuration successfully"
    else
      echo -e "${RED} Failed to apply netplan configuration"
    fi
  else
    echo -e "${RED} Failed to apply netplan"
    rm -f "$TEMP_CONFIG"
    exit 1

    echo -e "${GREEN} Bridge created successfully on $ID $VERSION"

  fi
}

# rhel based os
default_bridge() {
  log_step "Configuring RHEL-based Bridge with NetworkManager "

  # interface Nmae
  CON_NAME=$(nmcli -t -f NAME,DEVICE connection show | grep ":$IFACE" | cut -d: -f1)

  log_info "Interface Name: $CON_NAME "

  if [[ -z "$CON_NAME" ]]; then
    log_warn "No NetworkManager connection found for interface $IFACE"
    exit 1
  fi

  log_step "Creating bridge..."
  if ! nmcli connection add type bridge con-name viifbr0 ifname viifbr0 autoconnect yes; then
    log_error " Failed to create bridge connection"
    exit 1
  fi

  nmcli connection modify viifbr0 ipv4.addresses "$IP_NET" ipv4.gateway "$GW" ipv4.dns '8.8.8.8' ipv4.method manual

  if [[ -n "$IPV6_ADDR" ]]; then
    nmcli connection modify viifbr0 ipv6.addresses "$IPV6_ADDR" ipv6.gateway "$IPV6_GW" ipv6.method manual ipv6.dns "2001:4860:4860::8888"
  fi
  nmcli connection modify "$CON_NAME" master viifbr0
  nmcli connection modify viifbr0 connection.autoconnect-slaves 1

  log_warn "Bringing up bridge connections..."
  nmcli connection up viifbr0

  log_warn "Bringing UP $CON_NAME"
  nmcli connection up "$CON_NAME"

  log_success "Bridge created successfully on $ID $VERSION"
}

hetzner_rhel() {

  # interface Nmae
  CON_NAME=$(nmcli -t -f NAME,DEVICE connection show | grep ":$IFACE" | cut -d: -f1)

  echo -e "${GRAY} Interface Name: $CON_NAME ${NC}"

  if [[ -z "$CON_NAME" ]]; then
    log_warn "No NetworkManager connection found for interface $IFACE"
    exit 1
  fi

  echo -e "${GRAY} Creating bridge..."
  if ! nmcli connection add type bridge con-name viifbr0 ifname viifbr0 autoconnect yes; then
    log_error "Failed to create bridge connection"
    exit 1
  fi

  nmcli connection modify viifbr0 ipv4.addresses "$IP/$CIDR" ipv4.gateway "$GW" ipv4.dns '8.8.8.8' ipv4.method manual

  if [[ -n "$IPV6_ADDR" ]]; then
    nmcli connection modify viifbr0 ipv6.addresses "$IPV6_ADDR" ipv6.gateway "$IPV6_GW" ipv6.method manual ipv6.dns "2001:4860:4860::8888"
  fi
  nmcli connection modify "$CON_NAME" master viifbr0
  nmcli connection modify viifbr0 connection.autoconnect-slaves 1

  log_warn "Bringing up bridge connections..."
  nmcli connection up viifbr0

  log_warn "Bringing UP $CON_NAME"
  nmcli connection up "$CON_NAME"

  log_success "Bridge created successfully on $ID $VERSION"

}

# timeout and ping test
check_connectivity() {
  log_step 4 5 "Testing connectivity"
  if is_rhel_basedos; then
    ROLLBACK_WAIT=${ROLLBACK_WAIT:-30}
  else
    ROLLBACK_WAIT=${ROLLBACK_WAIT:-15}
  fi

  TEST_HOST=${TEST_HOST:-8.8.8.8}

  log_info "Waiting ${ROLLBACK_WAIT}s for network stabilization"
  sleep "$ROLLBACK_WAIT"

  if ping -w 5 -c 2 "$TEST_HOST" >/dev/null 2>&1; then
    log_success "Connectivity test passed"
    return 0
  else
    log_error "Connectivity test failed"
    return 1
  fi
}

# Rollback
rollback() {
  log_warn "Starting automatic rollback"
  if is_ubuntu; then
    BACKUP="/etc/netplan/${NETPLAN}-bak"
    if [[ ! -f "$BACKUP" ]]; then
      echo -e "${RED} No backup .yaml found - cannot rollback"
      exit 2
    fi

    log_warn "Restoring backup configuration"

    log_info "Restoring ${NETPLAN}-bak"

    if cp --archive "$BACKUP" "/etc/netplan/${NETPLAN}"; then
      echo -e "${GREEN} Configuration file restored"
      if netplan apply; then
        log_success "Netplan applied successfully"

        if ip link delete dev viifbr0 2>/dev/null; then
          echo -e "${GREEN} Bridge viifbr0 removed"
        fi
        rm -rf "$BACKUP"

        log_success "Rollback completed successfully"
      else
        log_error "Failed to apply netplan configuration"
      fi
    else
      log_error "Failed to restore backup configuration "
    fi

  fi

  if is_rhel_basedos; then
    log_warn "Rolling back NetworkManager configuration..."

    log_info "Bringing down bridge viifbr0"
    nmcli connection down viifbr0

    log_info "Removing bridge slave configuration from $CON_NAME"
    eval 'nmcli connection modify "${CON_NAME}" connection.master "" connection.slave-type ""'

    log_info "Bringing up the interface $CON_NAME"
    nmcli connection up "${CON_NAME}"

    log_info "Deleting bridge connection viifbr0"
    nmcli connection delete viifbr0

    log_success "Rollback completed successfully"
    exit 2
  fi
}

#
if is_ubuntu; then
  case "$PROVIDER" in
  hetzner)
    hetzner
    ;;
  ovh)
    ovh
    ;;
  *)
    setup_bridge_ubuntu
    ;;
  esac
elif is_rhel_basedos && [[ "${VERSION_ID%%.*}" -ge 8 ]]; then
  case "$PROVIDER" in
  hetzner)
    hetzner_rhel
    ;;
  *)
    default_bridge
    ;;
  esac
fi

# rollnback
if check_connectivity; then
  print_box_line() {
    printf "${GREEN}║ %-52s ║${NC}\n" "$1"
  }

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"

  print_box_line "✓ Bridge Configuration Successful"
  print_box_line ""
  print_box_line "Bridge Name: viifbr0"
  print_box_line "Physical Interface: $IFACE"
  print_box_line "IP Address: $IP_NET"
  print_box_line "Gateway: $GW"
  print_box_line "Provider: $ISP"
  print_box_line ""
  print_box_line "Status: ONLINE"

  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"

  echo ""
  log_success "Bridge viifbr0 is ready for use"
else
  rollback
fi

history -r
