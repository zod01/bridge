#!/bin/bash

#
# Author: Aman Shaikh
# Version: 2.1
# Description: Interactive script to configure a Linux bridge on Ubuntu (Netplan)
#              or AlmaLinux (nmcli), with ipcalc check and color-coded output.



source /etc/os-release

trap 'rm -- "$0"' EXIT

# Define color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m" # No Color


# Logging functions
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  case "$level" in 
    INFO)     echo -e "${BLUE}ℹ ${NC} $message" ;;
    SUCCESS)  echo -e "${GREEN}✓${NC} $message" ;;
    WARN)     echo -e "${YELLOW}"⚠ ${NC}   $message ;;
    ERROR)   echo -e "${RED}✗${NC}  $message" ;;
    STEP)    echo -e "\n${CYAN}${BOLD}▸ $message${NC}" ;;
  esac
}



# Banner
clear
echo -e "${BOLD}${BLUE}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║                                                        ║"
echo "║        Linux Bridge Configuration Script              ║"
echo "║              Network Bridge Setup                      ║"
echo "║                                                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"
log INFO "Script started by user: $(whoami)"



# Detect Network Interface 
IFACE=$(ip route show default | awk '{print $5}')
log INFO "Defualt interface: $IFACE"

IP_NET=$(ip -4 addr show $IFACE | grep inet | grep -v '127.0.0.1' | awk '{print $2}')

IP=$(ip -4 addr show $IFACE | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)

GW=$(ip route show default | awk '{print $3}')

log INFO "IPV4 addressh: $IP_NET"
log INFO "GATEWAY: $GW"


# Check if ipcalc is installed
log INFO "Checking if ipcalc is installed"
if ! command -v ipcalc >/dev/null; then
    log WARN "ipcalc not found, attempting to install...."


    if grep -qi 'ubuntu' /etc/os-release; then
        apt-get update -y >/dev/null 2>&1 && apt-get install -y ipcalc >/dev/null 2>&1 
        if [[ $? = 0 ]]; then
          log SUCCESS "ipcalc is successfully installed"
        else
          log ERROR "Failed to install ipcalc."
          exit 1
        fi
    elif [[ "$ID" == "almalinux" || "$ID" == "rocky" || "$ID" == "centos" ]]; then
        dnf install -y ipcalc >/dev/null 2>&1
        if [[ $? = 0  ]]; then
          log SUCCESS "ipcalc is successfully install"
          else
            log ERROR "Failed to install ipcalc."
            exit 1 
        fi

    else
        log ERROR "Unsupported OS. Please install ipcalc manually."
        exit 1
    fi
fi


# Checking IPv6
log STEP "checking IPv6 configuration"
IPV6_ADDR=""
IPV6_GW=""

IPV6=$(ip -6 addr show dev $IFACE scope global | grep -w inet6  | awk '{print $2}')
if [[ -n "$IPV6" ]]; then
  IPV6_ADDR=$IPV6
  IPV6_GW=$(ip -6 route | awk '/default via/ {print $3; exit}')
  log INFO "IPV6 address: $IPV6"
  log INFO "IPV6 gateway: $IPV6_GW"
else
  log WARN "No IPV6 found"
fi

# Check if interface exists:
if ! ip link show "$IFACE" >/dev/null 2>&1; then
    log ERROR "Interface $IFACE not found."
    exit 1
fi

# Detecting if provider is OVH or Hetzner
log STEP "Detecting server provider"
DATA=$(curl -sS ipinfo.io/$IP 2>/dev/null)
if echo "$DATA" | grep -q '"bogon": true'; then
    log WARN "Private IP detected. Skipping ISP detection"
    ISP="private"
else
    ISP=$(echo "$DATA" | grep -Eio "hetzner|ovh")
fi

log INFO "Detected ISP: ${ISP:-Unknown}"


# gathering correct netmask
if [[ $ISP == "Hetzner" ]]
then
  log STEP "Hetzner configuration required"

  while true; do
	read -p "Your server is from $ISP so you need to provide the correct nastmask from hetnzer panel.! (eq.. 255.255.255.0): " NETMASK
  if [[ "$NETMASK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
  then
	CIDR=$(ipcalc $IP $NETMASK | awk '/Netmask/ {print $4}')
  log INFO "Netmask: $NETMASK (CIDR: /$CIDR)"
  break
else
  log ERROR "Invalid netmask format. Please try again."
  fi 
done

fi


# Get MAC address
MAC=$(cat /sys/class/net/$IFACE/address)


###########################################
# Ubuntu Bridge Setup using Netplan
###########################################
setup_bridge_ubuntu() {
log STEP "Starting Ubuntu bridge with Netplan..."

# considering the server don't have multiples .yamls file
NETPLAN=$(ls /etc/netplan/ | head -n1)

# create backup of .yaml
log INFO "Backing up current netplan config: $NETPLAN"
cp /etc/netplan/$NETPLAN /etc/netplan/$NETPLAN-bak

log INFO "Creating new netplan configuration..."
cat > /etc/netplan/$NETPLAN <<EOF
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

    netplan apply 2>/dev/null
    log SUCCESS "Applied Default Netplan configuration.."
}

# OVH/Hetzner netplan
hetzner_netplan() {

log STEP "Starting Ubuntu bridge with Netplan..."

# considering the server don't have multiples .yamls file
NETPLAN=$(ls /etc/netplan/ | head -n1)

# create backup of .yaml
log INFO "Backing up current netplan config: $NETPLAN"
cp /etc/netplan/$NETPLAN /etc/netplan/$NETPLAN-bak

log INFO "Creating new netplan configuration..."
cat > /etc/netplan/$NETPLAN <<EOF
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
      routes:
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
    
    netplan apply 2>/dev/null
    log SUCCESS "Applied Hetzner Netplan config"
}



ovh_netplan() {

log STEP "Starting Ubuntu bridge with Netplan..."

# considering the server don't have multiples .yamls file
NETPLAN=$(ls /etc/netplan/ | head -n1)

# create backup of .yaml
log INFO "Backing up current netplan config: $NETPLAN"
cp /etc/netplan/$NETPLAN /etc/netplan/$NETPLAN-bak

log INFO "Creating new netplan configuration..."
cat > /etc/netplan/$NETPLAN <<EOF
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
      routes:
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

    netplan apply 2>/dev/null
    log SUCCESS "Applied OVH/Hetzner Netplan config.."	
}


# Redhat based linux OS setup
setup_bridge_rhel() {
  log STEP "Configuring RHEL-based Bridge with NetworkManager"

    CON_NAME=$(nmcli -t -f NAME,DEVICE connection show | grep ":$IFACE" | cut -d: -f1)
    log INFO "Connection name: $CON_NAME"

    nmcli connection add type bridge con-name viifbr0 ifname viifbr0 autoconnect yes
    nmcli connection modify viifbr0 ipv4.addresses "$IP_NET" ipv4.gateway "$GW" ipv4.dns '8.8.8.8'  ipv4.method manual

    if [[ -n "$IPV6_ADDR" ]]; then
    nmcli connection modify viifbr0 ipv6.addresses "$IPV6_ADDR" ipv6.gateway "$IPV6_GW" ipv6.method manual ipv6.dns "2001:4860:4860::8888"
else
    nmcli connection modify viifbr0 ipv6.method ignore
fi
    nmcli connection modify "$CON_NAME" master viifbr0
    nmcli connection modify viifbr0 connection.autoconnect-slaves 1
    nmcli connection up viifbr0
    nmcli connection up "$CON_NAME"

    log SUCCESS "Bridge created successfully $ID:"
}

hetzner_rhel() {
  log STEP "Configuring Hetzner RHEL Bridge with NetworkManager"

	CON_NAME=$(nmcli -t -f NAME,DEVICE connection show | grep ":$IFACE" | cut -d: -f1)

	nmcli connection add type bridge con-name viifbr0 ifname viifbr0 autoconnect yes
	nmcli connection modify viifbr0 ipv4.addresses $IP/$CIDR ipv4.gateway "$GW" ipv4.dns '8.8.8.8' ipv4.method manual
	if [[ -n "$IPV6_ADDR" ]]; then
	nmcli connection modify viifbr0 ipv6.addresses "$IPV6_ADDR" ipv6.gateway "$IPV6_GW" ipv6.dns "2001:4868::8888" ipv6.method manual
else
	nmcli connection modify viifbr0 ipv6.method ignore
	fi
	nmcli connection modify $CON_NAME master viifbr0
	nmcli connection modify viifbr0 connection.autoconnect-slaves 1
	nmcli connection up viifbr0
	nmcli connection up "$CON_NAME"

  log SUCCESS "Bridge created successfully $ID:"

}


###########################################
# OS Detection and Setup Trigger
###########################################
if [[ "$ID" == "ubuntu" ]]
then
  log INFO "Ubuntu detected"
  if [[ "$ISP" == "Hetzner" ]] 
  then
      hetzner_netplan
    elif [[ "$ISP" == OVH ]]
    then
	    ovh_netplan
    else
	    setup_bridge_ubuntu
  fi
elif [[ "$ID" == "almalinux" || "$ID" == "rocky" || "$ID" == "centos" ]]
then
    log INFO "RHEL-based distribution detected: $ID"
    if [[ $ISP == "Hetzner" ]]
    then
	    hetzner_rhel
    else
	    setup_bridge_rhel
    fi
else
   log ERROR "Unsupported OS: $ID"
    echo -e "${RED}This script supports only Ubuntu, AlmaLinux, Rocky Linux, and CentOS Stream${NC}"
    exit 1
fi


##########################################################################################################

#                                      ROLLBACK

##########################################################################################################

# Waiting for viifbr0 stable
if [[ "$ID" == "almalinux" || "$ID" == "centos" || "$ID" == "rocky" ]]
then
  ROLLBACK_WAIT=${ROLLBACK_WAIT:-30}
  log WARN "Waiting $ROLLBACK_WAIT"
else
  ROLLBACK_WAIT=${ROLLBACK_WAIT:-15}
fi

TEST_HOST=${TEST_HOST:-8.8.8.8}

log STEP "Starting Connectivity Test (${ROLLBACK_WAIT}s Stabilization)"
echo ""
echo -e "${YELLOW}⏳ Waiting ${ROLLBACK_WAIT} seconds before testing connectivity...${NC}"

# Visual countdown
for ((i=$ROLLBACK_WAIT; i>0; i--)); do
  printf "\r${CYAN}Time remaining: %2ds${NIC}" $i
  sleep 1
done
echo ""

# Progressive connectivity test with multiple attemptS
CONNECTION_OK=0
for attempt in {1..3}; do
  if ping -W 3 -c 2 "${TEST_HOST}" >/dev/null 2>&1; then
    CONNECTION_OK=1
    log SUCCESS "Connectivity test passed (attempt $attempt/3)"
    break
  else
    log WARN "Ping attempt $attempt/3 failed, retrying..."
    sleep 3
  fi
done

# If connectivity is good, show success and exit
if [[ $CONNECTION_OK -eq 1 ]]
then
  echo ""
  echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                                                        ║${NC}"
  echo -e "${GREEN}║  ✓ Bridge Configuration Successful!                    ║${NC}"
  echo -e "${GREEN}║                                                        ║${NC}"
  echo -e "${GREEN}║  Bridge Name: viifbr0                                  ║${NC}"
  echo -e "${GREEN}║  Interface: $IFACE${BLUE}"
  echo -e "${GREEN}║                                                        ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
  exit 0
fi

# if connectivity failed
log ERROR "Connectivity test failed after 3 attempts, initiating rollback"

echo ""
echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ⚠ CONNECTIVITY TEST FAILED                            ║${NC}"
echo -e "${RED}║  Rolling back to previous configuration...             ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Ubunut restore
if [[ "$ID" == ubuntu ]]
then
  BACKUP="/etc/netplan/${NETPLAN}-bak"
  if [[ ! -f "$BACKUP" ]]
  then
    log ERROR "No backup .yaml found - connont rollback"
    exit 2
  fi
    log INFO "Restoring $BACKUP → ${NETPLAN}"
    cp --archive "$BACKUP" "/etc/netplan/${NETPLAN}"
    netplan apply
    ip link delete dev viifbr0
    rm -rf $BACKUP
    log SUCCESS "Rolled backed to previous configuration"
    echo -e "${YELLOW}Please investigate the issue${NC}"
    exit 2
fi 

# RHEL rollback
if [[ "$ID" == "almalinux" || "$ID" == "rocky" || "$ID" == "centos" ]]
then
  log INFO "Rolling back NetworkManager configuration..."
  nmcli connection down viifbr0
  #nmcli connection modify "${CON_NAME}" connection.master "" connection.slave-type ""
  eval 'nmcli connection modify "${CON_NAME}" connection.master "" connection.slave-type ""'
  nmcli connection up "${CON_NAME}"
  nmcli connection delete viifbr0
  log SUCCESS "Rolled backed to previous configuration"
  echo -e "${YELLOW}Please investigate the issue${NC}"
  exit 2
fi
