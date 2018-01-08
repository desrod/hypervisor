#!/bin/bash
# Network Setup to create LXD & Libvirt OpenVswitch Networks
# This currently supports Ubuntu-Xenial only; YMMV on other OS'es
# Requires running LXD Libvirt and OpenVSwitch components

## TO-DO List
# Add logging function
# Add Verbose/Quiet run option
# Add package/dependency install function
# Add GRE IFACE Configuration as optional function
# Add function to create local LXD Firewall/Gateway Container
# Add support for classic LXD Snap "lxd.lxc commands"
# Add support for other LXD storage configuration options during profile creation
# Add Better Error handling & Detection
# Add support for Ubuntu Core OS
# Add support for LXD+MAAS Integration
# - https://github.com/lxc/lxd/blob/master/doc/containers.md (MAAS Integration)
#
# Review & research:
# - https://github.com/yeasy/easyOVS
# Enable multi-distribution detection & setting of service unit name congruence

# Check if run as root!
if [[ "$EUID" -ne "0" ]]; then
	echo "ERROR: Must be run with root/sudo priviledges!" 
	echo "Exiting!"
	exit 1
fi
      
# Set Output Formatting Variables:
SEP_1="------------------------------------------------------------------+"
SEP_2="       |"
SEP_3="       +"

# Set Bridge-Builder Variables 
# Used unless otherwise set by flags at run-time
echo "[o00.0b]$SEP_1"
echo "$SEP_2 Setting Default Variables"
OBB_VERSION=v00.81.a
#Distribution Specific System Service Names
LXD_SERVICE="lxd.service"
OVS_SERVICE="openvswitch-switch.service"
LIBVIRT_SERVICE="libvirtd.service"
# Default Variables
DEFAULT_NETWORK_NAME="obb"
NETWORK_NAME="$DEFAULT_NETWORK_NAME"
TMP_FILE_STORE=/tmp/bridge-builder/
PURGE_NETWORK=false
SHOW_CONFIG=false
SHOW_HEALTH=false
SHOW_HELP=false
WORK_DIR=$(pwd)

# Read variables from command line
echo "$SEP_2 Enabling Command Line Options"
OPTS=`getopt -o phnsHz: --long help,name,show,health,purge: -n 'parse-options' -- "$@"`

# Fail if options are not sane
echo "$SEP_2 Checking Command Line Option Sanity"
if [ $? != 0 ] ; 
    then echo "$SEP_2 Failed parsing options ... Exiting!" >&2 ; 
        exit 1
fi

eval set -- "$OPTS"

# Parse variables
echo "$SEP_2 Parsing Command Line Options"
while true; do
    case "$1" in
        -h | --help ) SHOW_HELP=true; shift ;;
        -n | --name ) NETWORK_NAME="$3"; shift; shift ;;
        -s | --show ) SHOW_CONFIG=true; shift;;
        -H | --health ) SHOW_HEALTH=true; shift ;;
        -p | --purge ) PURGE_NETWORK="$3"; shift; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done
echo "[o00.0e]$SEP_1"

print_VARS () {
#Print option values
echo "[d00.0b]$SEP_1"
echo "       | SHOW_HELP     =  $SHOW_HELP"
echo "       | NETWORK_NAME  =  $NETWORK_NAME"
echo "       | SHOW_CONFIG   =  $SHOW_CONFIG"
echo "       | SHOW_HEALTH   =  $SHOW_HEALTH"
echo "       | PURGE_NETWORK =  $PURGE_NETWORK"
echo "       | Confirmed command line options are useable .... Continuing"
echo "[d00.0e]$SEP_1"
}

#Debug & Testing break
DBG () {
    echo "       | NOTICE: DBG Calls Enabled"
    print_VARS
#    exit 0
}
DBG

end_BUILD () {
# Confirm end of setup script 
echo "[f0e.0s]$SEP_1"
echo "$SEP_2 $NETWORK_NAME Build complete for LXD and KVM"
echo "[f0e.0e]$SEP_1"
}

config_LIBVIRT () {
# create virsh network xml & define new virsh network
echo "[f08.0s]$SEP_1"
echo "$SEP_2 Configuring Network Definitions for Libvirtd+KVM+QEMU"
# Set VIRSH Working Variables
VIRSH_XML_FILE=$NETWORK_NAME.xml 
VIRSH_XML_PATH="/var/lib/libvirt/network-config" 
VIRSH_XML_TARGET=$VIRSH_XML_PATH/$VIRSH_XML_FILE

# Create xml file path and file
echo "[f08.1r]$SEP_1"
echo "$SEP_2 Creating virsh network xml configuration file"
    mkdir -p $VIRSH_XML_PATH 
echo "$SEP_2 Creating virsh network xml directory"

# Write xml configuration
echo "[f08.2r]$SEP_1"
echo "$SEP_2 Writing configuration: 
$SEP_2       > $VIRSH_XML_PATH/$VIRSH_XML_FILE"
cat >$VIRSH_XML_TARGET <<EOF
<network>
  <name>$NETWORK_NAME</name>
  <forward mode='bridge'/>
  <bridge name='$NETWORK_NAME' />
  <virtualport type='openvswitch'/>
</network>
EOF
echo "$SEP_2 $VIRSH_XML_FILE VIRSH XML Config Written"

# Defining libvirt network $NETWORK_NAME
echo "[f08.3r]$SEP_1"
echo "$SEP_2 Creating virsh network from $VIRSH_XML_TARGET"
echo "$SEP_3
 "
    virsh net-define $VIRSH_XML_TARGET 
echo "$SEP_3"
echo "$SEP_2 Defined virsh network from $VIRSH_XML_FILE"

#Starting Libvirt network
echo "$SEP_3"
echo "[f08.4r] Starting virsh $NETWORK_NAME"
echo "$SEP_3
 "
virsh net-start $NETWORK_NAME
# Setting network to auto-start at boot
echo "$SEP_3"
echo "$SEP_2 Switching virsh $NETWORK_NAME to autostart"
echo "$SEP_3
 "
virsh net-autostart $NETWORK_NAME

echo "$SEP_3"
echo "[f08.0e] Done Configuring Libvirt $NETWORK_NAME"
}

# Create initial bridge with OVS driver & configure LXD
config_LXD () {
# Create network via LXD API
echo "[f07.0s]$SEP_1"
echo "$SEP_2 Building LXD Network \"$NETWORK_NAME\" using \"$BRIDGE_DRIVER\" driver"
echo "$SEP_3
"
lxc network create $NETWORK_NAME 
echo "
$SEP_3"
    echo "$SEP_2 Created LXD Network"

# Setup network driver type
echo "[f07.1r]$SEP_1"
lxc network set $NETWORK_NAME \
    bridge.driver $BRIDGE_DRIVER 
    echo "$SEP_2 Configured $NETWORK_NAME with $BRIDGE_DRIVER driver"

## DNS configuration Options
# define default domain name:
echo "[f07.2r]$SEP_1"
lxc network set $NETWORK_NAME \
    dns.domain $DNS_DOMAIN 
    echo "$SEP_2 Configured $NETWORK_NAME with default domain name: $DNS_DOMAIN"  
# define dns mode = set via hostname
lxc network set $NETWORK_NAME \
    dns.mode dynamic         

echo "[f07.3r] Disabling LXD IP Configuration"
# Set ipv4 address on bridge
lxc network set $NETWORK_NAME \
    ipv4.address none        
# Set ipv6 address on bridge
lxc network set $NETWORK_NAME \
    ipv6.address none        

# Configure ipv4 & ipv6 address on bridge [true/false]
echo "[f07.4r] Disabling Bridge Address"
# configure ipv4 nat setting
lxc network set $NETWORK_NAME \
    ipv4.nat $NATv4          
    echo "$SEP_2 Switching ipv4 nat to $NATv4"
# configure ipv4 nat setting
lxc network set $NETWORK_NAME \
    ipv6.nat $NATv6          
    echo "$SEP_2 Switching ipv6 nat to $NATv6"

# Configure routing on bridge [enable/disable]
echo "[f07.5r] Disabling Bridge Routing function"
# set ipv4 routing
lxc network set $NETWORK_NAME \
    ipv4.routing $ROUTEv4    
    echo "$SEP_2 Switching ipv4 routing to $DHCPv4"
# Set ipv6 routing
lxc network set $NETWORK_NAME \
    ipv6.routing $ROUTEv6    
    echo "$SEP_2 Switching ipv6 routing to $DHCPv6"

# configure dhcp on bridge 
# options: true false
echo "[f07.6r] Disabling LXD DHCP Function"
# set ipv4 dhcp
lxc network set $NETWORK_NAME \
    ipv4.dhcp $DHCPv4        
# set ipv6 dhcp
lxc network set $NETWORK_NAME \
    ipv6.dhcp $DHCPv6        

# Bridge nat+router+firewall settings
echo "[f07.7r] Disabling LXD NAT+Firewall Function"
# disable ipv4 firewall 
lxc network set $NETWORK_NAME \
    ipv4.firewall false      
# disable ipv6 firewall
lxc network set $NETWORK_NAME \
    ipv6.firewall false      

# Create associated lxd profile with default ethernet device name and storage
# path
echo "[f07.8r] Creating LXD Profile for $NETWORK_NAME"
echo "$SEP_3
"
lxc profile create $LXD_PROFILE
lxc profile device add $NETWORK_NAME $LXD_PROFILE \
    nic nictype=bridged parent=$NETWORK_NAME
lxc profile device add $LXD_PROFILE \
    root disk path=/ pool=default
echo "
$SEP_3"
echo "[f07.0e] LXD Network \"$NETWORK_NAME\" Configuration Complete"
}

check_DEFAULTS () {
echo "[f06.0s]$SEP_1"
echo "[f06.1r] Validating All LXD Configuration Variables"
DEFAULT_CHECK_CONFIRM="Are you sure you want to continue building"
if [ $NETWORK_NAME == $DEFAULT_NETWORK_NAME ]
    then
        echo "[f06.2r] WARN: Bridge Builder run with default value for OVS network configuration!"
        while true; do
            read -p "$DEFAULT_CHECK_CONFIRM $NETWORK_NAME?" yn
            case $yn in
                [Yy]* ) echo "Continuing ...." ; break;;
                [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
    done
    else 
        echo "[f06.3r]----------------------------------------------------------"
        echo "       | Preparing to configure $NETWORK_NAME"
fi
echo "[f06.0e]$SEP_1"
}

set_LXD_DEFAULTS () {
# Define default DNS domain assignment
echo "[f05.0s]$SEP_1"
echo "$SEP_2 Setting additional LXD Network and Profile Build Variables"

#DNS_DOMAIN="braincraft.io" 
#echo "Setting Default Domain Name to $DNS_DOMAIN"

# Set Working Dir for temp files such as network .xml definitions for KVM+QEMU
IFACE_CFG_DIR="/root/network/"
# Set LXD Profile name to match network name
LXD_PROFILE=$NETWORK_NAME

# Configure default LXD container interface name
LXD_ETHERNET="eth0"

# Configure DHCP function
# Valid options "true|false"
DHCPv4="false"
DHCPv6="false"

# Configure Routing function
# Valid Options "true|false" 
ROUTEv4="false"
ROUTEv6="false"
echo "[f05.0e]$SEP_1"
}

BUILD () {
# Core Bridge Builder Feature
# This function calls the child functions which build the bridge and configure
# client services such as LXD and KVM+QEMU (virsh) for use with OVS
echo "[f04.0s]$SEP_1"
echo "[f04.1r]$SEP_2 > Checking System Readiness"
check_SERVICE_HEALTH
echo "[f04.2r]$SEP_2 > Setting LXD Default Variables"
set_LXD_DEFAULTS
echo "[f04.3r]$SEP_2 > Checking LXD Variables"
check_DEFAULTS
echo "[f04.4r]$SEP_2 > purging any pre-existing $NETWORK_NAME configuration"
purge_NETWORK
echo "[f04.5r]$SEP_2 > Starting LXD Configuration"
config_LXD

config_LIBVIRT
show_CONFIG
echo "[f04.0s]$SEP_1"
}

purge_NETWORK () {
# Purge any conflicting networks ) --purge | -p
echo "[f03.0s]$SEP_1"
echo "[f03.1r] Purging $PURGE_NETWORK from  LXD Network and Profile configuration"
    lxc network delete $PURGE_NETWORK > /dev/null 2>&1 ;
    lxc profile delete $LXD_PROFILE > /dev/null 2>&1 
echo "$SEP_2  > Purged $PURGE_NETWORK from LXD configuration"
echo "[f03.2r] Purging $PURGE_NETWORK from Libvirt Network Configuration"
    virsh net-undefine $PURGE_NETWORK > /dev/null 2>&1 ;
    virsh net-destroy $PURGE_NETWORK > /dev/null 2>&1 ;
echo "$SEP_2  > Purged $PURGE_NETWORK from Libvirt configuration"
echo "[f03.3r] Purging OpenVswitch Configuration"
    ovs-vsctl del-br $PURGE_NETWORK > /dev/null 2>&1  ;
echo "$SEP_2  > Purged $PURGE_NETWORK from OpenVswitch configuration"
echo "$SEP_2 Finished Purging $PURGE_NETWORK from system"
echo "[f03.0e]$SEP_1"
}

check_SERVICE_HEALTH () {
# Confirm OVS/LXD/Libvirtd services are all running ) --health | -H
echo "[f02.0s]$SEP_1"
echo "$SEP_2 Checking service health"
LXD_STATUS=$(systemctl is-active $LXD_SERVICE)
LXD_ENABLED=$(systemctl is-enabled $LXD_SERVICE)
echo "[f02.1r]$SEP_1"
echo "$SEP_2 LXD Daemon is $LXD_STATUS & $LXD_ENABLED"
    if [ $LXD_STATUS != "active" ] && [ $LXD_ENABLED != "enabled" ]
    then
        echo "$SEP_2 LXD Service is not running or enabled persistently"
        echo "$SEP_2 Install/Enable and initialize LXD service or check configuration and try again"
        exit 0
    else
        echo "$SEP_2 LXD Service is READY"
    fi
echo "[f02.2r]$SEP_1"
LIBVIRT_STATUS=$(systemctl is-active $LIBVIRT_SERVICE)
LIBVIRT_ENABLED=$(systemctl is-enabled $LIBVIRT_SERVICE)
echo "$SEP_2 Libvirt Daemon is $LIBVIRT_STATUS & $LIBVIRT_ENABLED"
    if [ $LIBVIRT_STATUS != "active" ] && [ $LIBVIRT_ENABLED != "enabled" ]
    then
        echo "$SEP_2 Libvirtd Service is not running or enabled persistently"
        echo "$SEP_2 Install/Enable Libvirtd service or check configuration and try again"
        exit 0
    else
        echo "$SEP_2 Libvirtd Service is READY"
    fi
echo "[f02.3r]$SEP_1"
OVS_STATUS=$(systemctl is-active $OVS_SERVICE)
OVS_ENABLED=$(systemctl is-enabled $OVS_SERVICE)
echo "$SEP_2 OVS Daemon is $OVS_STATUS & $OVS_ENABLED"
    if [ $OVS_STATUS != "active" ] && [ $OVS_ENABLED != "enabled" ]
    then
        echo "$SEP_2 OVS Service is not running or enabled persistently"
        echo "$SEP_2 Install/Enable OpenVswitch or check configuration and try again"
        exit 0
    else
        echo "$SEP_2 OVS Service is READY"
    fi
echo "[f02.0e]$SEP_1"
}

show_CONFIG () {
# Show current networks configured for OVS/LXD/KVM+QEMU ) --show | -s
echo "[f01.0s]$SEP_1"
echo "$SEP_2 Showing Local Bridge Configuration"
echo "[f01.0s]$SEP_1"
echo "$SEP_2"
#Checking System Service Status
OVS_SERVICE_STATUS=$(systemctl is-active $OVS_SERVICE)
LXD_SERVICE_STATUS=$(systemctl is-active $LXD_SERVICE)
LIBVIRT_SERVICE_STATUS=$(systemctl is-active $LIBVIRT_SERVICE)
# List Openvswitch Networks
echo "$SEP_2         $OVS_SERVICE = $OVS_SERVICE_STATUS"
echo "$SEP_2                        $LXD_SERVICE = $LXD_SERVICE_STATUS"
echo "$SEP_2                   $LIBVIRT_SERVICE = $LIBVIRT_SERVICE_STATUS"
echo "$SEP_2"
echo "$SEP_3
 "
if [ "$OVS_SERVICE_STATUS" = active ]
    then
        echo "[f01.1r] > OpenVSwitch Configuration <"
        echo "$SEP_3
        "
        ovs-vsctl show
        echo "
$SEP_3"
    else
        echo "$SEP_2 ERROR: The OpenVSwitch System Service IS NOT RUNNING"
fi
# List LXD Networks
if [ "$LXD_SERVICE_STATUS" = "active" ]
    then
        echo "[f01.2r] > LXD Networks List <"
echo "$SEP_3
        "
        lxc network list
        echo "
$SEP_3"
    else
        echo "$SEP_2 ERROR: The LXD System Service IS NOT RUNNING"
fi
# List LibVirtD Networks
if [ "$LIBVIRT_SERVICE_STATUS" = "active" ]
    then
        echo "[f01.3r] > LibVirtD Network Configuration < "
        echo "$SEP_3
        "
        virsh net-list --all
        echo "
$SEP_3"
    else
        echo "$SEP_2 ERROR: The LibVirtD System Service IS NOT RUNNING"
fi
echo "[f01.0e]$SEP_1"
}

show_HELP () {
    # Show Help menu ) --help | -h
    echo "[f0h.0s]$SEP_1"
    echo "$SEP_3"
    echo "
    syntax:
       command [option] [value]

    This tool will create a new OVS bridge.
    By default, this bridge will be ready for use with each of the following:

       LXD:
        \_______       
                \_Launch a container with the \"lxd profile\" flag to attach
                |    Example:                                               
                |      lxc launch ubuntu: test-container -p \$NETWORK_NAME 

       Libvirt Guests:
        \_______
                \_Attach Libvirt / QEMU / KVM guests:
                |   Example:
                |     virt-manager nic configuration
                |     virsh xml configuration

       Physical Ports:
        \_______
                \_Attach Physical Ports via the following
                |   Example with physical device name "eth0"
                |      ovs-vsctl add-port $NETWORK_NAME eth0

    Options:
       --help            -h    --    Print this help menu
       --health-check    -H    --    Check OVS|LXD|Libvirtd Service Status
       --show-config     -c    --    Show current networks configured locally
       --purge           -p    --    Purges network when pased with a value
                                     matching an existing network name.
       --name            -n    --    Sets the name for building the following: 
                                        OVS Bridge
                                        Libvirt Bridge
                                        LXD Network & Profile Name
    "
    echo "$SEP_3"
    echo "[f0h.0e]$SEP_1"
}

RUN () {
# Initial function that determines behavior from command line flags
if [ $SHOW_HELP != 'false' ]
then
    echo "[f0h.0o]<"
        show_HELP
        echo "$SEP_2 OVS_BridgeBuilder_VERSION = $OBB_VERSION"
        echo "[f0h.0c]$SEP_1"
    exit 0
fi
if [ $SHOW_CONFIG != 'false' ]
then
    echo "[f01.0o]<"
        show_CONFIG
    echo "[f01.0c]$SEP_1"
    exit 0
fi
if [ $SHOW_HEALTH != 'false' ]
then
    echo "[f02.0o]<"
        check_SERVICE_HEALTH
        echo "[q00.3c]$SEP_1"
    exit 0
fi
if [ $PURGE_NETWORK != 'false' ]
then
    echo "[f03.0o]<"
    echo "$SEP_2 Purging $PURGE_NETWORK ..."
        purge_NETWORK
        show_CONFIG
        echo "$SEP_2 Removed $PURGE_NETWORK"
    echo "[f03.0c]$SEP_1"
    exit 0
fi
  if [ $SHOW_HELP == 'false' ]     && \
     [ $SHOW_CONFIG == 'false' ]   && \
     [ $SHOW_HEALTH == 'false' ]   && \
     [ $PURGE_NETWORK == 'false' ]
then
    echo "[f04.0o]<"
        BUILD
    echo "[f04.1r]<"
        end_BUILD
    echo "[f04.0c]"
    exit 0
else
    echo "$SEP_2 ERROR: Unable to parse comand line options .. EXITING!"
    exit 0
fi
}

# Start initial function that determines behavior from command line flags
RUN
