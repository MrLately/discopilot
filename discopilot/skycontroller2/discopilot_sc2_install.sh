#!/bin/sh

ADB="/data/ftp/uavpal/bin/adb"
SC2_PORT="9050"
SRC_DIR="./uavpal"
DST_PARENT="/data/lib/ftp"
DST_DIR="${DST_PARENT}/uavpal"
ZT_DIR="/data/lib/zerotier-one"
ZT_LOCAL_CONF="${ZT_DIR}/local.conf"
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

require_dir()
{
	if [ ! -d "$1" ]; then
		die "required directory missing: $1"
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

remote_has_path()
{
	result=$("$ADB" -s "$sc2_target" shell "if [ -e $1 ]; then echo present; else echo missing; fi" 2>/dev/null)
	echo "$result" | grep -q "present"
}

remote_require_file()
{
	if ! remote_has_path "$1"; then
		die "remote file missing after copy: $1"
	fi
}

push_file()
{
	src_file="$1"
	dst_file="$2"
	"$ADB" -s "$sc2_target" push "$src_file" "$dst_file" || die "could not push $src_file"
	remote_require_file "$dst_file"
}

push_dir_files()
{
	src_dir="$1"
	dst_dir="$2"
	"$ADB" -s "$sc2_target" shell "mkdir -p ${dst_dir}" || die "could not create ${dst_dir}"
	for src_file in "$src_dir"/*; do
		if [ -f "$src_file" ]; then
			dst_name=${src_file##*/}
			push_file "$src_file" "${dst_dir}/${dst_name}"
		fi
	done
}

case "$0" in
	*/*)
		script_dir=${0%/*}
	;;
	*)
		script_dir=.
	;;
esac

cd "$script_dir" || die "could not enter installer directory: $script_dir"

info "=== Installing DiscoPilot softmod on Skycontroller 2 ==="

require_file "$ADB"
require_dir "$SRC_DIR"
require_dir "${SRC_DIR}/bin"
require_dir "${SRC_DIR}/conf"
require_file "${SRC_DIR}/bin/uavpal_sc2.sh"
require_file "${SRC_DIR}/bin/zerotier-one"
require_file "${SRC_DIR}/conf/local.conf"
require_file "${SRC_DIR}/conf/zt_networkid"
require_file "${SRC_DIR}/version.txt"

ip_sc2=$(detect_sc2_ip) || die "could not detect Skycontroller 2 local IP on 192.168.42.x:9988"
info "Detected Skycontroller 2 at ${ip_sc2}"

connect_sc2 "$ip_sc2" || die "could not connect to Skycontroller 2 adb at ${ip_sc2}:${SC2_PORT}"
sc2_target="${ip_sc2}:${SC2_PORT}"

info "Checking for existing SC2 install"
if remote_has_path "$DST_DIR"; then
	die "${DST_DIR} already exists on Skycontroller 2; uninstall first"
fi

if remote_has_path "${DST_PARENT}/bin" || remote_has_path "${DST_PARENT}/conf" || remote_has_path "${DST_PARENT}/version.txt"; then
	die "partial files found directly under ${DST_PARENT}; remove the failed install leftovers before retrying"
fi

info "Creating package directories"
"$ADB" -s "$sc2_target" shell "mkdir -p ${DST_DIR}/bin ${DST_DIR}/conf" || die "could not create SC2 package directories"

info "Copying SC2 package"
push_dir_files "${SRC_DIR}/bin" "${DST_DIR}/bin"
push_dir_files "${SRC_DIR}/conf" "${DST_DIR}/conf"
push_file "${SRC_DIR}/version.txt" "${DST_DIR}/version.txt"

info "Making binaries and scripts executable"
"$ADB" -s "$sc2_target" shell "chmod +x ${DST_DIR}/bin/*" || die "could not chmod SC2 binaries"
remote_require_file "${DST_DIR}/bin/uavpal_sc2.sh"
remote_require_file "${DST_DIR}/bin/zerotier-one"
remote_require_file "${DST_DIR}/conf/local.conf"
remote_require_file "${DST_DIR}/conf/zt_networkid"
remote_require_file "${DST_DIR}/version.txt"

info "Installing SC2 service"
"$ADB" -s "$sc2_target" shell "mount -o remount,rw / && printf 'service uavpal /data/lib/ftp/uavpal/bin/uavpal_sc2.sh\n    class main\n    user root\n' > ${SERVICE_FILE} && chmod 640 ${SERVICE_FILE}; rc=\$?; mount -o remount,ro /; exit \$rc" || die "could not install SC2 service"

info "Creating ZeroTier local config symlink"
"$ADB" -s "$sc2_target" shell "mkdir -p ${ZT_DIR}" || die "could not create ${ZT_DIR}"
"$ADB" -s "$sc2_target" shell "rm -f ${ZT_LOCAL_CONF}" || die "could not remove existing ${ZT_LOCAL_CONF}"
"$ADB" -s "$sc2_target" shell "ln -s ${DST_DIR}/conf/local.conf ${ZT_LOCAL_CONF}" || die "could not create ${ZT_LOCAL_CONF} symlink"

info "Installed SC2 version:"
"$ADB" -s "$sc2_target" shell "cat ${DST_DIR}/version.txt"

info "ZeroTier version:"
"$ADB" -s "$sc2_target" shell "${DST_DIR}/bin/zerotier-one -v"

info "Verification:"
"$ADB" -s "$sc2_target" shell "ls -l ${SERVICE_FILE} ${ZT_LOCAL_CONF}"

info "SC2 install complete. Reboot the Skycontroller 2 before testing LTE mode."
