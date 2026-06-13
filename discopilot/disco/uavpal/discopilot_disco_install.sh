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

case "$0" in
	*/*)
		script_dir=${0%/*}
	;;
	*)
		script_dir=.
	;;
esac

cd "$script_dir" || die "could not enter installer directory: $script_dir"

src_dir=$(pwd)
dst_parent="/data/ftp"
dst_dir="${dst_parent}/uavpal"
udev_rule="/lib/udev/rules.d/70-huawei-e3372.rules"
zt_dir="/data/lib/zerotier-one"
zt_local_conf="${zt_dir}/local.conf"

trap 'if [ "$root_rw" = "1" ]; then mount -o remount,ro / >/dev/null 2>&1; fi' EXIT HUP INT TERM

info "=== Installing DiscoPilot softmod on Disco ==="

require_dir "$src_dir"
require_dir "$dst_parent"
require_dir "${src_dir}/bin"
require_dir "${src_dir}/conf"
require_dir "${src_dir}/lib"
require_dir "${src_dir}/mod"
require_file "${src_dir}/bin/uavpal_disco.sh"
require_file "${src_dir}/conf/zt_networkid"
require_file "${src_dir}/conf/70-huawei-e3372.rules"
require_file "${src_dir}/conf/local.conf"
require_file "${src_dir}/version.txt"

if [ "$src_dir" = "$dst_dir" ]; then
	die "installer is already running from ${dst_dir}; run it from the transferred package in internal storage"
fi

if [ -e "$dst_dir" ]; then
	die "${dst_dir} already exists; this installer is for a fresh unmodded Disco"
fi

info "Copying DiscoPilot files to ${dst_dir}"
mkdir "$dst_dir" || die "could not create ${dst_dir}"
cp -fr "${src_dir}/"* "$dst_dir" || die "copy failed"
rm -f "${dst_dir}/discopilot_disco_install.sh" || die "could not remove installer from installed package"

info "Making binaries and scripts executable"
chmod +x "${dst_dir}/bin/"* || die "chmod failed for ${dst_dir}/bin"

info "Installing udev rule"
remount_root_rw
rm -f "$udev_rule" || die "could not remove existing udev rule path"
ln -s "${dst_dir}/conf/70-huawei-e3372.rules" "$udev_rule" || die "could not create udev rule symlink"
remount_root_ro

info "Creating ZeroTier config directory"
mkdir -p "$zt_dir" || die "could not create ${zt_dir}"

info "Creating ZeroTier local.conf symlink"
rm -f "$zt_local_conf" || die "could not remove existing ${zt_local_conf}"
ln -s "${dst_dir}/conf/local.conf" "$zt_local_conf" || die "could not create ${zt_local_conf} symlink"

installed_version=$(head -1 "${dst_dir}/version.txt" | tr -d '\r\n')
installed_zt_network=$(head -1 "${dst_dir}/conf/zt_networkid" | tr -d '\r\n')

info "Installed version: ${installed_version}"
info "ZeroTier network ID: ${installed_zt_network}"
info "Install complete. Reboot or reconnect the modem to start the mod."
