#!/bin/sh

ADB="/data/ftp/uavpal/bin/adb"
SC2_PORT="9050"
DST_DIR="/data/lib/ftp/uavpal"
ZT_DIR="/data/lib/zerotier-one"
SERVICE_FILE="/etc/boxinit.d/99-uavpal.rc"

info()
{
	printf '%s\n' "$*"
}

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

require_file()
{
	if [ ! -f "$1" ]; then
		die "required file missing: $1"
	fi
}

detect_sc2_ip()
{
	attempt=1
	while [ "$attempt" -le 30 ]; do
		ip_sc2=$(netstat -nu 2>/dev/null | awk '$5 ~ /^192\.168\.42\.[0-9]+:9988$/ { sub(/:9988$/, "", $5); print $5; exit }')
		if [ -n "$ip_sc2" ]; then
			printf '%s\n' "$ip_sc2"
			return 0
		fi
		info "Trying to detect Skycontroller 2 local IP (${attempt}/30)" >&2
		attempt=$((attempt + 1))
		sleep 1
	done
	return 1
}

connect_sc2()
{
	target="$1:${SC2_PORT}"
	attempt=1
	while [ "$attempt" -le 15 ]; do
		if [ "$attempt" -eq 1 ]; then
			"$ADB" start-server >/dev/null 2>&1
		fi
		response=$("$ADB" connect "$target" 2>&1)
		case "$response" in
			*"connected to"*|*"already connected to"*)
				return 0
			;;
			*"ADB server didn't ACK"*|*"failed to start daemon"*|*"cannot connect to daemon"*)
				info "ADB daemon did not start cleanly; resetting (${attempt}/15)" >&2
				"$ADB" kill-server >/dev/null 2>&1
			;;
			*)
				info "Trying to connect to Skycontroller 2 at ${target} (${attempt}/15)" >&2
			;;
		esac
		attempt=$((attempt + 1))
		sleep 1
	done
	return 1
}

info "=== Uninstalling DiscoPilot softmod from Skycontroller 2 ==="

require_file "$ADB"

ip_sc2=$(detect_sc2_ip) || die "could not detect Skycontroller 2 local IP on 192.168.42.x:9988"
info "Detected Skycontroller 2 at ${ip_sc2}"

connect_sc2 "$ip_sc2" || die "could not connect to Skycontroller 2 adb at ${ip_sc2}:${SC2_PORT}"
sc2_target="${ip_sc2}:${SC2_PORT}"

info "Stopping DiscoPilot SC2 processes"
"$ADB" -s "$sc2_target" shell "killall -9 uavpal_sc2.sh >/dev/null 2>&1; killall -9 zerotier-one >/dev/null 2>&1; killall -9 udhcpc >/dev/null 2>&1; killall -SIGCONT mppd >/dev/null 2>&1; killall -SIGCONT wifid >/dev/null 2>&1" || die "could not stop SC2 processes"

info "Removing SC2 service"
"$ADB" -s "$sc2_target" shell "mount -o remount,rw / && rm -f ${SERVICE_FILE}; rc=\$?; mount -o remount,ro /; exit \$rc" || die "could not remove SC2 service"

info "Removing ZeroTier state"
"$ADB" -s "$sc2_target" shell "rm -rf ${ZT_DIR}" || die "could not remove ${ZT_DIR}"

info "Removing SC2 package"
"$ADB" -s "$sc2_target" shell "rm -rf ${DST_DIR}" || die "could not remove ${DST_DIR}"

info "Removing DiscoPilot temp files"
"$ADB" -s "$sc2_target" shell "rm -f /tmp/uavpal_sc2_diag /tmp/uavpal_sc2_mode /tmp/zt_interface /tmp/zerotier-one_err /tmp/mode /tmp/button_prev_timestamp /tmp/button_timestamp" || die "could not remove temp files"

info "Verification:"
"$ADB" -s "$sc2_target" shell "if [ -e ${SERVICE_FILE} ]; then echo service: still present; else echo service: removed; fi"
"$ADB" -s "$sc2_target" shell "if [ -e ${DST_DIR} ]; then echo package: still present; else echo package: removed; fi"
"$ADB" -s "$sc2_target" shell "if [ -e ${ZT_DIR} ]; then echo ZeroTier state: still present; else echo ZeroTier state: removed; fi"

info "SC2 uninstall complete. Reboot the Skycontroller 2 before normal use."
