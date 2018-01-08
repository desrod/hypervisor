#!/bin/sh
#
## By ContainerCraft.io (CCIO|ccio) 
# This function will:
# -- Install LXD from PPA
# -- Install Libvirt+KVM+QEMU
# -- Install OpenVSwitch (dpdk)
#
## ToDo:
# Add option to choose LXD install from PPA or SNAP
# Cleanup LXD Init function to handle pre-existing zfs volumes more gracefully
# Add ability to pass variables via yaml *(1) *(2) *(3) 
# Add ability to turn component install on and off with flags at command line:
# Add docker host installation either as a guest vm or natively (research required)
# Create preseed helper tui
# Finish libvirt logical EFI enablement on properly equipped systems if EFI vars are detected
# - /sys/firmware/efi/efivars
#   Eg: $ ccio --hypervisor-install --[lxd-snap|lxd-ppa] --kvm-qemu --[openvswitch|openvswitch-dpdk] 
#
## Add support for `lxd init` yaml config as follows for CCIO supported values: 
# Do you want to configure a new storage pool (yes/no) [default=yes]? yes
# Name of the new storage pool [default=default]: default
# Name of the storage backend to use (dir, lvm, zfs) [default=zfs]: zfs
# Create a new ZFS pool (yes/no) [default=yes]? yes
# Would you like to use an existing block device (yes/no) [default=no]? no
# Size in GB of the new loop device (1GB minimum) [default=100GB]: 64
# Would you like LXD to be available over the network (yes/no) [default=no]? yes
# Address to bind LXD to (not including port) [default=all]:  all
# Port to bind LXD to [default=8443]: 8443
# Trust password for new clients:    
# Again:                             
# Would you like stale cached images to be updated automatically (yes/no) [default=yes]? yes
# Would you like to create a new network bridge (yes/no) [default=yes]? no       

# Refrences: 
# https://software.intel.com/en-us/articles/set-up-open-vswitch-with-dpdk-on-ubuntu-server
# http://dpdk.org/doc/guides/linux_gsg/sys_reqs.html#running-dpdk-applications
# https://help.ubuntu.com/community/JeOSVMBuilder
# https://www.ibm.com/support/knowledgecenter/en/linuxonibm/liaat/liaatvirtinstalloptions.htm
# https://ubuntu-smoser.blogspot.co.uk/2013/02/using-ubuntu-cloud-images-without-cloud.html
# https://dshcherb.github.io/2017/12/04/qemu-kvm-virtual-machines-in-unprivileged-lxd.html
# https://github.com/dillonhafer/wiki/wiki/KVM
#  (1) https://medium.com/@frontman/how-to-parse-yaml-string-via-command-line-374567512303
#  (2) https://gist.github.com/pkuczynski/8665367
#  (3) https://github.com/0k/shyaml
#-------------------------------------------------------------------------------------------

# formatting values
SEP_2="       |"

# Check if run as root!
if [[ $EUID -ne 0 ]]; then
        echo "$SEP_2 This script must be run as root!"
	echo "$SEP_2 Exiting ... " 
        exit 1
fi

apt_UPDATE () {
# System update sub-routine called when required
apt update 
apt upgrade -y 
apt dist-upgrade -y 
apt autoremove -y
}

configure_LIBVIRT () {
echo "[f26.0s] Configuring host Libvirt Hypervisor"
echo "$SEP_2 WARNING! All automated Libvirt configuration currently disabled!!!"
virt-host-validate
# Allow running libvirt commands as user without passwd
# gpasswd libvirtd -a <username>
#
# Enable pci-passthrough on bare metal
# /etc/modules
# pci_stub  
# vfio  
# vfio_iommu_type1  
# vfio_pci  
# vfio_virqfd  
# kvm  
# kvm_intel  
# 
# Enable IOMMU at grub cmdline
# /etc/default/grub
# sed find replace
# line: GRUB_CMDLINE_LINUX_DEFAULT
# s/quiet splash/intel_iommu=on/g
# 
# intelligent kvm nested enablement
# Only enable if bare metal
# Only enable if following command output != Y
# cat /sys/module/kvm_intel/parameters/nested
# then: echo 'options kvm_intel nested=1' >> \
#	/etc/modprobe.d/qemu-system-x86.conf
# if intel then
# /etc/default/grub
# s/quiet splash/kvm-intel.nested=1/g
#
# grub-update
# double check against:
# https://computingforgeeks.com/complete-installation-of-kvmqemu-and-virt-manager-on-arch-linux-and-manjaro/
# https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF
# https://wiki.archlinux.org/index.php/KVM
echo "$SEP_2 Done"
}

install_LIBVIRT () {
# install Libvirt | KVM | QEMU packages
echo "[f25.0s] Installing Libvirt packages"
LIBVIRT_PKGS="qemu \
	     qemu-kvm \
	     qemu-utils \
	     libvirt0 \
	     libvirt-bin \
	     virtinst"
EFI_PKGS="qemu-efi \
          ovmf"
       apt install -y $LIBVIRT_PKGS #$EFI_PKGS
echo "$SEP_2 Installed LibvirtD + KVM + QEMU Requirements!"
echo "$SEP_2 Done"
}

configure_LXD () {
# Configure LXD for first time use
echo "[f24.0s] Preping host for LXD configuration"
ZPOOL_NAME=default
ZPOOL_TYPE=zfs
echo "[f24.1r] CCIO_Setup is about to purge any zfs pools and lxd storage"
echo "$SEP_2 matching the name $ZPOOL_NAME"
echo "$SEP_2 Listing all matching pools between the following brackets"
echo "       \{"
    zpool list $ZPOOL_NAME
    lxc storage list | grep $ZPOOL_NAME
echo "       \}"
while true; do
    read -p "Are you sure $ZPOOL_NAME is safe to erase?" yn
        case $yn in
            [Yy]* ) 
                echo "Continuing ...." ; 
                break;;
            [Nn]* ) 
                echo "Exiting due to user input" ; 
                exit;;
            * ) 
                echo "Please answer yes or no.";;
        esac
done
echo "[f24.2r] Purging conflicting configurations"
    zpool destroy -f $ZPOOL_NAME
    lxc storage delete $ZPOOL_NAME
    lxc storage create $ZPOOL_NAME $ZPOOL_TYPE
echo "[f24.3r] Configuring LXD init with preseed data"
cat <<EOF | lxd init --preseed 
config:
  core.https_address: 0.0.0.0:8443
  core.trust_password: default
  images.auto_update_interval: 60
networks:
- name: ovs
  type: bridge
  config:
    dns.mode: none
    ipv4.nat: false
    ipv4.dhcp: false
    ipv4.address: none
    ipv4.routing: false
    ipv4.firewall: false
    ipv6.nat: false
    ipv6.dhcp: false
    ipv6.address: none
    ipv6.routing: false
    ipv4.firewall: false
profiles:
- name: default
  devices:
    root:
      path: /
      pool: default
      type: disk
  devices:
    eth0:
      name: eth0
      nictype: bridged
      parent: ovs
      type: nic
EOF
echo "$SEP_2 Configured LXD successfully with preseed values"
echo "Done"
}

install_LXD () {
# Install LXD Packages
echo "[f23.0s] Installing LXD from PPA"
    apt-add-repository ppa:ubuntu-lxc/stable -y
	apt update
	apt install -y -t xenial-backports \
		lxd \
		lxd-client \
		lxd-tools \
		lxc-common \
		lxcfs \
		liblxc1 \
		uidmap \
		criu \
		zfsutils-linux \
		ebtables
# sudo -i
# groupadd --system-extrausers lxd
# lxd --group lxd --debug
# newgrp lxd
# lxc remote add images images.linuxcontainers.org
# usermod -G lxd -a <username>
# snap install lxd (--edge) 
echo "$SEP_2 Installed LXD requirements successfully!"	
}

configure_OPENVSWITCH () {
# configure system for OVS
# If supported & user approves, enable dpdk
echo "[f22.0s] Configuring Host for OpenVSwitch with DPDK Enablement"
echo "[f22.1r]"
	update-alternatives --set ovs-vswitchd /usr/lib/openvswitch-switch-dpdk/ovs-vswitchd-dpdk
echo "[f22.2r]"
	systemctl restart openvswitch-switch.service
echo "$SEP_2 Done"
}

install_OPENVSWITCH () {
# Install OpenVSwitch Packages
echo "[f21.0s] Installing OpenVSwitch Components"
OVS_PKGS="openvswitch-common \
          openvswitch-switch"
OVS_DPDK_PKGS="dkms 
               dpdk \
	       dpdk-dev \
               openvswitch-switch-dpdk"

	apt install -y $OVS_PKGS $OVS_DPDK_PKGS
echo "$SEP_2 Done"
}

apt_PKG_INST () {
echo "[f20.0s] Installing Packages"
    apt_UPDATE
echo "$SEP_2 Starting OpenVSwitch Host Configuration ..."
	install_OPENVSWITCH
echo "[f21.0e] Installed OpenVSwitch requirements!"
echo "$SEP_2 OpenVSwitch Components"
	configure_OPENVSWITCH
echo "[f22.0e]"
echo "$SEP_2 Installing and configuring packages"
	install_LXD
echo "[f23.0e] "
echo "$SEP_2 Configuring LXD Components"
	configure_LXD
echo "[f24.0e]"
echo "$SEP_2 Installing Libvirt | KVM | QEMU Components"
	install_LIBVIRT
echo "[f25.0e]"
	configure_LIBVIRT
echo "[f26.0e]"
echo "[f20.0e] Installed all components successfully!"
}

check_HOST_VIRT_SUPPORT () {
# Test host system for virtual extensions
#   (Usually enabled in BIOS on supported hardware)
#   EG: VT-d or AMD-V 

CHECK_HOST_VIRT_EXT=$(egrep -c '(vmx|svm)' /proc/cpuinfo)
echo "[f10.0b]"
if [ $CHECK_HOST_VIRT_EXT != "0" ]
    then
	echo "$SEP_2 System passed host virtual extension support check"
else
	echo "$SEP_2 ERROR: Host did not pass virtual extension support check!"
	echo "       $SEP_2 This means that your hardware either does not support"
	echo "       $SEP_2 KVM acceleration (VT-d|AMD-v), or the feature has not"
	echo "       $SEP_2 yet been enabled in BIOS."
	echo "       $SEP_2 You may continue installation but libvirt guests will"
	echo "       $SEP_2 only run in HVM mode. HVM guests will experience"
	echo "       $SEP_2 significantly degrated performance as compared to"
	echo "       $SEP_2 running with full PVM support.
	     "
	while true; do
		read -p "$SEP_2 Do you want to continue installation?"
		case $yn in
			[Yy]* ) echo "$SEP_2 Continuing ..." ; 
				break;;
			[Nn]* ) echo "$SEP_2 Exiting due to user input!"
				exit;;
			* ) echo "$SEP_2 Please answer yes or no." ;;
		esac
	done
fi
echo "[f10.0e]"
}

RUN () {
echo "[f10.0o] Checking system for hardware support..."
    check_HOST_VIRT_SUPPORT
echo "[f10.0c]"
echo "[f20.0o] Starting Hypervisor Installation"
    apt_PKG_INST
echo "[f20.0c]"
}

RUN




#===============================================================================#
# Research required on scripting the following:
# - Hugepages
# - OVS-DPDK configuration
#
# DO NOT USE UNTIL FULLY TESTED!!!!!
#(/etc/default/grub) <> 
# GRUB_CMDLINE_LINUX_DEFAULT= \
#    "default_hugepagesz=1G \
#    hugepagesz=1G \
#    hugepages=16 \
#    hugepagesz=2M \
#    hugepages=2048 \
#    iommu=pt \
#    intel_iommu=on \
#    isolcpus=2-8,10-16,18-24,26-32"
#(/etc/dpdk/dpdk.conf) <> NR_1G_PAGES=8
#sudo mkdir -p /mnt/huge
#sudo mkdir -p /mnt/huge_2mb
#sudo mount -t hugetlbfs none /mnt/huge
#sudo mount -t hugetlbfs none /mnt/huge_2mb -o pagesize=2MB
#sudo mount -t hugetlbfs none /dev/hugepages
#sudo update-grub
#sudo reboot
#(confirm HP config) $ grep HugePages_ /proc/meminfo cat /proc/cmdline
#‘sudo ovs-vsctl ovs-vsctl set Open_vSwitch . <argument>’.
#sudo ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
