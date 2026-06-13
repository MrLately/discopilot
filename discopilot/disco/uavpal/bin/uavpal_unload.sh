#!/bin/sh

usbmodeswitchStatus=`ps |grep usb_modeswitch |grep -v grep |wc -l`
if [ $usbmodeswitchStatus -ne 0 ]; then
	exit 0  # ignoring "removal" event while usb_modesswitch is running
fi

# Ignore unrelated USB removal events while modem is still present.
MODEM_USB_IDS="12d1:* 19d2:* 2c7c:* 1199:* 2dee:* 05c6:* 1bc7:* 413c:*"
if [ -f /data/ftp/uavpal/conf/modem.conf ]; then
	# shellcheck disable=SC1091
	. /data/ftp/uavpal/conf/modem.conf
fi

active_modem_usb_id=""
if [ -f /tmp/modem_usb_id ]; then
	active_modem_usb_id=$(head -1 /tmp/modem_usb_id 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '\r\n')
fi

modem_still_present()
{
	for line in $(lsusb 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="ID") print $(i+1)}' | tr 'A-Z' 'a-z'); do
		if [ -n "$active_modem_usb_id" ]; then
			if [ "$line" = "$active_modem_usb_id" ]; then
				return 0
			fi
			continue
		fi
		for pattern in $MODEM_USB_IDS; do
			pattern_lc=$(echo "$pattern" | tr 'A-Z' 'a-z')
			case "$line" in
			$pattern_lc)
				return 0
				;;
			*)
				;;
			esac
		done
	done
	return 1
}

if modem_still_present; then
	exit 0
fi

# Some modems briefly disconnect/re-enumerate (e.g. storage mode -> modem mode).
# Hold off unload for a short time and re-check whether a supported modem appears.
for retry in $(seq 1 12); do
	usleep 500000
	if modem_still_present; then
		exit 0
	fi
done

ulogger -s -t uavpal_drone "USB modem disconnected"
ulogger -s -t uavpal_drone "... unloading scripts and daemons"
killall -9 uavpal_disco.sh
killall -9 uavpal_bebop2.sh
killall -9 uavpal_telemetry.sh
killall -9 zerotier-one
killall -9 ntpd
killall -9 udhcpc
killall -9 curl
killall -9 chat
killall -9 pppd

ulogger -s -t uavpal_drone "... stopping telemetry endpoint"
if [ -f /tmp/uavpal_telemetry_httpd.pid ]; then
	telemetry_httpd_pid=$(cat /tmp/uavpal_telemetry_httpd.pid 2>/dev/null)
	if [ -n "$telemetry_httpd_pid" ]; then
		kill "$telemetry_httpd_pid" >/dev/null 2>&1
		sleep 1
		kill -9 "$telemetry_httpd_pid" >/dev/null 2>&1
	fi
fi
killall -9 uavpal_telemetry_server.sh >/dev/null 2>&1
killall -9 uavpal_telemetry_request_handler.sh >/dev/null 2>&1
for nc_pid in $(ps | awk '/[n]c -l -p 18080/ {print $1}'); do
	kill -9 "$nc_pid" >/dev/null 2>&1
done
if [ -f /tmp/uavpal_maintenance_httpd.pid ]; then
	maintenance_httpd_pid=$(cat /tmp/uavpal_maintenance_httpd.pid 2>/dev/null)
	if [ -n "$maintenance_httpd_pid" ]; then
		kill "$maintenance_httpd_pid" >/dev/null 2>&1
		sleep 1
		kill -9 "$maintenance_httpd_pid" >/dev/null 2>&1
	fi
fi
if [ -f /tmp/uavpal_telnetd.pid ]; then
	uavpal_telnetd_pid=$(cat /tmp/uavpal_telnetd.pid 2>/dev/null)
	if [ -n "$uavpal_telnetd_pid" ]; then
		kill "$uavpal_telnetd_pid" >/dev/null 2>&1
	fi
fi
if [ -f /tmp/uavpal_zerotier_join.pid ]; then
	uavpal_zerotier_join_pid=$(cat /tmp/uavpal_zerotier_join.pid 2>/dev/null)
	if [ -n "$uavpal_zerotier_join_pid" ]; then
		kill "$uavpal_zerotier_join_pid" >/dev/null 2>&1
	fi
fi
if [ -f /tmp/uavpal_zerotier_ready.pid ]; then
	uavpal_zerotier_ready_pid=$(cat /tmp/uavpal_zerotier_ready.pid 2>/dev/null)
	if [ -n "$uavpal_zerotier_ready_pid" ]; then
		kill "$uavpal_zerotier_ready_pid" >/dev/null 2>&1
	fi
fi
if [ -f /tmp/uavpal_delayed_fallback.pid ]; then
	uavpal_delayed_fallback_pid=$(cat /tmp/uavpal_delayed_fallback.pid 2>/dev/null)
	if [ -n "$uavpal_delayed_fallback_pid" ]; then
		kill "$uavpal_delayed_fallback_pid" >/dev/null 2>&1
	fi
fi
if [ -f /tmp/uavpal_connection_wait.pid ]; then
	uavpal_connection_wait_pid=$(cat /tmp/uavpal_connection_wait.pid 2>/dev/null)
	if [ -n "$uavpal_connection_wait_pid" ]; then
		kill "$uavpal_connection_wait_pid" >/dev/null 2>&1
	fi
fi

ulogger -s -t uavpal_drone "... clearing UAVPAL iptables rules"
iptables -D INPUT -j UAVPAL_INPUT 2>/dev/null
iptables -F UAVPAL_INPUT 2>/dev/null
iptables -X UAVPAL_INPUT 2>/dev/null
# Backward compatibility: remove direct INPUT drop rules from older releases.
legacy_ifaces="eth1 ppp0 ppp1 ppp2 ppp3"
for ifname in $(ls /proc/sys/net/ipv4/conf 2>/dev/null | grep '^ppp'); do
	legacy_ifaces="$legacy_ifaces $ifname"
done
for iface in $legacy_ifaces; do
	for port in 21 23 51 61 873 8888 9050 44444 67 5353 14551; do
		while iptables -D INPUT -p tcp -i $iface --dport $port -j DROP 2>/dev/null; do :; done
	done
done

ulogger -s -t uavpal_drone "... clearing default route"
if [ -f /tmp/hilink_router_ip ]; then
	ip route del default via "$(cat /tmp/hilink_router_ip)" >/dev/null 2>&1
fi
if [ -f /tmp/modem_gateway_ip ]; then
	ip route del default via "$(cat /tmp/modem_gateway_ip)" >/dev/null 2>&1
fi

ulogger -s -t uavpal_drone "... removing temp files"
rm -f /tmp/serial_ctrl_dev
rm -f /tmp/hilink_router_ip
rm -f /tmp/hilink_login_required
rm -f /tmp/modem_gateway_ip
rm -f /tmp/modem_ip
rm -f /tmp/modem_iface
rm -f /tmp/modem_usb_id
rm -f /tmp/modem_usb_desc
rm -f /tmp/modem_provider
rm -f /tmp/modem_connection_profile
rm -f /tmp/uavpal_starting
rm -f /tmp/uavpal_queue_diag
rm -f /tmp/uavpal_route_diag
rm -f /tmp/uavpal_reconnect_diag
rm -f /tmp/uavpal_usb8_diag
rm -f /tmp/uavpal_usb8_diag.tmp
rm -f /tmp/uavpal_quectel_setup_diag
rm -f /tmp/uavpal_quectel_diag
rm -f /tmp/uavpal_quectel_diag.tmp
rm -rf /tmp/uavpal_at_command.lock
rm -f /tmp/uavpal_telnetd_expires_at
rm -f /tmp/uavpal_zerotier_join.pid
rm -f /tmp/uavpal_zerotier_ready.pid
rm -f /tmp/uavpal_delayed_fallback.pid
rm -f /tmp/uavpal_connection_wait.pid
rm -f /tmp/uavpal_telemetry_loop.pid
rm -f /tmp/uavpal_telemetry_httpd.pid
rm -f /tmp/uavpal_maintenance_httpd.pid
rm -f /tmp/uavpal_telnetd.pid
rm -f /tmp/uavpal_telemetry.json
rm -f /tmp/uavpal_telemetry.json.tmp
rm -f /tmp/uavpal_telemetry_request_handler.sh
rm -f /tmp/uavpal_maintenance_action.sh
rm -f /tmp/uavpal_telemetry_http_fifo.*
rm -f /tmp/uavpal_telemetry_www/cgi-bin/maintenance
rm -f /tmp/uavpal_telemetry_www/telemetry.json
rm -f /tmp/uavpal_telemetry_server.sh
rm -f /tmp/uavpal_maintenance_www/cgi-bin/maintenance
rmdir /tmp/uavpal_telemetry_www/cgi-bin 2>/dev/null
rmdir /tmp/uavpal_telemetry_www 2>/dev/null
rmdir /tmp/uavpal_maintenance_www/cgi-bin 2>/dev/null
rmdir /tmp/uavpal_maintenance_www 2>/dev/null

ulogger -s -t uavpal_drone "... removing lock files"
rm -f /tmp/lock/uavpal_disco
rm -f /tmp/lock/uavpal_bebop2
rm -f /tmp/lock/uavpal_unload

ulogger -s -t uavpal_drone "... unloading kernel modules"
rmmod xt_tcpudp >/dev/null 2>&1
rmmod iptable_filter >/dev/null 2>&1
rmmod ip_tables >/dev/null 2>&1
rmmod x_tables >/dev/null 2>&1
rmmod option >/dev/null 2>&1
rmmod usb_wwan >/dev/null 2>&1
rmmod usbserial >/dev/null 2>&1
rmmod tun >/dev/null 2>&1
rmmod bsd_comp.ko >/dev/null 2>&1
rmmod ppp_deflate.ko >/dev/null 2>&1
rmmod ppp_async.ko >/dev/null 2>&1
rmmod ppp_generic.ko >/dev/null 2>&1
rmmod slhc.ko >/dev/null 2>&1
rmmod crc-ccitt >/dev/null 2>&1

ulogger -s -t uavpal_drone "*** idle on Wi-Fi ***"
