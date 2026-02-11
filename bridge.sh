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
MAGENTA="\033[0;35m"
GRAY="\033[1;30m"
BOLD="\033[1m"
DIM="\033[2m"
NC="\033[0m" # No Color

# Debug and verbose flags
DEBUG=false
VERBOSE=false


# Logging functions
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local show_timestamp=false

  # Show timestamp in debug or verbose mode
  [[ "$DEBUG" == true || "$VERBOSE" == true ]] && show_timestamp=true

  case "$level" in 
    DEBUG)    
      [[ "$DEBUG" == true ]] && {
        local ts_prefix=""
        [[ "$show_timestamp" == true ]] && ts_prefix="${GRAY}[$timestamp]${NC} "
        echo -e "${ts_prefix}${MAGENTA}🔧 DEBUG${NC}: $message"
      }
      ;;
    INFO)     
      local ts_prefix=""
      [[ "$show_timestamp" == true ]] && ts_prefix="${GRAY}[$timestamp]${NC} "
      echo -e "${ts_prefix}${BLUE}ℹ${NC} $message" 
      ;;
    SUCCESS)  
      local ts_prefix=""
      [[ "$show_timestamp" == true ]] && ts_prefix="${GRAY}[$timestamp]${NC} "
      echo -e "${ts_prefix}${GREEN}✓${NC} $message" 
      ;;
    WARN)     
      local ts_prefix=""
      [[ "$show_timestamp" == true ]] && ts_prefix="${GRAY}[$timestamp]${NC} "
      echo -e "${ts_prefix}${YELLOW}⚠${NC} $message" 
      ;;
    ERROR)   
      local ts_prefix=""
      [[ "$show_timestamp" == true ]] && ts_prefix="${GRAY}[$timestamp]${NC} "
      echo -e "${ts_prefix}${RED}✗${NC} $message" 
      ;;
    STEP)    
      echo -e "\n${CYAN}${BOLD}▸ $message${NC}" ;;
  esac
}



# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--debug)
      DEBUG=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "  -d, --debug    Enable debug mode with detailed logging"
      echo "  -v, --verbose  Enable verbose output with timestamps"
      echo "  -h, --help     Show this help message"
      exit 0
      ;;
    *)
      log ERROR "Unknown option: $1"
      echo "Use -h for help"
      exit 1
      ;;
  esac
done

# Debug info
log DEBUG "Debug mode: $DEBUG"
log DEBUG "Verbose mode: $VERBOSE"

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
[[ "$VERBOSE" == true || "$DEBUG" == true ]] && echo -e "${GRAY}Mode: $([ "$DEBUG" == true ] && echo "DEBUG" || echo "VERBOSE")${NC}\n"
log INFO "Script started by user: $(whoami)"



# Detect Network Interface 
IFACE=$(ip route show default | awk '{print $5}')
log DEBUG "Command: ip route show default | awk '{print \$5}'"

if [[ -z "$IFACE" ]]; then
  log ERROR "No default interface found!"
  echo -e "${YELLOW}Troubleshooting tips:${NC}"
  echo -e "  • Check if you have network connectivity: ${DIM}ip addr show${NC}"
  echo -e "  • Verify default route: ${DIM}ip route show${NC}"
  echo -e "  • Check network interface status: ${DIM}ip link show${NC}"
  exit 1
fi

log INFO "Default interface: ${CYAN}$IFACE${NC}"

IP_NET=$(ip -4 addr show $IFACE | grep inet | grep -v '127.0.0.1' | awk '{print $2}')
log DEBUG "Command: ip -4 addr show $IFACE | grep inet | grep -v '127.0.0.1' | awk '{print \$2}'"

IP=$(ip -4 addr show $IFACE | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)

GW=$(ip route show default | awk '{print $3}')
log DEBUG "Command: ip route show default | awk '{print \$3}'"

if [[ -z "$IP_NET" || -z "$IP" ]]; then
  log ERROR "No IPv4 address found on interface $IFACE!"
  echo -e "${YELLOW}Troubleshooting tips:${NC}"
  echo -e "  • Check interface configuration: ${DIM}ip addr show $IFACE${NC}"
  echo -e "  • Verify DHCP is working or set static IP"
  echo -e "  • Check if interface is up: ${DIM}ip link show $IFACE${NC}"
  exit 1
fi

if [[ -z "$GW" ]]; then
  log ERROR "No default gateway found!"
  echo -e "${YELLOW}Troubleshooting tips:${NC}"
  echo -e "  • Check routing table: ${DIM}ip route show${NC}"
  echo -e "  • Verify network configuration"
  echo -e "  • Check if router is accessible"
  exit 1
fi

log INFO "IPv4 address: ${CYAN}$IP_NET${NC}"
log INFO "Gateway: ${CYAN}$GW${NC}"


# Check if ipcalc is installed
log INFO "Checking if ipcalc is installed"
if ! command -v ipcalc >/dev/null; then
    log WARN "ipcalc not found, attempting to install..."
    log DEBUG "Package installation will require root privileges"

    if grep -qi 'ubuntu' /etc/os-release; then
        log INFO "Ubuntu detected - using apt package manager"
        echo -e "${YELLOW}Updating package lists...${NC}"
        if apt-get update -y >/dev/null 2>&1; then
            log SUCCESS "Package lists updated"
            echo -e "${YELLOW}Installing ipcalc...${NC}"
            if apt-get install -y ipcalc >/dev/null 2>&1; then
                log SUCCESS "ipcalc installed successfully"
            else
                log ERROR "Failed to install ipcalc with apt"
                echo -e "${YELLOW}Manual installation required:${NC}"
                echo -e "  ${DIM}sudo apt-get update && sudo apt-get install ipcalc${NC}"
                exit 1
            fi
        else
            log ERROR "Failed to update package lists"
            echo -e "${YELLOW}Troubleshooting tips:${NC}"
            echo -e "  • Check internet connectivity"
            echo -e "  • Verify apt sources: ${DIM}cat /etc/apt/sources.list${NC}"
            echo -e "  • Try manual update: ${DIM}sudo apt-get update${NC}"
            exit 1
        fi
    elif [[ "$ID" == "almalinux" || "$ID" == "rocky" || "$ID" == "centos" ]]; then
        log INFO "RHEL-based system detected - using dnf package manager"
        echo -e "${YELLOW}Installing ipcalc...${NC}"
        if dnf install -y ipcalc >/dev/null 2>&1; then
            log SUCCESS "ipcalc installed successfully"
        else
            log ERROR "Failed to install ipcalc with dnf"
            echo -e "${YELLOW}Manual installation required:${NC}"
            echo -e "  ${DIM}sudo dnf install ipcalc${NC}"
            echo -e "${YELLOW}Troubleshooting tips:${NC}"
            echo -e "  • Check internet connectivity"
            echo -e "  • Verify dnf repositories: ${DIM}dnf repolist${NC}"
            echo -e "  • Try updating: ${DIM}sudo dnf update${NC}"
            exit 1
        fi
    else
        log ERROR "Unsupported OS for automatic ipcalc installation: $ID"
        echo -e "${YELLOW}Please install ipcalc manually:${NC}"
        echo -e "  • Ubuntu/Debian: ${DIM}sudo apt-get install ipcalc${NC}"
        echo -e "  • RHEL/CentOS: ${DIM}sudo dnf install ipcalc${NC}"
        echo -e "  • Or download from: ${DIM}https://github.com/jknapier/ipcalc${NC}"
        exit 1
    fi
else
    log SUCCESS "ipcalc is already installed"
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
echo -e "${YELLOW}Querying IP information...${NC}"
DATA=$(curl -sS ipinfo.io/$IP 2>/dev/null)
log DEBUG "curl -sS ipinfo.io/$IP"

if [[ $? -ne 0 ]]; then
  log WARN "Failed to fetch IP information, continuing without ISP detection"
  ISP="unknown"
else
  log DEBUG "IP info data received"
  if echo "$DATA" | grep -q '"bogon": true'; then
      log INFO "Private IP detected. Skipping ISP detection"
      ISP="private"
  else
      ISP=$(echo "$DATA" | grep -Eio "hetzner|ovh")
      [[ -n "$ISP" ]] && log DEBUG "ISP pattern matched: $ISP"
  fi
fi

log INFO "Detected ISP: ${CYAN}${ISP:-Unknown}${NC}"


# gathering correct netmask
if [[ $ISP == "Hetzner" ]]
then
  log STEP "Hetzner configuration required"
  echo -e "${YELLOW}Hetzner servers require manual netmask configuration.${NC}"
  echo -e "${DIM}Please find the correct netmask in your Hetzner Cloud Console.${NC}"

  while true; do
	echo -n -e "${CYAN}Enter netmask (e.g., 255.255.255.0): ${NC}"
	read -r NETMASK
  if [[ "$NETMASK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
  then
	CIDR=$(ipcalc $IP $NETMASK | awk '/Netmask/ {print $4}')
	if [[ $? -eq 0 && -n "$CIDR" ]]; then
	  log SUCCESS "Valid netmask: $NETMASK (CIDR: /$CIDR)"
	  break
	else
	  log ERROR "Failed to calculate CIDR from netmask"
	  echo -e "${YELLOW}Example valid netmasks:${NC}"
	  echo -e "  ${DIM}255.255.255.0  (/24)${NC}"
	  echo -e "  ${DIM}255.255.0.0    (/16)${NC}"
	  echo -e "  ${DIM}255.0.0.0      (/8)${NC}"
	fi
  else
    log ERROR "Invalid netmask format. Use format: 255.255.255.0"
    echo -e "${YELLOW}Common Hetzner netmasks:${NC}"
    echo -e "  ${DIM}255.255.255.192  (for /26)${NC}"
    echo -e "  ${DIM}255.255.255.224  (for /27)${NC}"
    echo -e "  ${DIM}255.255.255.240  (for /28)${NC}"
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

# Validate required variables
log DEBUG "Validating configuration parameters"
if [[ -z "$IFACE" || -z "$IP_NET" || -z "$GW" || -z "$MAC" ]]; then
  log ERROR "Missing required configuration parameters"
  log DEBUG "IFACE=$IFACE, IP_NET=$IP_NET, GW=$GW, MAC=$MAC"
  exit 1
fi

# considering the server don't have multiples .yamls file
NETPLAN=$(ls /etc/netplan/ 2>/dev/null | head -n1)
if [[ -z "$NETPLAN" ]]; then
  log ERROR "No netplan configuration files found in /etc/netplan/"
  echo -e "${YELLOW}Troubleshooting tips:${NC}"
  echo -e "  • Check if netplan is installed: ${DIM}which netplan${NC}"
  echo -e "  • Verify directory exists: ${DIM}ls -la /etc/netplan/${NC}"
  echo -e "  • Create default config if needed"
  exit 1
fi

# create backup of .yaml
log INFO "Backing up current netplan config: $NETPLAN"
if ! cp /etc/netplan/$NETPLAN /etc/netplan/$NETPLAN-bak; then
  log ERROR "Failed to backup netplan configuration"
  exit 1
fi

log INFO "Creating new netplan configuration..."
log DEBUG "Bridge configuration: IFACE=$IFACE, IP=$IP_NET, GW=$GW, MAC=$MAC"

# Create temporary config file for validation
TEMP_CONFIG="/tmp/netplan-config.yaml"
cat > "$TEMP_CONFIG" <<EOF
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
  log ERROR "Generated netplan configuration has invalid YAML syntax"
  rm -f "$TEMP_CONFIG"
  exit 1
fi

log DEBUG "YAML syntax validation passed"

# Apply configuration
if cp "$TEMP_CONFIG" /etc/netplan/$NETPLAN; then
  log SUCCESS "Netplan configuration file created"
  rm -f "$TEMP_CONFIG"
  
  echo -e "${YELLOW}Applying netplan configuration...${NC}"
  if netplan apply 2>/dev/null; then
    log SUCCESS "Applied netplan configuration successfully"
  else
    log ERROR "Failed to apply netplan configuration"
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo -e "  • Check syntax: ${DIM}netplan generate --debug${NC}"
    echo -e "  • Validate config: ${DIM}netplan try${NC}"
    echo -e "  • Check logs: ${DIM}journalctl -u systemd-networkd${NC}"
    exit 1
  fi
else
  log ERROR "Failed to write netplan configuration"
  rm -f "$TEMP_CONFIG"
  exit 1
fi
}

# Hetzner netplan
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

    # Validate required variables
    log DEBUG "Validating configuration parameters"
    if [[ -z "$IFACE" || -z "$IP_NET" || -z "$GW" ]]; then
      log ERROR "Missing required configuration parameters"
      log DEBUG "IFACE=$IFACE, IP_NET=$IP_NET, GW=$GW"
      exit 1
    fi

    CON_NAME=$(nmcli -t -f NAME,DEVICE connection show | grep ":$IFACE" | cut -d: -f1)
    log INFO "Connection name: $CON_NAME"
    
    if [[ -z "$CON_NAME" ]]; then
      log ERROR "No NetworkManager connection found for interface $IFACE"
      echo -e "${YELLOW}Troubleshooting tips:${NC}"
      echo -e "  • List connections: ${DIM}nmcli connection show${NC}"
      echo -e "  • Check interface: ${DIM}nmcli device status${NC}"
      echo -e "  • Create connection manually if needed"
      exit 1
    fi

    log DEBUG "Creating bridge viifbr0"
    if ! nmcli connection add type bridge con-name viifbr0 ifname viifbr0 autoconnect yes; then
      log ERROR "Failed to create bridge connection"
      exit 1
    fi

    log DEBUG "Configuring bridge IPv4 settings"
    if ! nmcli connection modify viifbr0 ipv4.addresses "$IP_NET" ipv4.gateway "$GW" ipv4.dns '8.8.8.8' ipv4.method manual; then
      log ERROR "Failed to configure bridge IPv4 settings"
      exit 1
    fi

    log DEBUG "Configuring bridge IPv6 settings"
    if [[ -n "$IPV6_ADDR" ]]; then
      if ! nmcli connection modify viifbr0 ipv6.addresses "$IPV6_ADDR" ipv6.gateway "$IPV6_GW" ipv6.method manual ipv6.dns "2001:4860:4860::8888"; then
        log WARN "Failed to configure IPv6 settings, continuing with IPv4 only"
      fi
    else
      nmcli connection modify viifbr0 ipv6.method ignore
    fi

    log DEBUG "Binding interface $CON_NAME to bridge"
    if ! nmcli connection modify "$CON_NAME" master viifbr0; then
      log ERROR "Failed to bind interface to bridge"
      exit 1
    fi

    log DEBUG "Enabling autoconnect slaves"
    nmcli connection modify viifbr0 connection.autoconnect-slaves 1

    echo -e "${YELLOW}Bringing up bridge connections...${NC}"
    if ! nmcli connection up viifbr0; then
      log ERROR "Failed to bring up bridge viifbr0"
      exit 1
    fi

    if ! nmcli connection up "$CON_NAME"; then
      log ERROR "Failed to bring up interface connection $CON_NAME"
      exit 1
    fi

    log SUCCESS "Bridge created successfully on $ID"
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
else
  ROLLBACK_WAIT=${ROLLBACK_WAIT:-15}
fi

TEST_HOST=${TEST_HOST:-8.8.8.8}

log STEP "Starting Connectivity Test (${ROLLBACK_WAIT}s Stabilization)"
echo ""
echo -e "${YELLOW}⏳ Waiting ${ROLLBACK_WAIT} seconds for network stabilization...${NC}"

# Enhanced visual countdown with progress bar
for ((i=$ROLLBACK_WAIT; i>0; i--)); do
  progress=$(( (ROLLBACK_WAIT - i) * 100 / ROLLBACK_WAIT ))
  bar_length=30
  filled=$(( progress * bar_length / 100 ))
  empty=$(( bar_length - filled ))
  bar="[${GREEN}"$(printf '█%.0s' $(seq 1 $filled))"${GRAY}"$(printf '░%.0s' $(seq 1 $empty))"${NC}]"
  printf "\r${CYAN}Stabilizing: %s %3d%% (%2ds remaining)${NC}" "$bar" "$progress" "$i"
  sleep 1
done
printf "\r${CYAN}Stabilizing: [%s] 100%% (Complete)${NC}\n" "$(printf '█%.0s' $(seq 1 30))"

echo ""
echo -e "${YELLOW}🔍 Testing connectivity to ${CYAN}${TEST_HOST}${NC}..."

# Progressive connectivity test with multiple attempts
CONNECTION_OK=0
for attempt in {1..3}; do
  echo -n -e "${DIM}Attempt $attempt/3... ${NC}"
  if ping -W 3 -c 2 "${TEST_HOST}" >/dev/null 2>&1; then
    CONNECTION_OK=1
    echo -e "${GREEN}✓ Success${NC}"
    log SUCCESS "Connectivity test passed (attempt $attempt/3)"
    break
  else
    echo -e "${RED}✗ Failed${NC}"
    log WARN "Ping attempt $attempt/3 failed"
    if [[ $attempt -lt 3 ]]; then
      echo -e "${DIM}Retrying in 3 seconds...${NC}"
      sleep 3
    fi
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
  echo -e "${GREEN}║  Physical Interface: ${CYAN}$IFACE${NC}                ${GREEN}║${NC}"
  echo -e "${GREEN}║  IP Address: ${CYAN}$IP_NET${NC}                       ${GREEN}║${NC}"
  echo -e "${GREEN}║  Gateway: ${CYAN}$GW${NC}                              ${GREEN}║${NC}"
  [[ -n "$ISP" && "$ISP" != "private" && "$ISP" != "unknown" ]] && echo -e "${GREEN}║  Provider: ${CYAN}$ISP${NC}                                    ${GREEN}║${NC}"
  echo -e "${GREEN}║                                                        ║${NC}"
  echo -e "${GREEN}║  Status: ${GREEN}► ONLINE${NC}                             ${GREEN}║${NC}"
  echo -e "${GREEN}║                                                        ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
  log SUCCESS "Bridge viifbr0 is ready for use!"
  exit 0
fi

# if connectivity failed
log ERROR "Connectivity test failed after 3 attempts, initiating rollback"

echo ""
echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ⚠ CONNECTIVITY TEST FAILED                            ║${NC}"
echo -e "${RED}║  Rolling back to previous configuration...             ║${NC}"
echo -e "${RED}║                                                        ║${NC}"
echo -e "${RED}║  Bridge: viifbr0                                       ║${NC}"
echo -e "${RED}║  Interface: $IFACE                                     ║${NC}"
echo -e "${RED}║  Status: ${RED}► OFFLINE${NC} (Rolling back)               ${RED}║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Ubuntu restore
if [[ "$ID" == ubuntu ]]
then
  BACKUP="/etc/netplan/${NETPLAN}-bak"
  if [[ ! -f "$BACKUP" ]]
  then
    log ERROR "No backup .yaml found - cannot rollback"
    echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ❌ ROLLBACK FAILED                                    ║${NC}"
    echo -e "${RED}║  No backup configuration found                       ║${NC}"
    echo -e "${RED}║                                                        ║${NC}"
    echo -e "${RED}║  Manual intervention required:                        ║${NC}"
    echo -e "${RED}║  • Restore network config manually                     ║${NC}"
    echo -e "${RED}║  • Delete bridge: sudo ip link delete viifbr0         ║${NC}"
    echo -e "${RED}║  • Reconfigure interface: sudo netplan apply          ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
    exit 2
  fi
    echo -e "${YELLOW}Restoring backup configuration...${NC}"
    log INFO "Restoring $BACKUP → ${NETPLAN}"
    if cp --archive "$BACKUP" "/etc/netplan/${NETPLAN}"; then
      log SUCCESS "Configuration file restored"
      if netplan apply; then
        log SUCCESS "Netplan configuration applied"
        if ip link delete dev viifbr0 2>/dev/null; then
          log SUCCESS "Bridge viifbr0 removed"
        else
          log WARN "Bridge viifbr0 may not exist or couldn't be removed"
        fi
        rm -rf "$BACKUP"
        log SUCCESS "Rollback completed successfully"
      else
        log ERROR "Failed to apply netplan configuration"
      fi
    else
      log ERROR "Failed to restore backup configuration"
    fi
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠ ROLLBACK COMPLETED                                ║${NC}"
    echo -e "${YELLOW}║  Please investigate the connectivity issue           ║${NC}"
    echo -e "${YELLOW}║                                                        ║${NC}"
    echo -e "${YELLOW}║  Debug commands:                                     ║${NC}"
    echo -e "${YELLOW}║  • ip addr show                                       ║${NC}"
    echo -e "${YELLOW}║  • ip route show                                      ║${NC}"
    echo -e "${YELLOW}║  • ping -c 3 8.8.8.8                                 ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}"
    exit 2
fi 

# RHEL rollback
if [[ "$ID" == "almalinux" || "$ID" == "rocky" || "$ID" == "centos" ]]
then
  echo -e "${YELLOW}Rolling back NetworkManager configuration...${NC}"
  log INFO "Bringing down bridge viifbr0"
  nmcli connection down viifbr0
  log INFO "Removing bridge slave configuration from $CON_NAME"
  eval 'nmcli connection modify "${CON_NAME}" connection.master "" connection.slave-type ""'
  log INFO "Bringing up original interface $CON_NAME"
  nmcli connection up "${CON_NAME}"
  log INFO "Deleting bridge connection viifbr0"
  nmcli connection delete viifbr0
  log SUCCESS "Rollback completed successfully"
  echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║  ⚠ ROLLBACK COMPLETED                                ║${NC}"
  echo -e "${YELLOW}║  Please investigate the connectivity issue           ║${NC}"
  echo -e "${YELLOW}║                                                        ║${NC}"
  echo -e "${YELLOW}║  Debug commands:                                     ║${NC}"
  echo -e "${YELLOW}║  • nmcli connection show                              ║${NC}"
  echo -e "${YELLOW}║  • ip addr show                                       ║${NC}"
  echo -e "${YELLOW}║  • ping -c 3 8.8.8.8                                 ║${NC}"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}"
  exit 2
fi
