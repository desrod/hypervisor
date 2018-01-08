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
sep_1="------------------------------------------------------------------+"
sep_2="       |"
sep_3="       +"

# Set Bridge-Builder Variables 
# Used unless otherwise set by flags at run-time
echo "[o00.0b]$sep_1"
echo "$sep_2 Setting Default Variables"
obb_version=v00.81.a
#Distribution Specific System Service Names
lxd_service="lxd.service"
ovs_service="openvswitch-switch.service"
libvirt_service="libvirtd.service"
# Default Variables
default_network_name="obb"
network_name="$default_network_name"
tmp_file_store=/tmp/bridge-builder/
bridge_driver="openvswitch"
purge_network=false
show_config=false
show_health=false
show_help=false
work_dir=$(pwd)

# Read variables from command line
echo "$sep_2 Enabling Command Line Options"
OPTS=$(getopt -o phnsHz: --long help,name,show,health,purge: -n 'parse-options' -- "$@")

# Fail if options are not sane
echo "$sep_2 Checking Command Line Option Sanity"
if [ $? != 0 ] ; 
    then echo "$sep_2 Failed parsing options ... Exiting!" >&2 ; 
        exit 1
fi

eval set -- "$OPTS"

# Parse variables
echo "$sep_2 Parsing Command Line Options"
while true; do
    case "$1" in
        -h | --help ) show_help=true; shift ;;
        -n | --name ) network_name="$3"; shift; shift ;;
        -s | --show ) show_config=true; shift;;
        -H | --health ) show_health=true; shift ;;
        -p | --purge ) purge_network="$3"; shift; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done
echo "[o00.0e]$sep_1"


######################################################################
print_vars () {
#Print option values
echo "[d00.0b]$sep_1"
echo "       | SHOW_HELP     =  $show_help"
echo "       | NETWORK_NAME  =  $network_name"
echo "       | SHOW_CONFIG   =  $show_config"
echo "       | SHOW_HEALTH   =  $show_health"
echo "       | PURGE_NETWORK =  $purge_network"
echo "       | Confirmed command line options are useable .... Continuing"
echo "[d00.0e]$sep_1"
}

#Debug & Testing break
DBG () {
    echo "       | NOTICE: DBG Calls Enabled"
    print_vars
#    exit 0
}
DBG


######################################################################
end_build () {
# Confirm end of setup script 
echo "[f0e.0s]$sep_1"
echo "$sep_2 $network_name Build complete for LXD and KVM"
echo "[f0e.0e]$sep_1"
}


######################################################################
config_libvirt () {
# create virsh network xml & define new virsh network
echo "[f08.0s]$sep_1"
echo "$sep_2 Configuring Network Definitions for Libvirtd+KVM+QEMU"
# Set VIRSH Working Variables
virsh_xml_file=$network_name.xml 
virsh_xml_path="/var/lib/libvirt/network-config" 
virsh_xml_target=$virsh_xml_path/$virsh_xml_file

# Create xml file path and file
echo "[f08.1r]$sep_1"
echo "$sep_2 Creating virsh network xml configuration file"
    mkdir -p $virsh_xml_path 
echo "$sep_2 Creating virsh network xml directory"

# Write xml configuration
echo "[f08.2r]$sep_1"
echo "$sep_2 Writing configuration: 
$sep_2       > $virsh_xml_path/$virsh_xml_file"
cat > "$virsh_xml_target" <<EOF
<network>
  <name>$network_name</name>
  <forward mode='bridge'/>
  <bridge name='$network_name' />
  <virtualport type='openvswitch'/>
</network>
EOF
echo "$sep_2 $virsh_xml_file VIRSH XML Config Written"

# Defining libvirt network $network_name
echo "[f08.3r]$sep_1"
echo "$sep_2 Creating virsh network from $virsh_xml_target"
echo "$sep_3"
    virsh net-define "$virsh_xml_target"
echo "$sep_3"
echo "$sep_2 > Defined virsh network from $virsh_xml_file"

#Starting Libvirt network
echo "$sep_3"
echo "[f08.4r] Starting virsh $network_name"
echo "$sep_3
 "
virsh net-start "$network_name"
# Setting network to auto-start at boot
echo "$sep_3"
echo "$sep_2 Switching virsh $network_name to autostart"
echo "$sep_3
 "
virsh net-autostart "$network_name"

echo "$sep_3"
echo "[f08.0e] Done Configuring Libvirt $network_name"
}


######################################################################
# Create initial bridge with OVS driver & configure LXD
config_lxd () {
# Create network via LXD API
echo "[f07.0s]$sep_1"
echo "$sep_2 Building LXD Network \"$network_name\" using \"$bridge_driver\" driver"
echo "$sep_3
"
lxc network create "$network_name"
echo "
$sep_3"
    echo "$sep_2 Created LXD Network $network_name"

# Setup network driver type
echo "[f07.1r]$sep_1"
lxc network set "$network_name" \
    bridge.driver $bridge_driver 
    echo "$sep_2 Configured $network_name with $bridge_driver driver"

## DNS configuration Options
# define default domain name:
#echo "[f07.2r]$sep_1"
#lxc network set "$network_name" \
#    dns.domain $DNS_DOMAIN 
#    echo "$sep_2 Configured "$network_name" with default domain name: $DNS_DOMAIN"  
# define dns mode = set via hostname
#lxc network set "$network_name" \
#    dns.mode dynamic         

echo "[f07.3r] Disabling LXD IP Configuration"
# Set ipv4 address on bridge
lxc network set "$network_name" \
    ipv4.address none        
# Set ipv6 address on bridge
lxc network set "$network_name" \
    ipv6.address none        

# Configure ipv4 & ipv6 address on bridge [true/false]
#echo "[f07.4r] Disabling Bridge Address"
# configure ipv4 nat setting
#lxc network set "$network_name" \
#    ipv4.nat $NATv4          
#    echo "$sep_2 Switching ipv4 nat to $NATv4"
# configure ipv4 nat setting
#lxc network set "$network_name" \
#    ipv6.nat $NATv6          
#    echo "$sep_2 Switching ipv6 nat to $NATv6"

# Configure routing on bridge [enable/disable]
echo "[f07.5r] Disabling Bridge Routing function"
# set ipv4 routing
#lxc network set "$network_name" \
#    ipv4.routing $ROUTEv4    
#    echo "$sep_2 Switching ipv4 routing to $DHCPv4"
# Set ipv6 routing
#lxc network set "$network_name" \
#    ipv6.routing $ROUTEv6    
#    echo "$sep_2 Switching ipv6 routing to $DHCPv6"

# configure dhcp on bridge 
# options: true false
echo "[f07.6r] Disabling LXD DHCP Function"
# set ipv4 dhcp
lxc network set "$network_name" \
    ipv4.dhcp "$DHCPv4"
# set ipv6 dhcp
lxc network set "$network_name" \
    ipv6.dhcp "$DHCPv6"

# Bridge nat+router+firewall settings
echo "[f07.7r] Disabling LXD NAT+Firewall Function"
# disable ipv4 firewall 
lxc network set "$network_name" \
    ipv4.firewall false      
# disable ipv6 firewall
lxc network set "$network_name" \
    ipv6.firewall false      

# Create associated lxd profile with default ethernet device name and storage
# path
echo "[f07.8r] Creating LXD Profile for $network_name"
echo "$sep_3
"
lxc profile create "$lxd_profile"
lxc profile device add "$network_name" "$lxd_profile" \
    nic nictype=bridged parent="$network_name"
lxc profile device add "$lxd_profile" \
    root disk path=/ pool=default
echo "
$sep_3"
echo "[f07.0e] LXD Network \"$network_name\" Configuration Complete"
}


######################################################################
check_defaults () {
echo "[f06.0s]$sep_1"
echo "[f06.1r] Validating All LXD Configuration Variables"
default_check_confirm="Are you sure you want to continue building"
if [ "$network_name" == $default_network_name ]
    then
        echo "[f06.2r] WARN: Bridge Builder run with default value for OVS network configuration!"
        while true; do
            read -p "$default_check_confirm $network_name?" yn
            case $yn in
                [Yy]* ) echo "Continuing ...." ; break;;
                [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
    done
    else 
        echo "[f06.3r]----------------------------------------------------------"
        echo "       | Preparing to configure $network_name"
fi
echo "[f06.0e]$sep_1"
}


######################################################################
set_lxd_defaults () {
# Define default DNS domain assignment
echo "[f05.0s]$sep_1"
echo "$sep_2 Setting additional LXD Network and Profile Build Variables"

#DNS_DOMAIN="braincraft.io" 
#echo "Setting Default Domain Name to $DNS_DOMAIN"

# Set Working Dir for temp files such as network .xml definitions for KVM+QEMU
iface_cfg_dir="/root/network/"
# Set LXD Profile name to match network name
lxd_profile=$network_name

# Configure default LXD container interface name
lxd_ethernet="eth0"

# Configure DHCP function
# Valid options "true|false"
DHCPv4="false"
DHCPv6="false"

# Configure Routing function
# Valid Options "true|false" 
ROUTEv4="false"
ROUTEv6="false"
echo "[f05.0e]$sep_1"
}


######################################################################
build () {
# Core Bridge Builder Feature
# This function calls the child functions which build the bridge and configure
# client services such as LXD and KVM+QEMU (virsh) for use with OVS
echo "[f04.0s]$sep_1"
echo "[f04.1r] > Checking System Readiness"
check_service_health
echo "[f04.2r]$sep_2 > Setting LXD Default Variables"
set_lxd_defaults
echo "[f04.3r]$sep_2 > Checking LXD Variables"
check_defaults
echo "[f04.4r]$sep_2 > purging any pre-existing $network_name configuration"
purge_network
echo "[f04.5r]$sep_2 > Starting LXD Configuration"
config_LXD

config_libvirt
show_config
echo "[f04.0s]$sep_1"
}


######################################################################
purge_network () {
# Purge any conflicting networks ) --purge | -p
if [ "$purge_network" = "false" ]
then
    purge_network=$network_name
fi
echo "[f03.0s]$sep_1"
echo "[f03.1r] Purging $purge_network from  LXD Network and Profile configuration"
    lxc network delete "$purge_network" > /dev/null 2>&1 ;
    lxc profile delete "$lxd_profile" > /dev/null 2>&1 
echo "$sep_2  > Purged $purge_network from LXD configuration"
echo "[f03.2r] Purging $purge_network from Libvirt Network Configuration"
    virsh net-undefine "$purge_network" > /dev/null 2>&1 ;
    virsh net-destroy "$purge_network" > /dev/null 2>&1 ;
echo "$sep_2  > Purged $purge_network from Libvirt configuration"
echo "[f03.3r] Purging OpenVswitch Configuration"
    ovs-vsctl del-br "$purge_network" > /dev/null 2>&1  ;
echo "$sep_2  > Purged $purge_network from OpenVswitch configuration"
echo "$sep_2 Finished Purging $purge_network from system"
echo "[f03.0e]$sep_1"
}


######################################################################
check_service_health () {
# Confirm OVS/LXD/Libvirtd services are all running ) --health | -H
echo "[f02.0s]$sep_1"
echo "$sep_2 Checking service health"
lxd_status=$(systemctl is-active $lxd_service)
lxd_enabled=$(systemctl is-enabled $lxd_service)
    if [ "$lxd_status" != "active" ] 
    then
        echo "$sep_2 $lxd_service does not appear to be running"
        echo "$sep_2 Starting $lxd_service "
        systemctl start $lxd_service
        lxd_status=$(systemctl is-active $lxd_service)
    fi
    if [ "$lxd_enabled" != "enabled" ] && [ "$lxd_enabled" != "indirect" ] 
    then
        echo "$sep_2 $lxd_service does not appear to be enabled"
        echo "$sep_2 Enabling $lxd_service"
        systemctl enable $lxd_service
        lxd_enabled=$(systemctl is-enabled $lxd_service)
    fi
echo "[f02.1r]$sep_1"
echo "$sep_2 LXD Daemon is $lxd_status & $lxd_enabled"
    if [ "$lxd_status" != "active" ] && [ "$lxd_enabled" != "enabled" ]
    then
        echo "$sep_2 LXD Service is not running or enabled persistently"
        echo "$sep_2 Install/Enable and initialize LXD service or check configuration and try again"
        exit 0
    else
        echo "$sep_2 LXD Service is READY"
    fi
echo "[f02.2r]$sep_1"
libvirt_status=$(systemctl is-active $libvirt_service)
libvirt_enabled=$(systemctl is-enabled $libvirt_service)
    if [ "$libvirt_status" != "active" ]
    then
        systemctl start $libvirt_service
        libvirt_status=$(systemctl is-active $libvirt_service)
    fi
    if [ "$libvirt_enabled" != "enabled" ]
    then
        systemctl start $libvirt_service
        libvirt_enabled=$(systemctl is-active $libvirt_service)
    fi
echo "$sep_2 Libvirt Daemon is $libvirt_status & $libvirt_enabled"
    if [ "$libvirt_status" != "active" ] && [ "$libvirt_enabled" != "enabled" ]
    then
        echo "$sep_2 Libvirtd Service is not running or enabled persistently"
        echo "$sep_2 Install/Enable Libvirtd service or check configuration and try again"
        exit 0
    else
        echo "$sep_2 Libvirtd Service is READY"
    fi
echo "[f02.3r]$sep_1"
ovs_status=$(systemctl is-active $ovs_service)
ovs_enabled=$(systemctl is-enabled $ovs_service)
    if [ "$ovs_status" != "active" ] 
    then
        systemctl start $ovs_service
        ovs_status=$(systemctl is-active $ovs_service)
    fi
    if [ "$ovs_enabled" != "enabled" ]
    then
        systemctl enable $ovs_service
        ovs_enabled=$(systemctl is-enabled $ovs_service)
    fi
echo "$sep_2 OVS Daemon is $ovs_status & $ovs_enabled"
    if [ "$ovs_status" != "active" ] && [ "$ovs_enabled" != "enabled" ]
    then
        echo "$sep_2 OVS Service is not running or enabled persistently"
        echo "$sep_2 Install/Enable OpenVswitch or check configuration and try again"
        exit 0
    else
        echo "$sep_2 OVS Service is READY"
    fi
echo "[f02.0e]$sep_1"
}


######################################################################
show_config () {
# Show current networks configured for OVS/LXD/KVM+QEMU ) --show | -s
echo "[f01.0s]$sep_1"
echo "$sep_2 Showing Local Bridge Configuration"
echo "[f01.0s]$sep_1"
echo "$sep_2"
#Checking System Service Status
ovs_service_status=$(systemctl is-active $ovs_service)
lxd_service_status=$(systemctl is-active $lxd_service)
libvirt_service_status=$(systemctl is-active $libvirt_service)
# List Openvswitch Networks
echo "$sep_2         $ovs_service = $ovs_service_status"
echo "$sep_2                        $lxd_service = $lxd_service_status"
echo "$sep_2                   $libvirt_service = $libvirt_service_status"
echo "$sep_2"
echo "$sep_3
 "
if [ "$ovs_service_status" = active ]
    then
        echo "[f01.1r] > OpenVSwitch Configuration <"
        echo "$sep_3
        "
        ovs-vsctl show
        echo "
$sep_3"
    else
        echo "$sep_2 ERROR: The OpenVSwitch System Service IS NOT RUNNING"
fi
# List LXD Networks
if [ "$lxd_service_status" = "active" ]
    then
        echo "[f01.2r] > LXD Networks List <"
echo "$sep_3
        "
        lxc network list
        echo "
$sep_3"
    else
        echo "$sep_2 ERROR: The LXD System Service IS NOT RUNNING"
fi
# List LibVirtD Networks
if [ "$libvirt_service_status" = "active" ]
    then
        echo "[f01.3r] > LibVirtD Network Configuration < "
        echo "$sep_3
        "
        virsh net-list --all
        echo "
$sep_3"
    else
        echo "$sep_2 ERROR: The LibVirtD System Service IS NOT RUNNING"
fi
echo "[f01.0e]$sep_1"
}


######################################################################
show_help () {
    # Show Help menu ) --help | -h
    echo "[f0h.0s]$sep_1"
    echo "$sep_3"
    echo "
    syntax:
       command [option] [value]

    This tool will create a new OVS bridge.
    By default, this bridge will be ready for use with each of the following:

       LXD:
        \_______       
                \_Launch a container with the \"lxd profile\" flag to attach
                |    Example:                                               
                |      lxc launch ubuntu: test-container -p \$network_name 

       Libvirt Guests:
        \_______
                \_Attach Libvirt / QEMU / KVM guests:
                |   Example:
                |     virt-manager nic configuration
                |     virsh xml configuration

       Physical Ports:
        \_______
                \_Attach Physical Ports via the following
                |   Example with physical device name eth0
                |      ovs-vsctl add-port $network_name eth0

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
    echo "$sep_3"
    echo "[f0h.0e]$sep_1"
}


######################################################################
run () {
# Initial function that determines behavior from command line flags
if [ $show_help != 'false' ]
then
    echo "[f0h.0o]<"
        show_help
        echo "$sep_2 OVS_BridgeBuilder_VERSION = $obb_version"
        echo "[f0h.0c]$sep_1"
    exit 0
fi
if [ $show_config != 'false' ]
then
    echo "[f01.0o]<"
        show_config
    echo "[f01.0c]$sep_1"
    exit 0
fi
if [ $show_health != 'false' ]
then
    echo "[f02.0o]<"
        check_service_health
        echo "[q00.3c]$sep_1"
    exit 0
fi
if [ "$purge_network" != 'false' ]
then
    echo "[f03.0o]<"
    echo "$sep_2 Purging $purge_network ..."
        purge_network
        show_config
        echo "$sep_2 Removed $purge_network"
    echo "[f03.0c]$sep_1"
    exit 0
fi
  if [ $show_help == 'false' ]     && \
     [ $show_config == 'false' ]   && \
     [ $show_health == 'false' ]   && \
     [ "$purge_network" == 'false' ]
then
    echo "[f04.0o]<"
        build
    echo "[f04.1r]<"
        end_build
    echo "[f04.0c]"
    exit 0
else
    echo "$sep_2 ERROR: Unable to parse comand line options .. EXITING!"
    exit 0
fi
}

# Start initial function that determines behavior from command line flags
run
