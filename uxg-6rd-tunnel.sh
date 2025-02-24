#!/bin/bash

# settings specific to the router
LAN_DEV="br0"
TUN_DEV="6rd"

# settings specific to the ISP (Quantum/CenturyLink/Lumen shown)
IP6RD_PREFIX="2602"
IP6RD_PREFIX_LEN="24"
IP6RD_ROUTER="205.171.2.64"

# Apply DNS servers in the Unifi Controller:
#     Networks -> $NAME -> IPv6 -> Advanced=Manual -> DNS Server
# CenturyLink/qwest 2001:428::1, 2
# Others: https://en.wikipedia.org/wiki/Public_recursive_name_server

get_ip4()
{
    IP4=$(ip route get 1.1.1.1 | grep -oP 'src \K[^ ]+')
    if [ -z "$IP4" ]; then
        echo "Unable to determine public IPv4 address"
        exit 2
    fi
    echo "$IP4"
}

get_ip6()
{
    ip -6 -o addr show up "$1" | \
        grep $IP6RD_PREFIX | grep -v fe80 | \
        awk '{print $4}' | cut -f1 -d/ | head -n1
}

get_derived_ip6()
{
    printf "$IP6RD_PREFIX:%02x:%02x%02x:%02x00\n" $(echo "$1" | tr . ' ')
}

WAN_DEV="$(ip route get 1.1.1.1 | grep -oP 'dev \K[^ ]+')"
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

tunnel_destroy()
{
    if [ -n "$(ip -6 route list default)" ]; then
      ip -6 route del default
    fi

    for _dev in $WAN_DEV $LAN_DEV; do
      for _ip6 in $(ip -6 -o addr show up dev $_dev | grep $IP6RD_PREFIX | grep -oP 'inet6 \K[^ ]+')
      do
        echo "ip -6 addr del $_ip6 dev $_dev"
        ip -6 addr del $_ip6 dev $_dev
      done
    done

    ip tunnel del 6rd 2>/dev/null
}

tunnel_create()
{
    ip tunnel add $TUN_DEV mode sit remote any local $PUB_4_ADDR ttl 64
    ip tunnel 6rd dev $TUN_DEV 6rd-prefix $IP6RD_PREFIX::/$IP6RD_PREFIX_LEN
    ip addr add $PUB_6_PREFIX:0::1/$IP6RD_PREFIX_LEN dev $WAN_DEV
    ip addr add $PUB_6_PREFIX:1::1/64 dev $LAN_DEV
    ip link set $TUN_DEV up
    ip route add ::/0 via ::$IP6RD_ROUTER dev $TUN_DEV
}

has_pub6_changed
tunnel_destroy
tunnel_create
