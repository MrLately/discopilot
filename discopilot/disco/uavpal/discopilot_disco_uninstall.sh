#!/bin/sh

root_rw=0

info()
{
	printf '%s\n' "$*"
}

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	if [ "$root_rw" = "1" ]; then
		mount -o remount,ro / >/dev/null 2>&1
	fi
	exit 1
}

remount_root_rw()
{
	mount -o remount,rw / || die "could not remount / read-write"
	root_rw=1
}

remount_root_ro()
{
	if [ "$root_rw" = "1" ]; then
		mount -o remount,ro / || die "could not remount / read-only"
		root_rw=0
	fi
}

trap 'if [ "$root_rw" = "1" ]; then mount -o remount,ro / >/dev/null 2>&1; fi' EXIT HUP INT TERM

case "$0" in
	*/*)
		script_dir=${0%/*}
	;;
	*)
		script_dir=.
	;;
esac

cd "$script_dir" || die "could not enter uninstaller directory: $script_dir"

run_dir=$(pwd)
payload_dir=""
if [ "$run_dir" = "/data/ftp/internal_000/discopilot/disco/uavpal" ]; then
	payload_dir="/data/ftp/internal_000/discopilot"
fi

if [ "$run_dir" = "/data/ftp/uavpal" ]; then
	die "do not run this uninstaller from /data/ftp/uavpal; run it from the transferred package in internal storage"
fi

if [ "$1" != "--from-tmp" ] && [ -n "$payload_dir" ]; then
	tmp_uninstall="/tmp/discopilot_disco_uninstall.sh"
	cp "$0" "$tmp_uninstall" || die "could not copy uninstaller to /tmp"
	chmod +x "$tmp_uninstall" >/dev/null 2>&1
	exec sh "$tmp_uninstall" --from-tmp "$payload_dir"
	die "could not re-run uninstaller from /tmp"
fi

if [ "$1" = "--from-tmp" ]; then
	payload_dir="$2"
fi

info "=== Uninstalling DiscoPilot softmod from Disco ==="

info "Stopping DiscoPilot processes"
killall -9 uavpal_disco.sh >/dev/null 2>&1
killall -9 uavpal_telemetry.sh >/dev/null 2>&1
killall -9 uavpal_telemetry_server.sh >/dev/null 2>&1
killall -9 uavpal_telemetry_request_handler.sh >/dev/null 2>&1
killall -9 zerotier-one >/dev/null 2>&1
killall -9 ntpd >/dev/null 2>&1
killall -9 udhcpc >/dev/null 2>&1
killall -9 curl >/dev/null 2>&1
killall -9 chat >/dev/null 2>&1
killall -9 pppd >/dev/null 2>&1

for nc_pid in $(ps | awk '/[n]c -l -p 18080/ {print $1}'); do
	kill -9 "$nc_pid" >/dev/null 2>&1
done

info "Removing system hooks"
remount_root_rw
rm -f /lib/udev/rules.d/70-huawei-e3372.rules || die "could not remove udev rule"
remount_root_ro

info "Removing ZeroTier state"
rm -rf /data/lib/zerotier-one || die "could not remove /data/lib/zerotier-one"

info "Removing DiscoPilot package"
rm -rf /data/ftp/uavpal || die "could not remove /data/ftp/uavpal"

info "Removing runtime temp files"
rm -f /tmp/serial_ctrl_dev
rm -f /tmp/hilink_router_ip
rm -f /tmp/hilink_login_required
rm -f /tmp/modem_gateway_ip
rm -f /tmp/modem_ip
rm -f /tmp/modem_iface
rm -f /tmp/modem_usb_id
rm -f /tmp/modem_usb_desc
rm -f /tmp/modem_connection_profile
rm -f /tmp/uavpal_starting
rm -f /tmp/uavpal_queue_diag
rm -f /tmp/uavpal_route_diag
rm -f /tmp/uavpal_reconnect_diag
rm -f /tmp/uavpal_usb8_diag
rm -f /tmp/uavpal_usb8_diag.tmp
rm -f /tmp/uavpal_telnetd_expires_at
rm -f /tmp/uavpal_zerotier_join.pid
rm -f /tmp/uavpal_zerotier_ready.pid
rm -f /tmp/uavpal_delayed_fallback.pid
rm -f /tmp/uavpal_connection_wait.pid
rm -f /tmp/uavpal_telemetry_loop.pid
rm -f /tmp/uavpal_telemetry_httpd.pid
rm -f /tmp/uavpal_maintenance_httpd.pid
rm -f /tmp/uavpal_telnetd.pid
rm -f /tmp/uavpal_telnetd_stop.sh
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

info "Removing lock files"
rm -f /tmp/lock/uavpal_disco
rm -f /tmp/lock/uavpal_bebop2
rm -f /tmp/lock/uavpal_unload

if [ -n "$payload_dir" ]; then
	case "$payload_dir" in
		/data/ftp/internal_000/discopilot)
			info "Removing transferred installer package"
			rm -rf "$payload_dir" || die "could not remove transferred installer package"
		;;
		*)
			die "refusing to remove unexpected package path: $payload_dir"
		;;
	esac
fi

info "Verification"
if [ -e /data/ftp/uavpal ]; then info "installed package: still present"; else info "installed package: removed"; fi
if [ -e /lib/udev/rules.d/70-huawei-e3372.rules ]; then info "udev rule: still present"; else info "udev rule: removed"; fi
if [ -e /data/lib/zerotier-one ]; then info "ZeroTier state: still present"; else info "ZeroTier state: removed"; fi
if [ -e /data/ftp/internal_000/discopilot ]; then info "transferred package: still present"; else info "transferred package: removed"; fi

info "Uninstall complete. Reboot the Disco before normal use."
