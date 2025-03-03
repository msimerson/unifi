#!/bin/sh

# FreeBSD 6rd router setup script for Quantum (Lumen)
#
#   note: will not work for CenturyLink (also Lumen) which requires PPPoE
#
# This is designed to run on a FreeBSD router, which has one NIC plugged into
# the Quantum ONT (in Transparent Bridge mode with VLAN 201 tagging) and
# another NIC connected to your LAN.
#
# This script establishes a 6rd tunnel to Quantum (enabling IPv6 on the router)
# and then sets up routing and advertises the IPv6 routes to the LAN. It lets
# one use a vanilla FreeBSD host in the same way as OPNsense or pfSense.
#
# Revised: 2025-02-26
# tested on FreeBSD 14.2

# router specific settings
LAN_DEV="em0"
WAN_DEV="re0"
TUN_DEV="stf0"

# settings specific to the ISP (Quantum/CenturyLink/Lumen shown)
IP6RD_PREFIX="2602"
IP6RD_PREFIX_LEN="24"
IP6RD_ROUTER="205.171.2.64"

get_ip4()
{
    IP4=$(ifconfig $WAN_DEV | grep 'inet ' | awk '{ print $2 }' )
    if [ -z "$IP4" ]; then
	# more ways to get public IPv4 address
        # fetch -qo - http://ifconfig.me/ip
	# dig +short @resolver4.opendns.com myip.opendns.com
	IP4=$(drill -Q @resolver4.opendns.com myip.opendns.com)
        if [ -z "$IP4" ]; then
            echo "Unable to determine public IPv4 address"
            exit 2
	fi
    fi
    echo "$IP4"
}

get_ip6()
{
    ifconfig $1 | grep inet6 | grep $IP6RD_PREFIX | awk '{ print $2 }'
}

get_derived_ip6()
{
    printf "$IP6RD_PREFIX:%02x:%02x%02x:%02x00\n" $(echo "$1" | tr . ' ')
}

PUB_4_ADDR=$(get_ip4)
PUB_6_PREFIX=$(get_derived_ip6 "$PUB_4_ADDR")

echo "Found public IPv4 $PUB_4_ADDR on $WAN_DEV"

has_pub6_changed()
{
    WAN_6_NEW="$PUB_6_PREFIX::1"
    WAN_6_CUR=$(get_ip6 "$WAN_DEV")

    if [ "$WAN_6_CUR" = "$WAN_6_NEW" ]; then
        echo "WAN IPv6 unchanged: $WAN_6_CUR on $WAN_DEV"
        exit
    fi

    if [ -n "$WAN_6_CUR" ]; then
        echo "Updating WAN IPv6 $WAN_6_CUR -> $WAN_6_NEW"
    else
        echo "Setting WAN IPv6 $WAN_6_NEW"
    fi
}

assure_forwarding()
{
    if [ "$(sysctl -n net.inet6.ip6.forwarding)" = "0" ]; then
        echo "enabling IPv6 forwarding"
        sysctl net.inet6.ip6.forwarding=1
    fi
}

assure_no_adv_on_lan()
{
    if grep ifconfig_${LAN_DEV}_ipv6 /etc/rc.conf | grep -q '\-accept_rtadv'; then
	echo "HAS: -accept_rtadvd on $LAN_DEV"
    else
	echo "MISSING: -accept_rtadvd on $LAN_DEV in /etc/rc.conf"
	sysrc ifconfig_${LAN_DEV}_ipv6+=" -accept_rtadv"
	ifconfig $LAN_DEV inet6 -accept_rtadv
    fi
}

start_rtadvd()
{
    if ! sysrc -c rtadvd_enable=YES; then
        sysrc rtadvd_enable=YES
    fi

    if ! sysrc -c rtadvd_interfaces=$LAN_DEV; then
        sysrc rtadvd_interfaces=$LAN_DEV
    fi

    if service rtadvd status | grep -q running; then
	service rtadvd restart
    else
	service rtadvd start
    fi
}

reload_pf()
{
    if ! sysrc -c pf_enable=YES; then return; fi
    PF_FILE=$(sysrc -n pf_rules)
    if [ -z "$PF_FILE" ]; then PF_FILE=/etc/pf.conf; fi
    pfctl -f $PF_FILE
}

tunnel_destroy()
{
    if [ -n "$(netstat -rn6 | grep ^default)" ]; then
        route -6 del default
    fi

    for _dev in $WAN_DEV $LAN_DEV; do
        for _ip6 in $(ifconfig $_dev | grep inet6 | grep $IP6RD_PREFIX | awk '{ print $2 }')
        do
            echo "ifconfig $_dev inet6 $_ip6 delete"
            ifconfig $_dev inet6 $_ip6 delete
        done
    done

    ifconfig $TUN_DEV destroy 2>/dev/null
}

tunnel_create()
{
    ifconfig $TUN_DEV create
    ifconfig $TUN_DEV inet6 $PUB_6_PREFIX:: prefixlen 24 up
    ifconfig $TUN_DEV stfv4net 0.0.0.0/32 stfv4br $IP6RD_ROUTER description Quantum-6rd-tunnel
    ifconfig $WAN_DEV inet6 $PUB_6_PREFIX::1/$IP6RD_PREFIX_LEN
    ifconfig $LAN_DEV inet6 $PUB_6_PREFIX:1::1/64

    assure_forwarding
    route -6 add default -interface $TUN_DEV

    reload_pf
    assure_no_adv_on_lan
    start_rtadvd
}

has_pub6_changed
tunnel_destroy
tunnel_create
