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
	[[ "$ID" =~ ^(almalinux|rocky|centos)$ ]]
}

# checking if the script runs as root
if [[ $EUID -ne 0 ]]
then
	echo -e "${RED}--- The scipt must be run as root ---${NC} "
	exit 1
fi

# Detect Network Interface and IP netmask and gateway
IFACE=$(ip route show default | awk '{print $5}')

if [[ "$IFACE" == "viifbr0" ]]
then
	echo -e "${BLUE}--- The bridge interface is already UP/online ---"
	exit 1
fi

echo -e "${CYAN} Defualt Interface: $IFACE"

IP_NET=$(ip -4 addr show $IFACE | grep inet | grep -v '127.0.0.1' | awk '{print $2}')  # this commmand retrive IP/prefix 

IP=$(ip -4 addr show $IFACE | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1) # only IP

GW=$(ip route show default | awk '{print $3}')


# IPv6 check
echo -e "${CYAN}${BOLD} gathering IPv6 "
IPV6_ADDR=""
IPV6_GW=""

IPV6=$(ip -6 addr show dev $IFACE scope global | grep -w inet6  | awk '{print $2}')
if [[ -n "$IPV6" ]]
then
	IPV6_ADDR=$IPV6
	IPV6_GW=$(ip -6 route | awk '/default via/ {print $3; exit}')
	echo -e "${BLUE} IPv6 address: $IPV"
	echo -e "${BLUE} IPV6 gateway: $IPV_GW"
else
	echo -e "${YELLOW} IPv6 is not found. "
fi


# INstall ipcalc command
echo -e "${BLUE}--- check if ipcalc is installed ---${NC}"
if ! command -v ipcalc >/dev/null; then
	echo -e "${GRAY} ipcalc is not installed "

	# Install ipcalc
	if is_ubuntu
	then
		echo -e "${YELLOW} Installing ipcalc.... ${NC}"
		if apt-get update -y && apt-get install ipcalc -y >/dev/null 2>&1; then
			echo -e "${GREEN} ipcalc is installed "
		else
			echo -e "${RED} Failed to install ipcalc! ${NC}"
			echo -e "${YELLOW}Manual installation required:${NC}"
			echo -e "  ${DIM}sudo apt-get update && sudo apt-get install ipcalc${NC}"
			exit 1
		fi
	elif is_rhel_basedos
	then
		echo -e "${YELLOW}Installing ipcalc...${NC}"
		if dnf install ipcalc >/dev/null 2>&1; then
			echo -e "${GREEN} ipcalc has installed ${NC}"
		else
			echo -e "${RED} Failed to install ipcalc ${NIC}"
			echo -e "${YELLOW}Manual installation required:${NC}"
			echo -e "  ${DIM}sudo dnf install ipcalc${NC}"
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
echo -e "${CYAN} $PROVIDER: "



# Hetzner netmask
if [[ $PROVIDER == "hetzner" ]]
then
	echo -e "${CYAN}${BOLD} Hetzner configuration required "
	echo -e "${YELLOW}Hetzner servers require manual netmask configuration.${NC}"
	echo -e "${DIM}Please find the correct netmask in your Hetzner Cloud Console.${NC}"

	while true; do
		echo -n -e "${CYAN}Enter netmask (e.g., 255.255.255.0): ${NC}"
		read -r NETMASK
	if [[ "$NETMASK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
	then
		CIDR=$(ipcalc $IP $NETMASK | awk '/Netmask/ {print $4}')
		if [[ $? -eq 0 && -n "$CIDR" ]]
		then
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
  echo -e  "${RED} Generated netplan configuration has invalid YAML syntax"
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

}

hetzner() {
echo -e "${CYAN}${BOLD} Starting Ubuntu bridge with Netplan..."
BACKUP
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
  echo -e  "${RED} Generated netplan configuration has invalid YAML syntax"
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
}

ovh() {
echo -e "${CYAN}${BOLD} Starting Ubuntu bridge with Netplan..."
BACKUP
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
  echo -e  "${RED} Generated netplan configuration has invalid YAML syntax"
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
}


