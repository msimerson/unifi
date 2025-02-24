# unifi

Dev tools for UI/Unifi/Ubiquiti

## uxg-6rd-tunnel.sh

Tested by the author on a UXG-Max. I expect it'll work the same with the entire family: UXG-[Lite|Max|Pro|Enterprise].

To establish an IPv6 tunnel with Quantum in "Legacy Qwest" territory, we still 🙄 need to use a slow and ancient bit of technology called 6rd. After replacing my USG-3P, the commands I needed to run on my UXG-Max were:

```sh
ip tunnel add 6rd mode sit remote any local 174.21.137.73 ttl 64
ip tunnel 6rd dev 6rd 6rd-prefix 2602::/24
ip addr add 2602:ae:1589:4900:0::1/24 dev eth4
ip addr add 2602:ae:1589:4900:1::1/64 dev br0
ip link set 6rd up
ip route add ::/0 via ::205.171.2.64 dev 6rd
```

Simple, right? The dynamic bits of those commands are the public IPv4 address assigned by Quantum (174.21.137.73), the IPv4 derived IPv6 network prefix (2602:ae:1589:4900), and the devices eth4 and br0 which depend on how you cable up your router. The uxg-6rd-tunnel.sh logic is:

1. discover the public facing NIC (eth4 above)
2. discover the currently assigned public IPv4 address
3. calculate the IPv6 derived prefix
4. exit if the IPv6 address is already set up
5. tear down any remnants of the previous IPv6 tunnel
6. build a new IPv6 tunnel named 6rd

### dependencies

On the C5500XK ONT that Quantum provided me, I plugged in a Cat6 to my M3 MacBook Air and a [uni ethernet adapter](https://www.amazon.com/dp/B077KXY71Q) and immediately hit 940 Mbps up and down. My Quantum installer took pictures of that USB-C adapter as apparently most can't reliably saturage a 1Gb pipe. My upgrade was done in 8 minutes, goodbye Quantum tech. 👋🏻 

What's with this 192.168 address? The new ONT is a fiber modem AND a router. For now... On the label is the password for the `admin` user. I logged in, visited the `Advanced -> WAN` tab and switched to Transparent Bridging with VLAN 201 tagging (from memory, this part may be imprecise). The ONT rebooted itself and when it came back online my MBA got a public IP via plain old DHCP. 🎉 Hooray, no more PPPoE or VLAN tagging. Sadly, still no IPv6. ☹️

### Unifi Controller settings

Settings -> Networks -> Default -> IPv6

- Interface Type: Static
- Gateway:
  - IPv6 Address: fdxx:xxxx::1  (get a [random one](https://cd34.com/rfc4193/))
  - Netmask: 64
- Advanced: Manual
- Client Address Assignment: SLAAC
- DNS Server:
  - fdxx:xxxx::3
  - 2606:4700:4700::1111
RA: ✅

Settings -> Internet -> Primary -> IPv6

- IPv6 Connection: Disabled

### automating on IPv4 address change

I've installed a slightly modified version of this script to `/etc/dhcp/dhclient-exit-hooks.d/net_6rd`. I'm not certain I have it working perfectly and I'm bored with rebooting the router to keep testing. The mods, based on reading from `dhclient-script` look like this:

```sh
if ([ $reason = "BOUND" ] || [ $reason = "RENEW" ])
then
    has_pub6_changed
    tunnel_destroy
    tunnel_create
fi
```

---

## usg-3p-6rd-tunnel.sh

This is the script I used for years and years to get CenturyLink IPv6 working on my USG 3P gateway. I never did get it to work automatically when my IP changed (usually after a router reboot) and so I just logged into the console and ran this script.

