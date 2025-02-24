#!/bin/vbash

# Starts up an IPv6 6rd tunnel on a Ubiquti USG-3P gateway

export SBIN="/opt/vyatta/sbin/my_"
export DESCRIPTION="CenturyLink IPv6 6rd tunnel"
export WAN_DEV="pppoe2"
export LAN_DEV="eth1"
export TUN_DEV="tun0"
export TUN_STATUS=""

export WAN_4_ADDR=""

export WAN_6_OLD=""
export WAN_6_NEW=""
export WAN_6_PREFIX_LEN="64"

# These settings are specific to your ISP (CenturyLink shown)
export IP6_6RD_PREFIX="2602"
export IP6_6RD_PREFIX_LEN="24"
export IP6_6RD_ROUTER="205.171.2.64"

export IP6_NAMESERVERS="2606:4700:4700::1111 2606:4700:4700::1001"
# Cloudflare: 2606:4700:4700::1111,1001
# CenturyLink/qwest 2001:428::1,2

get_ip4()
{
    IP4=$(ip -4 -o addr list "$1" | awk '{print $4}' | cut -d/ -f1)
    if [ -z "$IP4" ]; then
        echo "Unable to determine IPv4 address"
        exit 2
    fi
    echo "$IP4"
}

get_ip6()
{
    ip -6 -o addr show up "$1" | \
        grep $IP6_6RD_PREFIX | grep -v fe80 | \
        awk '{print $4}' | cut -f1 -d/ | head -n1
}

get_derived_ip6()
{
    # shellcheck disable=2046
    printf "$IP6_6RD_PREFIX:%02x:%02x%02x:%02x00::1\n" $(echo "$1" | tr . ' ')
}

apply_config()
{
    if [ -n "$TUN_STATUS" ]; then
        # delete the existing tunnel interface
        ${SBIN}delete interfaces tunnel $TUN_DEV
    fi

    ${SBIN}set interfaces tunnel $TUN_DEV description "$DESCRIPTION"
    ${SBIN}set interfaces tunnel $TUN_DEV 6rd-prefix "${IP6_6RD_PREFIX}::/${IP6_6RD_PREFIX_LEN}"
    ${SBIN}set interfaces tunnel $TUN_DEV 6rd-default-gw "::${IP6_6RD_ROUTER}"
    ${SBIN}set interfaces tunnel $TUN_DEV local-ip "$WAN_4_ADDR"
    ${SBIN}set interfaces tunnel $TUN_DEV encapsulation sit
    ${SBIN}set interfaces tunnel $TUN_DEV multicast disable
    ${SBIN}set interfaces tunnel $TUN_DEV ttl 255
    ${SBIN}set interfaces tunnel $TUN_DEV mtu 1472
    ${SBIN}set interfaces tunnel $TUN_DEV firewall in ipv6-name WANv6_IN
    ${SBIN}set interfaces tunnel $TUN_DEV firewall local ipv6-name WANv6_LOCAL
    ${SBIN}set interfaces tunnel $TUN_DEV firewall out ipv6-name WANv6_OUT

    ${SBIN}set interfaces ethernet $LAN_DEV address ${WAN_6_NEW}/${WAN_6_PREFIX_LEN}
    ${SBIN}delete interfaces ethernet $LAN_DEV ipv6
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 dup-addr-detect-transmits 1
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert cur-hop-limit 64
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert managed-flag false
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert max-interval 300
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert other-config-flag false
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert prefix "${WAN_6_NEW}/${WAN_6_PREFIX_LEN}" autonomous-flag true
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert prefix "${WAN_6_NEW}/${WAN_6_PREFIX_LEN}" on-link-flag true
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert prefix "${WAN_6_NEW}/${WAN_6_PREFIX_LEN}" valid-lifetime 3600
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert reachable-time 0
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert retrans-timer 0
    ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert send-advert true

    for ns in $IP6_NAMESERVERS;
    do
        ${SBIN}set interfaces ethernet $LAN_DEV ipv6 router-advert name-server "$ns"
    done
}

if [ -n "$PPP_IFACE" ] && [ -n "$PPP_LOCAL" ]; then
    # called by ppp-up script
    WAN_DEV=""
else
    WAN_4_ADDR=$(get_ip4 "$WAN_DEV")
    echo "Found public IPv4 $WAN_4_ADDR on $WAN_DEV"
fi

# shellcheck disable=1091
source /opt/vyatta/etc/functions/script-template
configure

TUN_STATUS=$(show interfaces tunnel "$TUN_DEV")
WAN_6_NEW=$(get_derived_ip6 "$WAN_4_ADDR")

if [ -n "$TUN_STATUS" ]; then
    WAN_6_OLD=$(get_ip6 "$LAN_DEV")

    if [ "$WAN_6_OLD" = "$WAN_6_NEW" ]; then
        echo "Public IPv6 on $LAN_DEV unchanged: $WAN_6_OLD"
        exit
    fi
fi

if [ -n "$WAN_6_OLD" ]; then
    echo "Updating IPv6 $WAN_6_OLD -> $WAN_6_NEW"
else
    echo "Setting IPv6 $WAN_6_NEW"
fi

apply_config && commit && save
exit