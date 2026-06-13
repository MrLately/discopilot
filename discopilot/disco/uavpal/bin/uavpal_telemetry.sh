#!/bin/sh

# exports
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/data/ftp/uavpal/lib

# variables
serial_ctrl_dev=""
if [ -f /tmp/serial_ctrl_dev ]; then
	serial_ctrl_dev=$(head -1 /tmp/serial_ctrl_dev | tr -d '\r\n' | tr -d '\n')
fi

# functions
. /data/ftp/uavpal/bin/uavpal_globalfunctions.sh

json_escape()
{
	echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_bool()
{
	case "$1" in
	1 | true | TRUE | yes | YES | ok | OK)
		echo "true"
		;;
	0 | false | FALSE | no | NO | fail | FAIL)
		echo "false"
		;;
	*)
		echo "null"
		;;
	esac
}

json_number()
{
	case "$1" in
	'' | *[!0-9]*)
		echo "null"
		;;
	*)
		echo "$1"
		;;
	esac
}

json_signed_number()
{
	case "$1" in
	'' | - | *[!0-9-]* | *-*-* | *[0-9]-*)
		echo "null"
		;;
	*)
		echo "$1"
		;;
	esac
}

json_rc_ok()
{
	case "$1" in
	0)
		echo "true"
		;;
	[1-9]*)
		echo "false"
		;;
	*)
		echo "null"
		;;
	esac
}

kv_read()
{
	kv_file="$1"
	kv_key="$2"
	[ -f "$kv_file" ] || return
	awk -v k="$kv_key" '{
		for (i = 1; i <= NF; i++) {
			split($i, a, "=")
			if (a[1] == k) {
				print a[2]
				exit
			}
		}
	}' "$kv_file" 2>/dev/null
}

kv_read_line()
{
	kv_file="$1"
	kv_key="$2"
	[ -f "$kv_file" ] || return
	grep "^${kv_key}=" "$kv_file" 2>/dev/null | head -n 1 | sed "s/^${kv_key}=//"
}

net_stat_number()
{
	stat_iface="$1"
	stat_name="$2"
	stat_path="/sys/class/net/${stat_iface}/statistics/${stat_name}"
	if [ -n "$stat_iface" ] && [ -r "$stat_path" ]; then
		json_number "$(cat "$stat_path" 2>/dev/null | tr -dc '0-9')"
	else
		echo "null"
	fi
}

html_text()
{
	echo "$1" | tr '\r\n' '  ' | sed 's/<[^>][^>]*>/ /g; s/&nbsp;/ /g; s/&copy;/ /g; s/  */ /g'
}

trim_text()
{
	echo "$1" | sed 's/^ *//; s/ *$//'
}

quectel_metric_field()
{
	metric_line="$1"
	metric_name="$2"
	echo "$metric_line" | awk -v target="$metric_name" -F',' '
	{
		neg_count = 0
		snr_start = 0
		for (i = 1; i <= NF; i++) {
			f = $i
			gsub(/[" \r]/, "", f)
			if (f ~ /^-[0-9]+$/) {
				neg_count++
				if (target == "rsrp" && neg_count == 1) {
					print f
					exit
				}
				if (target == "rsrq" && neg_count == 2) {
					print f
					exit
				}
				if (neg_count == 2 && snr_start == 0) {
					snr_start = i + 1
				}
				if (neg_count == 3) {
					snr_start = i + 1
				}
			}
		}
		if (target == "snr" && snr_start > 0) {
			for (i = snr_start; i <= NF; i++) {
				f = $i
				gsub(/[" \r]/, "", f)
				if (f ~ /^-*[0-9]+$/) {
					print f
					exit
				}
			}
		}
	}'
}

quectel_metric_range()
{
	metric_value="$1"
	metric_min="$2"
	metric_max="$3"

	case "$metric_value" in
	'' | - | *[!0-9-]* | *-*-* | *[0-9]-*)
		return
		;;
	*)
		;;
	esac

	if [ "$metric_value" -lt "$metric_min" ] || [ "$metric_value" -gt "$metric_max" ]; then
		return
	fi
	echo "$metric_value"
}

quectel_qmap_summary()
{
	echo "$1" | grep '+QMAP:' | tr -d '\r"' | sed 's/^.*+QMAP: //; s/ /_/g' | tr '\n' ';' | sed 's/;*$//'
}

usb8_write_diag()
{
	{
		echo "provider=${usb8_provider}"
		echo "signal_bars=${usb8_signal_bars}"
		echo "signal_pct_source=${usb8_signal_pct_source}"
		echo "network=${usb8_network}"
		echo "technology=${usb8_technology}"
		echo "rsrp_dbm=${usb8_rsrp_dbm}"
		echo "snr_db=${usb8_snr_db}"
		echo "band=${usb8_band}"
		echo "apn=${usb8_apn}"
		echo "connection_duration_sec=${usb8_connection_duration_sec}"
		echo "ippt=${usb8_ippt}"
		echo "mtu=${usb8_mtu}"
		echo "management_ip=${usb8_management_ip}"
		echo "ts=${usb8_ts}"
	} >/tmp/uavpal_usb8_diag.tmp
	mv /tmp/uavpal_usb8_diag.tmp /tmp/uavpal_usb8_diag
}

quectel_write_diag()
{
	{
		echo "provider=quectel_rm520n"
		echo "usbnet_mode=${quectel_usbnet_mode_value}"
		echo "network=${quectel_network}"
		echo "technology=${quectel_technology}"
		echo "rat=${quectel_rat}"
		echo "band=${quectel_band}"
		echo "lte_band=${quectel_lte_band}"
		echo "nr_band=${quectel_nr_band}"
		echo "rsrp_dbm=${quectel_rsrp_dbm}"
		echo "rsrq_db=${quectel_rsrq_db}"
		echo "snr_db=${quectel_snr_db}"
		echo "lte_rsrp_dbm=${quectel_lte_rsrp_dbm}"
		echo "lte_rsrq_db=${quectel_lte_rsrq_db}"
		echo "lte_snr_db=${quectel_lte_snr_db}"
		echo "nr_rsrp_dbm=${quectel_nr_rsrp_dbm}"
		echo "nr_rsrq_db=${quectel_nr_rsrq_db}"
		echo "nr_snr_db=${quectel_nr_snr_db}"
		echo "apn=${quectel_apn}"
		echo "expected_apn=${quectel_expected_apn}"
		echo "active_cid=${quectel_active_cid}"
		echo "active_apn=${quectel_active_apn}"
		echo "expected_apn_cid=${quectel_expected_apn_cid}"
		echo "expected_apn_has_ipv4=${quectel_expected_apn_has_ipv4}"
		echo "ippt=${quectel_ippt}"
		echo "mtu=${quectel_mtu}"
		echo "qmap_ippt_nat=${quectel_qmap_ippt_nat}"
		echo "qmap_rule0_cid=${quectel_qmap_rule0_cid}"
		echo "qmap_rule0_enabled=${quectel_qmap_rule0_enabled}"
		echo "qmap_status0_cid=${quectel_qmap_status0_cid}"
		echo "qmap_status0_active=${quectel_qmap_status0_active}"
		echo "qmap_expected=${quectel_qmap_expected}"
		echo "qmap_mpdn_rule=${quectel_qmap_mpdn_rule}"
		echo "qmap_mpdn_status=${quectel_qmap_mpdn_status}"
		echo "setup_error=${quectel_setup_error}"
		echo "ts=${quectel_ts}"
	} >/tmp/uavpal_quectel_diag.tmp
	mv /tmp/uavpal_quectel_diag.tmp /tmp/uavpal_quectel_diag
}

ulogger -s -t uavpal_telemetry "... starting local telemetry loop"

telemetry_loop_pid_file="/tmp/uavpal_telemetry_loop.pid"
telemetry_current_pid=$$
if [ -f "$telemetry_loop_pid_file" ]; then
	telemetry_old_pid=$(cat "$telemetry_loop_pid_file" 2>/dev/null)
	if [ -n "$telemetry_old_pid" ] && [ "$telemetry_old_pid" != "$telemetry_current_pid" ] && kill -0 "$telemetry_old_pid" 2>/dev/null; then
		ulogger -s -t uavpal_telemetry "... telemetry loop already running"
		exit 0
	fi
fi
echo "$telemetry_current_pid" > "$telemetry_loop_pid_file"
trap 'rm -f "$telemetry_loop_pid_file"' EXIT

bat_percent_prev=""
signal_prev=""
signal_profile_prev=""
telemetry_signal_provider=""
usb8_diag_last_ts=0
ztConn_prev=""
zt_state_prev=""
zt_ip_prev=""
loop_counter=0

while true
do
	loop_counter=$((loop_counter + 1))

	# refresh serial control device if it appears later
	if [ -z "$serial_ctrl_dev" ] && [ -f /tmp/serial_ctrl_dev ]; then
		serial_ctrl_dev=$(head -1 /tmp/serial_ctrl_dev | tr -d '\r\n' | tr -d '\n')
	fi

	# refresh battery reading every ~15 seconds
	if [ "$bat_percent_prev" = "" ] || [ $((loop_counter % 3)) -eq 0 ]; then
		bat_percent_candidate=$(ulogcat -d -v csv | grep "Battery percentage" | tail -n 1 | cut -d " " -f 4 | tr -dc '0-9')
		if echo "$bat_percent_candidate" | grep -Eq '^[0-9]+$'; then
			bat_percent_prev="$bat_percent_candidate"
		fi
	fi
	bat_percent="$bat_percent_prev"

	ip_sc2=$(netstat -nu | grep 9988 | head -1 | awk '{ print $5 }' | cut -d ':' -f 1)
	ztConn=""
	mode=""
	signalPercentage=""
	signal=""
	signal_pct_source=""

	# read modem profile first; if no modem profile is active, report Wi-Fi mode
	modem_profile=""
	if [ -f "/tmp/modem_connection_profile" ]; then
		modem_profile=$(cat /tmp/modem_connection_profile | tr -d '\r\n' | tr -d '\n')
	fi

	if [ -z "$modem_profile" ] || [ "$(echo "$ip_sc2" | awk -F. '{print $1"."$2"."$3}')" = "192.168.42" ]; then
		signal="Wi-Fi"
		signal_prev="$signal"
		signal_profile_prev=""
		telemetry_signal_provider=""
		rm -f /tmp/uavpal_usb8_diag
		rm -f /tmp/uavpal_quectel_diag
		ztConn_prev=""
	else
		# detect if zerotier connection is direct vs. relayed
		if [ "$ip_sc2" != "" ]; then
			if [ -z "$ztConn_prev" ] || [ $((loop_counter % 2)) -eq 0 ]; then
				ztDirectCount=$(/data/ftp/uavpal/bin/zerotier-one -q listpeers 2>/dev/null | grep LEAF | grep -v ' - ' | wc -l | tr -d ' ')
				if [ "$ztDirectCount" -gt 0 ]; then
					ztConn=" [D]"
				else
					ztConn=" [R]"
				fi
				ztConn_prev="$ztConn"
			else
				ztConn="$ztConn_prev"
			fi
		else
			ztConn_prev=""
		fi

		refresh_modem_signal=0
		if [ -z "$signal_prev" ] || [ "$signal_profile_prev" != "$modem_profile" ]; then
			refresh_modem_signal=1
			telemetry_signal_provider=""
		elif [ $((loop_counter % 3)) -eq 0 ]; then
			refresh_modem_signal=1
		fi

		if [ "$refresh_modem_signal" -eq "1" ]; then
		huawei_auth_needed=0
		at_only_profile=0
		case "$modem_profile" in
			huawei_stick|generic_ppp)
				at_only_profile=1
				;;
			*)
				;;
		esac

		modem_api_ip=$(ip route | grep default | awk '{print $3}' | head -n 1)
		if [ -z "$modem_api_ip" ]; then
			modem_api_ip="192.168.8.1"
		fi

		# 1) Hi-Link API helper for explicit Hi-Link profile.
		if [ "$modem_profile" = "huawei_hilink" ]; then
			modeStr=$(hilink_api "get" "/api/device/information" | xmllint --xpath 'string(//workmode)' - 2>/dev/null)
			signalBars=$(hilink_api "get" "/api/monitoring/status" | xmllint --xpath 'string(//SignalIcon)' - 2>/dev/null)
			if [ -n "$modeStr" ] || [ -n "$signalBars" ]; then
				telemetry_signal_provider="hilink"
			fi
			if [ -z "$mode" ]; then
				case "$modeStr" in
					LTE)
						mode="4G"
						;;
					NR5G*|5G*)
						mode="5G"
						;;
					WCDMA|UMTS|HSPA*)
						mode="3G"
						;;
					GSM|GPRS|EDGE)
						mode="2G"
						;;
					"")
						;;
					*)
						mode="$modeStr"
						;;
				esac
			fi
			if [ -z "$signalPercentage" ] && echo "$signalBars" | grep -Eq '^[0-9]+$'; then
				signalPercentage=$(echo "$signalBars 20 * p" | /data/ftp/uavpal/bin/dc)%
			fi
		fi

		# 2) Quectel RM520N AT diagnostics for the ECM/generic Ethernet path.
		quectel_marker=""
		if [ -f /tmp/modem_provider ]; then
			quectel_marker=$(head -1 /tmp/modem_provider | tr -d '\r\n' | tr -d '\n')
		fi
		if [ -z "$quectel_marker" ] && [ -f /tmp/modem_usb_id ]; then
			case "$(head -1 /tmp/modem_usb_id | tr -d '\r\n' | tr -d '\n')" in
			2c7c:0801)
				quectel_marker="quectel_rm520n"
				;;
			*)
				;;
			esac
		fi
		if [ "$at_only_profile" -ne "1" ] && [ "$modem_profile" = "generic_ethernet" ] && [ "$quectel_marker" = "quectel_rm520n" ] && { [ -z "$telemetry_signal_provider" ] || [ "$telemetry_signal_provider" = "quectel" ]; }; then
			telemetry_signal_provider="quectel"
			quectel_ts=$(date +%s)
			quectel_diag_ts=$(json_number "$(kv_read_line /tmp/uavpal_quectel_diag ts)")

			quectel_usbnet_mode_value=$(kv_read_line /tmp/uavpal_quectel_diag usbnet_mode)
			quectel_network=$(kv_read_line /tmp/uavpal_quectel_diag network)
			quectel_technology=$(kv_read_line /tmp/uavpal_quectel_diag technology)
			quectel_rat=$(kv_read_line /tmp/uavpal_quectel_diag rat)
			quectel_band=$(kv_read_line /tmp/uavpal_quectel_diag band)
			quectel_lte_band=$(kv_read_line /tmp/uavpal_quectel_diag lte_band)
			quectel_nr_band=$(kv_read_line /tmp/uavpal_quectel_diag nr_band)
			quectel_rsrp_dbm=$(kv_read_line /tmp/uavpal_quectel_diag rsrp_dbm)
			quectel_rsrq_db=$(kv_read_line /tmp/uavpal_quectel_diag rsrq_db)
			quectel_snr_db=$(kv_read_line /tmp/uavpal_quectel_diag snr_db)
			quectel_lte_rsrp_dbm=$(kv_read_line /tmp/uavpal_quectel_diag lte_rsrp_dbm)
			quectel_lte_rsrq_db=$(kv_read_line /tmp/uavpal_quectel_diag lte_rsrq_db)
			quectel_lte_snr_db=$(kv_read_line /tmp/uavpal_quectel_diag lte_snr_db)
			quectel_nr_rsrp_dbm=$(kv_read_line /tmp/uavpal_quectel_diag nr_rsrp_dbm)
			quectel_nr_rsrq_db=$(kv_read_line /tmp/uavpal_quectel_diag nr_rsrq_db)
			quectel_nr_snr_db=$(kv_read_line /tmp/uavpal_quectel_diag nr_snr_db)
			quectel_apn=$(kv_read_line /tmp/uavpal_quectel_diag apn)
			quectel_expected_apn=$(kv_read_line /tmp/uavpal_quectel_diag expected_apn)
			quectel_active_cid=$(kv_read_line /tmp/uavpal_quectel_diag active_cid)
			quectel_active_apn=$(kv_read_line /tmp/uavpal_quectel_diag active_apn)
			quectel_expected_apn_cid=$(kv_read_line /tmp/uavpal_quectel_diag expected_apn_cid)
			quectel_expected_apn_has_ipv4=$(kv_read_line /tmp/uavpal_quectel_diag expected_apn_has_ipv4)
			quectel_ippt=$(kv_read_line /tmp/uavpal_quectel_diag ippt)
			quectel_mtu=$(kv_read_line /tmp/uavpal_quectel_diag mtu)
			quectel_qmap_ippt_nat=$(kv_read_line /tmp/uavpal_quectel_diag qmap_ippt_nat)
			quectel_qmap_rule0_cid=$(kv_read_line /tmp/uavpal_quectel_diag qmap_rule0_cid)
			quectel_qmap_rule0_enabled=$(kv_read_line /tmp/uavpal_quectel_diag qmap_rule0_enabled)
			quectel_qmap_status0_cid=$(kv_read_line /tmp/uavpal_quectel_diag qmap_status0_cid)
			quectel_qmap_status0_active=$(kv_read_line /tmp/uavpal_quectel_diag qmap_status0_active)
			quectel_qmap_expected=$(kv_read_line /tmp/uavpal_quectel_diag qmap_expected)
			quectel_qmap_mpdn_rule=$(kv_read_line /tmp/uavpal_quectel_diag qmap_mpdn_rule)
			quectel_qmap_mpdn_status=$(kv_read_line /tmp/uavpal_quectel_diag qmap_mpdn_status)
			quectel_setup_error=$(kv_read /tmp/uavpal_quectel_setup_diag error)

			quectel_diag_refresh=0
			if [ "$quectel_diag_ts" = "null" ]; then
				quectel_diag_refresh=1
			elif [ $((quectel_ts - quectel_diag_ts)) -ge 30 ]; then
				quectel_diag_refresh=1
			fi
			if [ "$quectel_diag_refresh" -eq "1" ]; then
				quectel_usbnet_mode_value=$(quectel_usbnet_mode)
				quectel_qnwinfo=$(at_command "AT+QNWINFO" "OK" "2")
				quectel_qeng=$(at_command 'AT+QENG="servingcell"' "OK" "2")
				quectel_cgdcont=$(at_command "AT+CGDCONT?" "OK" "2")
				quectel_cgpaddr=$(at_command "AT+CGPADDR" "OK" "2")
				quectel_mpdn_rule=$(at_command 'AT+QMAP="MPDN_rule"' "OK" "2")
				quectel_mpdn_status=$(at_command 'AT+QMAP="mPDN_status"' "OK" "2")
				quectel_ippt_nat=$(at_command 'AT+QMAP="IPPT_NAT"' "OK" "2")

				quectel_qnw_line=$(echo "$quectel_qnwinfo" | grep '+QNWINFO:' | tail -n 1 | tr -d '\r')
				quectel_rat=$(echo "$quectel_qnw_line" | sed -n 's/.*+QNWINFO: "\([^"]*\)".*/\1/p')
				quectel_network=$(echo "$quectel_qnw_line" | awk -F'"' '/\+QNWINFO:/ { print $4; exit }')
				quectel_band=$(echo "$quectel_qnw_line" | awk -F'"' '/\+QNWINFO:/ { print $6; exit }')
				quectel_technology="$quectel_rat"
				case "$quectel_rat" in
				*NR* | *5G*)
					quectel_technology="5G"
					;;
				*LTE*)
					quectel_technology="LTE"
					;;
				*)
					;;
				esac

				quectel_lte_band=""
				quectel_nr_band=""
				case "$quectel_band" in
				*LTE*)
					quectel_lte_band="$quectel_band"
					;;
				*NR* | *5G*)
					quectel_nr_band="$quectel_band"
					;;
				*)
					;;
				esac

				quectel_lte_line=$(echo "$quectel_qeng" | grep '+QENG:' | grep '"LTE"' | head -n 1 | tr -d '\r')
				quectel_nr_line=$(echo "$quectel_qeng" | grep '+QENG:' | grep -i 'NR5G' | head -n 1 | tr -d '\r')
				quectel_lte_rsrp_dbm=$(quectel_metric_field "$quectel_lte_line" rsrp)
				quectel_lte_rsrq_db=$(quectel_metric_field "$quectel_lte_line" rsrq)
				quectel_lte_snr_db=$(quectel_metric_field "$quectel_lte_line" snr)
				quectel_nr_rsrp_dbm=$(quectel_metric_field "$quectel_nr_line" rsrp)
				quectel_nr_rsrq_db=$(quectel_metric_field "$quectel_nr_line" rsrq)
				quectel_nr_snr_db=$(quectel_metric_field "$quectel_nr_line" snr)
				quectel_lte_rsrp_dbm=$(quectel_metric_range "$quectel_lte_rsrp_dbm" -160 -40)
				quectel_lte_rsrq_db=$(quectel_metric_range "$quectel_lte_rsrq_db" -40 0)
				quectel_lte_snr_db=$(quectel_metric_range "$quectel_lte_snr_db" -30 60)
				quectel_nr_rsrp_dbm=$(quectel_metric_range "$quectel_nr_rsrp_dbm" -160 -40)
				quectel_nr_rsrq_db=$(quectel_metric_range "$quectel_nr_rsrq_db" -40 0)
				quectel_nr_snr_db=$(quectel_metric_range "$quectel_nr_snr_db" -30 60)

				quectel_rsrp_dbm="$quectel_nr_rsrp_dbm"
				quectel_rsrq_db="$quectel_nr_rsrq_db"
				quectel_snr_db="$quectel_nr_snr_db"
				if [ -z "$quectel_rsrp_dbm" ]; then
					quectel_rsrp_dbm="$quectel_lte_rsrp_dbm"
				fi
				if [ -z "$quectel_rsrq_db" ]; then
					quectel_rsrq_db="$quectel_lte_rsrq_db"
				fi
				if [ -z "$quectel_snr_db" ]; then
					quectel_snr_db="$quectel_lte_snr_db"
				fi

				quectel_expected_apn="$(conf_read apn)"
				quectel_expected_apn_cid=""
				quectel_expected_apn_has_ipv4=""
				if [ -n "$quectel_expected_apn" ]; then
					quectel_expected_apn_cid=$(quectel_cgdcont_cid_for_apn "$quectel_cgdcont" "$quectel_expected_apn")
					quectel_expected_apn_ipv4=$(quectel_cgpaddr_ipv4_for_cid "$quectel_cgpaddr" "$quectel_expected_apn_cid")
					if [ -n "$quectel_expected_apn_ipv4" ]; then
						quectel_expected_apn_has_ipv4=1
					else
						quectel_expected_apn_has_ipv4=0
					fi
				fi
				quectel_qmap_rule0_cid=$(quectel_qmap_rule_cid "$quectel_mpdn_rule" 0)
				quectel_qmap_rule0_enabled=$(quectel_qmap_rule_enabled "$quectel_mpdn_rule" 0)
				quectel_qmap_status0_cid=$(quectel_qmap_status_cid "$quectel_mpdn_status" 0)
				quectel_qmap_status0_active=$(quectel_qmap_status_active "$quectel_mpdn_status" 0)
				quectel_active_cid=""
				if [ "$quectel_qmap_status0_active" = "1" ] && [ -n "$quectel_qmap_status0_cid" ] && [ "$quectel_qmap_status0_cid" != "0" ]; then
					quectel_active_cid="$quectel_qmap_status0_cid"
				elif [ "$quectel_qmap_rule0_enabled" = "1" ] && [ -n "$quectel_qmap_rule0_cid" ] && [ "$quectel_qmap_rule0_cid" != "0" ]; then
					quectel_active_cid="$quectel_qmap_rule0_cid"
				elif [ "$quectel_expected_apn_has_ipv4" = "1" ]; then
					quectel_active_cid="$quectel_expected_apn_cid"
				else
					quectel_active_cid=$(quectel_cgdcont_first_data_cid "$quectel_cgdcont")
				fi
				quectel_active_apn=$(quectel_cgdcont_apn_for_cid "$quectel_cgdcont" "$quectel_active_cid")
				quectel_apn="$quectel_active_apn"
				if [ -z "$quectel_apn" ]; then
					quectel_apn=$(echo "$quectel_cgdcont" | awk -F'"' '/\+CGDCONT:/ { apn=$4; if (apn != "" && apn !~ /^ims$/ && apn !~ /emergency/) { print apn; exit } }')
				fi
				if [ -z "$quectel_expected_apn" ]; then
					quectel_qmap_expected="unknown_expected_apn"
				elif [ -z "$quectel_expected_apn_cid" ]; then
					quectel_qmap_expected="missing_expected_apn_cid"
				elif [ "$quectel_qmap_status0_active" = "1" ] && [ "$quectel_qmap_status0_cid" != "$quectel_expected_apn_cid" ]; then
					quectel_qmap_expected="active_mismatch"
				elif [ "$quectel_qmap_rule0_cid" = "$quectel_expected_apn_cid" ] && [ "$quectel_qmap_rule0_enabled" = "1" ]; then
					quectel_qmap_expected="ok"
				elif [ "$quectel_qmap_rule0_cid" = "$quectel_expected_apn_cid" ]; then
					quectel_qmap_expected="rule_disabled"
				elif [ -z "$quectel_qmap_rule0_cid" ] || [ "$quectel_qmap_rule0_cid" = "0" ]; then
					quectel_qmap_expected="no_rule0"
				else
					quectel_qmap_expected="rule_mismatch"
				fi
				quectel_qmap_ippt_nat=$(echo "$quectel_ippt_nat" | sed -n 's/.*+QMAP: "IPPT_NAT",\([0-9][0-9]*\).*/\1/p' | tail -n 1)
				quectel_qmap_mpdn_rule=$(quectel_qmap_summary "$quectel_mpdn_rule")
				quectel_qmap_mpdn_status=$(quectel_qmap_summary "$quectel_mpdn_status")

				quectel_iface=""
				if [ -f /tmp/modem_iface ]; then
					quectel_iface=$(head -1 /tmp/modem_iface | tr -d '\r\n' | tr -d '\n')
				fi
				quectel_mtu=""
				if [ -n "$quectel_iface" ] && [ -r "/sys/class/net/${quectel_iface}/mtu" ]; then
					quectel_mtu=$(cat "/sys/class/net/${quectel_iface}/mtu" 2>/dev/null | tr -dc '0-9')
				fi

				quectel_ippt=""
				quectel_modem_ip=""
				quectel_modem_gateway=""
				if [ -f /tmp/modem_ip ]; then
					quectel_modem_ip=$(head -1 /tmp/modem_ip | tr -d '\r\n' | tr -d '\n')
				fi
				if [ -f /tmp/modem_gateway_ip ]; then
					quectel_modem_gateway=$(head -1 /tmp/modem_gateway_ip | tr -d '\r\n' | tr -d '\n')
				fi
				if [ -n "$quectel_modem_ip$quectel_modem_gateway" ]; then
					if echo "$quectel_modem_ip $quectel_modem_gateway" | grep -q '192\.168\.225\.'; then
						quectel_ippt=0
					else
						quectel_ippt=1
					fi
				fi

				quectel_write_diag
			fi

			if [ -z "$mode" ]; then
				case "$quectel_technology$quectel_rat" in
				*5G* | *NR*)
					mode="5G"
					;;
				*LTE*)
					mode="4G"
					;;
				*)
					;;
				esac
			fi
			if [ -z "$signalPercentage" ]; then
				signal_pct_source="quectel_at"
			fi
		fi

		# 3) Prefer Inseego USB8-style status API first for generic Ethernet.
		if [ "$at_only_profile" -ne "1" ] && [ "$modem_profile" = "generic_ethernet" ] && { [ -z "$telemetry_signal_provider" ] || [ "$telemetry_signal_provider" = "usb8" ]; } && { [ -z "$mode" ] || [ -z "$signalPercentage" ]; }; then
			usb8_status_json=$(/data/ftp/uavpal/bin/curl -q -m 1 -s "http://192.168.1.1/srv/status" 2>/dev/null)
			if echo "$usb8_status_json" | grep -q '"statusData"'; then
				telemetry_signal_provider="usb8"
				usb8_provider="inseego_usb8"
				usb8_management_ip="192.168.1.1"
				usb8_signal_pct_source="usb8_bars"
				usb8_ts=$(date +%s)
				modeStrUsb8=$(echo "$usb8_status_json" | sed -n 's/.*"statusBarTechnology":"\([^"]*\)".*/\1/p' | head -n 1)
				signalBarsUsb8=$(echo "$usb8_status_json" | sed -n 's/.*"statusBarSignalBars":"\([^"]*\)".*/\1/p' | head -n 1)
				usb8_network=$(trim_text "$(echo "$usb8_status_json" | sed -n 's/.*"statusBarNetwork":"\([^"]*\)".*/\1/p' | head -n 1)")
				usb8_technology="$modeStrUsb8"
				usb8_connection_duration_sec=$(echo "$usb8_status_json" | sed -n 's/.*"statusBarConnectionDuration":"*\([0-9][0-9]*\)"*.*/\1/p' | head -n 1)
				usb8_signal_bars=$(echo "$signalBarsUsb8" | tr -dc '0-9')

				usb8_rsrp_dbm=$(kv_read_line /tmp/uavpal_usb8_diag rsrp_dbm)
				usb8_snr_db=$(kv_read_line /tmp/uavpal_usb8_diag snr_db)
				usb8_band=$(kv_read_line /tmp/uavpal_usb8_diag band)
				usb8_apn=$(kv_read_line /tmp/uavpal_usb8_diag apn)
				usb8_diag_refresh=0
				if [ "$usb8_diag_last_ts" = "" ] || [ "$usb8_diag_last_ts" -le 0 ]; then
					usb8_diag_refresh=1
				elif [ $((usb8_ts - usb8_diag_last_ts)) -ge 120 ]; then
					usb8_diag_refresh=1
				fi
				if [ "$usb8_diag_refresh" -eq "1" ]; then
					usb8_diag_html=$(/data/ftp/uavpal/bin/curl -q -m 1 -s "http://192.168.1.1/diagnostics/" 2>/dev/null)
					usb8_diag_text=$(html_text "$usb8_diag_html")
					usb8_rsrp_candidate=$(echo "$usb8_diag_text" | sed -n 's/.*Signal Strength (RSRP)[^0-9-]*\(-*[0-9][0-9]*\)[^0-9-]*dBm.*/\1/p' | head -n 1)
					usb8_snr_candidate=$(echo "$usb8_diag_text" | sed -n 's/.*SNR[^0-9-]*\(-*[0-9][0-9]*\)[^0-9-]*dB.*/\1/p' | head -n 1)
					usb8_band_candidate=$(echo "$usb8_diag_text" | sed -n 's/.* Band[^A-Za-z0-9]*\([^ ]*\)[ ]*APN.*/\1/p' | head -n 1)
					usb8_apn_candidate=$(echo "$usb8_diag_text" | sed -n 's/.* APN[^A-Za-z0-9._-]*\([A-Za-z0-9._-][A-Za-z0-9._-]*\).*/\1/p' | head -n 1)
					[ -n "$usb8_rsrp_candidate" ] && usb8_rsrp_dbm="$usb8_rsrp_candidate"
					[ -n "$usb8_snr_candidate" ] && usb8_snr_db="$usb8_snr_candidate"
					[ -n "$usb8_band_candidate" ] && usb8_band=$(trim_text "$usb8_band_candidate")
					[ -n "$usb8_apn_candidate" ] && usb8_apn=$(trim_text "$usb8_apn_candidate")
					usb8_diag_last_ts="$usb8_ts"
				fi

				usb8_iface=""
				if [ -f /tmp/modem_iface ]; then
					usb8_iface=$(head -1 /tmp/modem_iface | tr -d '\r\n' | tr -d '\n')
				fi
				usb8_mtu=""
				if [ -n "$usb8_iface" ] && [ -r "/sys/class/net/${usb8_iface}/mtu" ]; then
					usb8_mtu=$(cat "/sys/class/net/${usb8_iface}/mtu" 2>/dev/null | tr -dc '0-9')
				fi
				usb8_ippt=""
				usb8_modem_ip=""
				usb8_modem_gateway=""
				if [ -f /tmp/modem_ip ]; then
					usb8_modem_ip=$(head -1 /tmp/modem_ip | tr -d '\r\n' | tr -d '\n')
				fi
				if [ -f /tmp/modem_gateway_ip ]; then
					usb8_modem_gateway=$(head -1 /tmp/modem_gateway_ip | tr -d '\r\n' | tr -d '\n')
				fi
				if [ -n "$usb8_modem_ip$usb8_modem_gateway" ]; then
					if echo "$usb8_modem_ip $usb8_modem_gateway" | grep -q '192\.168\.1\.'; then
						usb8_ippt=0
					else
						usb8_ippt=1
					fi
				fi

				usb8_write_diag

				if [ -z "$mode" ]; then
					case "$modeStrUsb8" in
						LTE|LTE+|LTE\ CA)
							mode="4G"
							;;
						NR5G*|5G*)
							mode="5G"
							;;
						WCDMA|UMTS|HSPA*|EVDO*|CDMA*)
							mode="3G"
							;;
						GSM|GPRS|EDGE|1XRTT)
							mode="2G"
							;;
						"")
							;;
						*)
							mode="$modeStrUsb8"
							;;
					esac
				fi
				if [ -z "$signalPercentage" ]; then
					signalBarsUsb8Num="$usb8_signal_bars"
					if echo "$signalBarsUsb8Num" | grep -Eq '^[0-9]+$'; then
						signal_pct_source="usb8_bars"
						if [ "$signalBarsUsb8Num" -le 4 ]; then
							signalPercentage=$(echo "$signalBarsUsb8Num 25 * p" | /data/ftp/uavpal/bin/dc)%
						elif [ "$signalBarsUsb8Num" -le 5 ]; then
							signalPercentage=$(echo "$signalBarsUsb8Num 20 * p" | /data/ftp/uavpal/bin/dc)%
						elif [ "$signalBarsUsb8Num" -le 100 ]; then
							signalPercentage="${signalBarsUsb8Num}%"
						fi
					fi
				fi
			fi
		fi

		# 4) Generic ZTE-style hostless modem API (clone modems).
		if [ "$at_only_profile" -ne "1" ] && { [ -z "$telemetry_signal_provider" ] || [ "$telemetry_signal_provider" = "zte" ]; } && { [ -z "$mode" ] || [ -z "$signalPercentage" ]; }; then
			modem_info_json=$(/data/ftp/uavpal/bin/curl -q -m 2 -s "http://${modem_api_ip}/reqproc/proc_get?isTest=false&multi_data=1&cmd=network_type,signalbar,signalbar_ex,ppp_status" 2>/dev/null)
			modeStr2=$(echo "$modem_info_json" | sed -n 's/.*"network_type":"\([^"]*\)".*/\1/p' | head -n 1)
			signalBars2=$(echo "$modem_info_json" | sed -n 's/.*"signalbar":"\([^"]*\)".*/\1/p' | head -n 1)
			if [ -n "$modeStr2" ] || [ -n "$signalBars2" ]; then
				telemetry_signal_provider="zte"
			fi
			if [ -z "$mode" ]; then
				case "$modeStr2" in
					LTE|FDD\ LTE|TDD\ LTE)
						mode="4G"
						;;
					NR5G*|5G*)
						mode="5G"
						;;
					WCDMA|UMTS|HSPA*)
						mode="3G"
						;;
					GSM|GPRS|EDGE)
						mode="2G"
						;;
					"")
						;;
					*)
						mode="$modeStr2"
						;;
				esac
			fi
			if [ -z "$signalPercentage" ] && echo "$signalBars2" | grep -Eq '^[0-9]+$'; then
				signalPercentage=$(echo "$signalBars2 20 * p" | /data/ftp/uavpal/bin/dc)%
			fi
		fi

		# 5) Direct Huawei API probe (unauthenticated).
		if [ "$at_only_profile" -ne "1" ] && { [ -z "$telemetry_signal_provider" ] || [ "$telemetry_signal_provider" = "hilink_direct" ]; } && { [ -z "$mode" ] || [ -z "$signalPercentage" ]; }; then
			hilink_info_xml=$(/data/ftp/uavpal/bin/curl -q -m 2 -s "http://${modem_api_ip}/api/device/information" 2>/dev/null)
			hilink_status_xml=$(/data/ftp/uavpal/bin/curl -q -m 2 -s "http://${modem_api_ip}/api/monitoring/status" 2>/dev/null)
			if echo "$hilink_info_xml$hilink_status_xml" | grep -q "<response>"; then
				telemetry_signal_provider="hilink_direct"
			fi

			if echo "$hilink_info_xml" | grep -q "<error>"; then
				hilink_info_err=$(echo "$hilink_info_xml" | xmllint --xpath 'string(//error/code)' - 2>/dev/null)
				if [ "$hilink_info_err" = "100003" ] || [ "$hilink_info_err" = "125002" ]; then
					huawei_auth_needed=1
				fi
			fi
			if echo "$hilink_status_xml" | grep -q "<error>"; then
				hilink_status_err=$(echo "$hilink_status_xml" | xmllint --xpath 'string(//error/code)' - 2>/dev/null)
				if [ "$hilink_status_err" = "100003" ] || [ "$hilink_status_err" = "125002" ]; then
					huawei_auth_needed=1
				fi
			fi

			modeStr3=$(echo "$hilink_info_xml" | xmllint --xpath 'string(//workmode)' - 2>/dev/null)
			signalBars3=$(echo "$hilink_status_xml" | xmllint --xpath 'string(//SignalIcon)' - 2>/dev/null)
			if [ -z "$mode" ]; then
				case "$modeStr3" in
					LTE)
						mode="4G"
						;;
					NR5G*|5G*)
						mode="5G"
						;;
					WCDMA|UMTS|HSPA*)
						mode="3G"
						;;
					GSM|GPRS|EDGE)
						mode="2G"
						;;
					"")
						;;
					*)
						mode="$modeStr3"
						;;
				esac
			fi
			if [ -z "$signalPercentage" ] && echo "$signalBars3" | grep -Eq '^[0-9]+$'; then
				signalPercentage=$(echo "$signalBars3 20 * p" | /data/ftp/uavpal/bin/dc)%
			fi
		fi

		# 6) Authenticated Huawei API retry for generic_ethernet when telemetry endpoints are protected.
		if [ "$at_only_profile" -ne "1" ] && [ "$modem_profile" = "generic_ethernet" ] && { [ -z "$telemetry_signal_provider" ] || [ "$telemetry_signal_provider" = "hilink_auth" ]; } && [ "$huawei_auth_needed" -eq "1" ]; then
			if [ -z "$mode" ] || [ -z "$signalPercentage" ]; then
				saved_hilink_router_ip=""
				had_hilink_router_ip=0
				if [ -f "/tmp/hilink_router_ip" ]; then
					saved_hilink_router_ip=$(cat /tmp/hilink_router_ip)
					had_hilink_router_ip=1
				fi

				echo "$modem_api_ip" >/tmp/hilink_router_ip
				touch /tmp/hilink_login_required
				auth_info_xml=$(hilink_api "get" "/api/device/information")
				auth_status_xml=$(hilink_api "get" "/api/monitoring/status")
				if echo "$auth_info_xml$auth_status_xml" | grep -q "<response>"; then
					telemetry_signal_provider="hilink_auth"
				fi
				rm -f /tmp/hilink_login_required

				if [ "$had_hilink_router_ip" -eq "1" ]; then
					echo "$saved_hilink_router_ip" >/tmp/hilink_router_ip
				else
					rm -f /tmp/hilink_router_ip
				fi

				modeStr4=$(echo "$auth_info_xml" | xmllint --xpath 'string(//workmode)' - 2>/dev/null)
				signalBars4=$(echo "$auth_status_xml" | xmllint --xpath 'string(//SignalIcon)' - 2>/dev/null)
				if [ -z "$mode" ]; then
					case "$modeStr4" in
						LTE)
							mode="4G"
							;;
						NR5G*|5G*)
							mode="5G"
							;;
						WCDMA|UMTS|HSPA*)
							mode="3G"
							;;
						GSM|GPRS|EDGE)
							mode="2G"
							;;
						"")
							;;
						*)
							mode="$modeStr4"
							;;
					esac
				fi
				if [ -z "$signalPercentage" ] && echo "$signalBars4" | grep -Eq '^[0-9]+$'; then
					signalPercentage=$(echo "$signalBars4 20 * p" | /data/ftp/uavpal/bin/dc)%
				fi
			fi
		fi

		# 7) Serial AT fallback (PPP sticks and mixed enumerations).
		if { [ -z "$telemetry_signal_provider" ] || [ "$telemetry_signal_provider" = "at" ]; } && { [ -z "$mode" ] || [ -z "$signalPercentage" ]; }; then
			if [ -z "$serial_ctrl_dev" ] || [ ! -c "/dev/${serial_ctrl_dev}" ]; then
				for dev in /dev/ttyUSB* /dev/ttyACM*; do
					if [ -c "$dev" ]; then
						serial_ctrl_dev=$(basename "$dev")
						break
					fi
				done
			fi
			if [ -n "$serial_ctrl_dev" ] && [ -c "/dev/${serial_ctrl_dev}" ]; then
				if [ -z "$mode" ]; then
					modeString=$(at_command "AT\^SYSINFOEX" "OK" "1" | grep "SYSINFOEX:" | tail -n 1)
					modeNum=$(echo "$modeString" | cut -d "," -f 8 | tr -dc '0-9')
					if echo "$modeNum" | grep -Eq '^[0-9]+$'; then
						if [ "$modeNum" -ge 101 ]; then
							mode="4G"
						elif [ "$modeNum" -ge 23 ] && [ "$modeNum" -le 65 ]; then
							mode="3G"
						elif [ "$modeNum" -ge 1 ] && [ "$modeNum" -le 3 ]; then
							mode="2G"
						fi
					fi
				fi
				if [ -z "$mode" ]; then
					copsString=$(at_command "AT+COPS?" "OK" "1" | grep "+COPS:" | tail -n 1)
					copsAct=$(echo "$copsString" | awk -F',' '{ gsub(/[^0-9]/, "", $4); print $4 }')
					if echo "$copsAct" | grep -Eq '^[0-9]+$'; then
						case "$copsAct" in
						7|9|10)
							mode="4G"
							;;
						11|12|13)
							mode="5G"
							;;
						2|4|5|6)
							mode="3G"
							;;
						0|1|3|8)
							mode="2G"
							;;
						*)
							;;
						esac
					fi
				fi
				if [ -z "$mode" ]; then
					hcsqString=$(at_command "AT\^HCSQ?" "OK" "1" | grep "HCSQ:" | tail -n 1)
					hcsqRat=$(echo "$hcsqString" | sed -n 's/.*"\([^"]*\)".*/\1/p' | tr '[:lower:]' '[:upper:]')
					case "$hcsqRat" in
					LTE)
						mode="4G"
						;;
					NR5G*|5G*)
						mode="5G"
						;;
					WCDMA|UMTS|HSPA*)
						mode="3G"
						;;
					GSM|GPRS|EDGE)
						mode="2G"
						;;
					*)
						;;
					esac
				fi
				if [ -z "$signalPercentage" ]; then
					signalString=$(at_command "AT+CSQ" "OK" "1" | grep "CSQ:" | tail -n 1)
					signalRSSI=$(echo "$signalString" | awk '{print $2}' | cut -d ',' -f 1 | tr -dc '0-9')
					if echo "$signalRSSI" | grep -Eq '^[0-9]+$' && [ "$signalRSSI" -ge 0 ] && [ "$signalRSSI" -le 31 ]; then
						signalPercentage=$(printf "%.0f\n" $(/data/ftp/uavpal/bin/dc -e "$(echo "$signalRSSI") 1 + 3.13 * p"))%
					fi
				fi
				if [ -n "$mode" ] || [ -n "$signalPercentage" ]; then
					telemetry_signal_provider="at"
				fi
			fi
		fi

		if [ -z "$mode" ]; then
			mode="Cell"
		fi
		if [ -z "$signalPercentage" ]; then
			signalPercentage="n/a"
		fi
		signal="$mode/$signalPercentage"
		if [ "$signal" = "Cell/n/a" ]; then
			telemetry_signal_provider=""
			if [ -n "$signal_prev" ] && [ "$signal_profile_prev" = "$modem_profile" ]; then
				signal="$signal_prev"
			fi
		else
			signal_prev="$signal"
			signal_profile_prev="$modem_profile"
		fi
		else
			signal="$signal_prev"
		fi
	fi

	telemetry_mode=$(echo "$signal" | awk -F'/' '{print $1}')
	if [ -z "$telemetry_mode" ]; then
		telemetry_mode="Cell"
	fi

	telemetry_signal_raw=$(echo "$signal" | awk -F'/' 'NF>1 {print $2}')
	telemetry_modem_signal_pct="null"
	if echo "$telemetry_signal_raw" | grep -Eq '^[0-9]+%$'; then
		telemetry_modem_signal_pct=$(echo "$telemetry_signal_raw" | tr -dc '0-9')
	fi

	telemetry_plane_battery_pct="null"
	if echo "$bat_percent" | grep -Eq '^[0-9]+$'; then
		telemetry_plane_battery_pct="$bat_percent"
	fi

	telemetry_zt=""
	case "$ztConn" in
		*"[D]"*) telemetry_zt="D" ;;
		*"[R]"*) telemetry_zt="R" ;;
	esac

	telemetry_iface=""
	if [ -f /tmp/modem_iface ]; then
		telemetry_iface=$(head -1 /tmp/modem_iface | tr -d '\r\n' | tr -d '\n')
	fi
	if [ -z "$telemetry_iface" ]; then
		telemetry_iface=$(ip route 2>/dev/null | awk '$1=="default" { for (i=1; i<=NF; i++) if ($i=="dev") { print $(i+1); exit } }')
	fi
	iface_rx_bytes=$(net_stat_number "$telemetry_iface" rx_bytes)
	iface_tx_bytes=$(net_stat_number "$telemetry_iface" tx_bytes)

	telemetry_gateway=""
	if [ -f /tmp/modem_gateway_ip ]; then
		telemetry_gateway=$(head -1 /tmp/modem_gateway_ip | tr -d '\r\n' | tr -d '\n')
	elif [ -f /tmp/hilink_router_ip ]; then
		telemetry_gateway=$(head -1 /tmp/hilink_router_ip | tr -d '\r\n' | tr -d '\n')
	fi
	if [ -z "$telemetry_gateway" ]; then
		telemetry_gateway=$(ip route 2>/dev/null | awk '$1=="default" { print $3; exit }')
	fi

	zt_state=""
	zt_ip=""
	if [ -z "$zt_state_prev$zt_ip_prev" ] || [ $((loop_counter % 2)) -eq 0 ]; then
		zt_network_line=$(/data/ftp/uavpal/bin/zerotier-one -q listnetworks 2>/dev/null | grep "$(conf_read zt_networkid)" | head -n 1)
		if [ -n "$zt_network_line" ]; then
			zt_state_prev=$(echo "$zt_network_line" | awk '{ for (i=1; i<=NF; i++) if ($i=="OK" || $i=="ACCESS_DENIED" || $i=="REQUESTING_CONFIGURATION" || $i=="NOT_FOUND" || $i=="PORT_ERROR") { print $i; exit } }')
			zt_ip_prev=$(echo "$zt_network_line" | awk '{ for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) { gsub(/,.*/, "", $i); print $i; exit } }')
		else
			zt_state_prev=""
			zt_ip_prev=""
		fi
	fi
	zt_state="$zt_state_prev"
	zt_ip="$zt_ip_prev"

	queue_ok=$(json_bool "$(kv_read /tmp/uavpal_queue_diag ok)")
	route_ok=$(json_bool "$(kv_read /tmp/uavpal_route_diag ok)")

	reconnect_handler=$(kv_read /tmp/uavpal_reconnect_diag handler)
	reconnect_state=$(kv_read /tmp/uavpal_reconnect_diag state)
	reconnect_fail_count=$(json_number "$(kv_read /tmp/uavpal_reconnect_diag fail_count)")
	reconnect_backoff_sec=$(json_number "$(kv_read /tmp/uavpal_reconnect_diag backoff_sec)")
	reconnect_link_ok=$(json_rc_ok "$(kv_read /tmp/uavpal_reconnect_diag link_ok)")
	reconnect_internet_raw=$(kv_read /tmp/uavpal_reconnect_diag internet_ok)
	reconnect_internet_ok=$(json_rc_ok "$reconnect_internet_raw")
	if ps | grep '[t]elnetd' >/dev/null 2>&1; then
		telnetd_running=true
	else
		telnetd_running=false
	fi

	telemetry_mode_escaped=$(json_escape "$telemetry_mode")
	telemetry_profile_escaped=$(json_escape "$modem_profile")
	telemetry_iface_escaped=$(json_escape "$telemetry_iface")
	telemetry_gateway_escaped=$(json_escape "$telemetry_gateway")
	telemetry_zt_escaped=$(json_escape "$telemetry_zt")
	telemetry_zt_state_escaped=$(json_escape "$zt_state")
	telemetry_zt_ip_escaped=$(json_escape "$zt_ip")
	telemetry_reconnect_handler_escaped=$(json_escape "$reconnect_handler")
	telemetry_reconnect_state_escaped=$(json_escape "$reconnect_state")
	telemetry_ts=$(date +%s)

	modem_provider=""
	modem_signal_bars="null"
	modem_signal_pct_source=""
	modem_rsrp_dbm="null"
	modem_snr_db="null"
	modem_band=""
	modem_network=""
	modem_technology=""
	modem_apn=""
	modem_active_apn=""
	modem_expected_apn=""
	modem_active_cid="null"
	modem_expected_apn_cid="null"
	modem_expected_apn_has_ipv4="null"
	modem_connection_duration_sec="null"
	modem_ippt="null"
	modem_mtu="null"
	modem_management_ip=""
	modem_usbnet_mode="null"
	modem_rsrq_db="null"
	modem_rat=""
	modem_lte_band=""
	modem_nr_band=""
	modem_lte_rsrp_dbm="null"
	modem_lte_rsrq_db="null"
	modem_lte_snr_db="null"
	modem_nr_rsrp_dbm="null"
	modem_nr_rsrq_db="null"
	modem_nr_snr_db="null"
	modem_qmap_ippt_nat="null"
	modem_qmap_rule0_cid="null"
	modem_qmap_rule0_enabled="null"
	modem_qmap_status0_cid="null"
	modem_qmap_status0_active="null"
	modem_qmap_expected=""
	modem_qmap_mpdn_rule=""
	modem_qmap_mpdn_status=""
	modem_setup_error=""
	quectel_diag_ts=$(json_number "$(kv_read_line /tmp/uavpal_quectel_diag ts)")
	if [ "$modem_profile" = "generic_ethernet" ] && [ "$quectel_diag_ts" != "null" ] && [ $((telemetry_ts - quectel_diag_ts)) -le 60 ]; then
		if [ "$(kv_read_line /tmp/uavpal_quectel_diag provider)" = "quectel_rm520n" ]; then
			modem_provider="quectel_rm520n"
			modem_signal_pct_source="quectel_at"
			modem_usbnet_mode=$(json_number "$(kv_read_line /tmp/uavpal_quectel_diag usbnet_mode)")
			modem_rsrp_dbm=$(json_signed_number "$(kv_read_line /tmp/uavpal_quectel_diag rsrp_dbm)")
			modem_rsrq_db=$(json_signed_number "$(kv_read_line /tmp/uavpal_quectel_diag rsrq_db)")
			modem_snr_db=$(json_signed_number "$(kv_read_line /tmp/uavpal_quectel_diag snr_db)")
			modem_band=$(kv_read_line /tmp/uavpal_quectel_diag band)
			modem_network=$(kv_read_line /tmp/uavpal_quectel_diag network)
			modem_technology=$(kv_read_line /tmp/uavpal_quectel_diag technology)
			modem_rat=$(kv_read_line /tmp/uavpal_quectel_diag rat)
			modem_lte_band=$(kv_read_line /tmp/uavpal_quectel_diag lte_band)
			modem_nr_band=$(kv_read_line /tmp/uavpal_quectel_diag nr_band)
			modem_lte_rsrp_dbm=$(json_signed_number "$(kv_read_line /tmp/uavpal_quectel_diag lte_rsrp_dbm)")
			modem_lte_rsrq_db=$(json_signed_number "$(kv_read_line /tmp/uavpal_quectel_diag lte_rsrq_db)")
			modem_lte_snr_db=$(json_signed_number "$(kv_read_line /tmp/uavpal_quectel_diag lte_snr_db)")
			modem_nr_rsrp_dbm=$(json_signed_number "$(kv_read_line /tmp/uavpal_quectel_diag nr_rsrp_dbm)")
			modem_nr_rsrq_db=$(json_signed_number "$(kv_read_line /tmp/uavpal_quectel_diag nr_rsrq_db)")
			modem_nr_snr_db=$(json_signed_number "$(kv_read_line /tmp/uavpal_quectel_diag nr_snr_db)")
			modem_apn=$(kv_read_line /tmp/uavpal_quectel_diag apn)
			modem_active_apn=$(kv_read_line /tmp/uavpal_quectel_diag active_apn)
			modem_expected_apn=$(kv_read_line /tmp/uavpal_quectel_diag expected_apn)
			modem_active_cid=$(json_number "$(kv_read_line /tmp/uavpal_quectel_diag active_cid)")
			modem_expected_apn_cid=$(json_number "$(kv_read_line /tmp/uavpal_quectel_diag expected_apn_cid)")
			modem_expected_apn_has_ipv4=$(json_bool "$(kv_read_line /tmp/uavpal_quectel_diag expected_apn_has_ipv4)")
			modem_ippt=$(json_bool "$(kv_read_line /tmp/uavpal_quectel_diag ippt)")
			modem_mtu=$(json_number "$(kv_read_line /tmp/uavpal_quectel_diag mtu)")
			modem_qmap_ippt_nat=$(json_number "$(kv_read_line /tmp/uavpal_quectel_diag qmap_ippt_nat)")
			modem_qmap_rule0_cid=$(json_number "$(kv_read_line /tmp/uavpal_quectel_diag qmap_rule0_cid)")
			modem_qmap_rule0_enabled=$(json_bool "$(kv_read_line /tmp/uavpal_quectel_diag qmap_rule0_enabled)")
			modem_qmap_status0_cid=$(json_number "$(kv_read_line /tmp/uavpal_quectel_diag qmap_status0_cid)")
			modem_qmap_status0_active=$(json_bool "$(kv_read_line /tmp/uavpal_quectel_diag qmap_status0_active)")
			modem_qmap_expected=$(kv_read_line /tmp/uavpal_quectel_diag qmap_expected)
			modem_qmap_mpdn_rule=$(kv_read_line /tmp/uavpal_quectel_diag qmap_mpdn_rule)
			modem_qmap_mpdn_status=$(kv_read_line /tmp/uavpal_quectel_diag qmap_mpdn_status)
			modem_setup_error=$(kv_read_line /tmp/uavpal_quectel_diag setup_error)
		fi
	fi
	usb8_diag_ts=$(json_number "$(kv_read_line /tmp/uavpal_usb8_diag ts)")
	if [ -z "$modem_provider" ] && [ "$modem_profile" = "generic_ethernet" ] && [ "$usb8_diag_ts" != "null" ] && [ $((telemetry_ts - usb8_diag_ts)) -le 60 ]; then
		if [ "$(kv_read_line /tmp/uavpal_usb8_diag provider)" = "inseego_usb8" ]; then
			modem_provider="inseego_usb8"
			modem_signal_bars=$(json_number "$(kv_read_line /tmp/uavpal_usb8_diag signal_bars)")
			modem_signal_pct_source=$(kv_read_line /tmp/uavpal_usb8_diag signal_pct_source)
			modem_rsrp_dbm=$(json_signed_number "$(kv_read_line /tmp/uavpal_usb8_diag rsrp_dbm)")
			modem_snr_db=$(json_signed_number "$(kv_read_line /tmp/uavpal_usb8_diag snr_db)")
			modem_band=$(kv_read_line /tmp/uavpal_usb8_diag band)
			modem_network=$(kv_read_line /tmp/uavpal_usb8_diag network)
			modem_technology=$(kv_read_line /tmp/uavpal_usb8_diag technology)
			modem_apn=$(kv_read_line /tmp/uavpal_usb8_diag apn)
			modem_connection_duration_sec=$(json_number "$(kv_read_line /tmp/uavpal_usb8_diag connection_duration_sec)")
			modem_ippt=$(json_bool "$(kv_read_line /tmp/uavpal_usb8_diag ippt)")
			modem_mtu=$(json_number "$(kv_read_line /tmp/uavpal_usb8_diag mtu)")
			modem_management_ip=$(kv_read_line /tmp/uavpal_usb8_diag management_ip)
		fi
	fi
	modem_provider_escaped=$(json_escape "$modem_provider")
	modem_signal_pct_source_escaped=$(json_escape "$modem_signal_pct_source")
	modem_band_escaped=$(json_escape "$modem_band")
	modem_network_escaped=$(json_escape "$modem_network")
	modem_technology_escaped=$(json_escape "$modem_technology")
	modem_apn_escaped=$(json_escape "$modem_apn")
	modem_active_apn_escaped=$(json_escape "$modem_active_apn")
	modem_expected_apn_escaped=$(json_escape "$modem_expected_apn")
	modem_management_ip_escaped=$(json_escape "$modem_management_ip")
	modem_rat_escaped=$(json_escape "$modem_rat")
	modem_lte_band_escaped=$(json_escape "$modem_lte_band")
	modem_nr_band_escaped=$(json_escape "$modem_nr_band")
	modem_qmap_expected_escaped=$(json_escape "$modem_qmap_expected")
	modem_qmap_mpdn_rule_escaped=$(json_escape "$modem_qmap_mpdn_rule")
	modem_qmap_mpdn_status_escaped=$(json_escape "$modem_qmap_mpdn_status")
	modem_setup_error_escaped=$(json_escape "$modem_setup_error")

	cat > /tmp/uavpal_telemetry.json.tmp <<EOF
{"schema":1,"modem_signal_pct":${telemetry_modem_signal_pct},"modem_provider":"${modem_provider_escaped}","modem_signal_bars":${modem_signal_bars},"modem_signal_pct_source":"${modem_signal_pct_source_escaped}","modem_rsrp_dbm":${modem_rsrp_dbm},"modem_rsrq_db":${modem_rsrq_db},"modem_snr_db":${modem_snr_db},"modem_band":"${modem_band_escaped}","modem_network":"${modem_network_escaped}","modem_technology":"${modem_technology_escaped}","modem_rat":"${modem_rat_escaped}","modem_lte_band":"${modem_lte_band_escaped}","modem_nr_band":"${modem_nr_band_escaped}","modem_lte_rsrp_dbm":${modem_lte_rsrp_dbm},"modem_lte_rsrq_db":${modem_lte_rsrq_db},"modem_lte_snr_db":${modem_lte_snr_db},"modem_nr_rsrp_dbm":${modem_nr_rsrp_dbm},"modem_nr_rsrq_db":${modem_nr_rsrq_db},"modem_nr_snr_db":${modem_nr_snr_db},"modem_apn":"${modem_apn_escaped}","modem_active_apn":"${modem_active_apn_escaped}","modem_expected_apn":"${modem_expected_apn_escaped}","modem_active_cid":${modem_active_cid},"modem_expected_apn_cid":${modem_expected_apn_cid},"modem_expected_apn_has_ipv4":${modem_expected_apn_has_ipv4},"modem_connection_duration_sec":${modem_connection_duration_sec},"modem_ippt":${modem_ippt},"modem_mtu":${modem_mtu},"modem_usbnet_mode":${modem_usbnet_mode},"modem_qmap_ippt_nat":${modem_qmap_ippt_nat},"modem_qmap_rule0_cid":${modem_qmap_rule0_cid},"modem_qmap_rule0_enabled":${modem_qmap_rule0_enabled},"modem_qmap_status0_cid":${modem_qmap_status0_cid},"modem_qmap_status0_active":${modem_qmap_status0_active},"modem_qmap_expected":"${modem_qmap_expected_escaped}","modem_qmap_mpdn_rule":"${modem_qmap_mpdn_rule_escaped}","modem_qmap_mpdn_status":"${modem_qmap_mpdn_status_escaped}","modem_setup_error":"${modem_setup_error_escaped}","modem_management_ip":"${modem_management_ip_escaped}","plane_battery_pct":${telemetry_plane_battery_pct},"mode":"${telemetry_mode_escaped}","profile":"${telemetry_profile_escaped}","iface":"${telemetry_iface_escaped}","gateway":"${telemetry_gateway_escaped}","zt":"${telemetry_zt_escaped}","zt_mode":"${telemetry_zt_escaped}","zt_state":"${telemetry_zt_state_escaped}","zt_ip":"${telemetry_zt_ip_escaped}","iface_rx_bytes":${iface_rx_bytes},"iface_tx_bytes":${iface_tx_bytes},"loop_ok":true,"telnetd":${telnetd_running},"queue_ok":${queue_ok},"route_ok":${route_ok},"reconnect_handler":"${telemetry_reconnect_handler_escaped}","reconnect_state":"${telemetry_reconnect_state_escaped}","reconnect_fail_count":${reconnect_fail_count},"reconnect_backoff_sec":${reconnect_backoff_sec},"reconnect_link_ok":${reconnect_link_ok},"reconnect_internet_ok":${reconnect_internet_ok},"ts":${telemetry_ts}}
EOF
	mv /tmp/uavpal_telemetry.json.tmp /tmp/uavpal_telemetry.json

	sleep 5
done
