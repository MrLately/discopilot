#!/bin/sh

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/data/ftp/uavpal/lib

serial_ctrl_dev=""
if [ -f /tmp/serial_ctrl_dev ]; then
	serial_ctrl_dev=$(head -1 /tmp/serial_ctrl_dev | tr -d '\r\n' | tr -d '\n')
fi

. /data/ftp/uavpal/bin/uavpal_globalfunctions.sh

usage()
{
	echo "Usage: $0 check|provision"
	echo "  check      Print RM520N ECM/APN/QMAP/route diagnostics only"
	echo "  provision  Bench-only: point QMAP rule 0 at the configured APN CID"
}

print_section()
{
	echo
	echo "=== $1 ==="
}

print_at_block()
{
	title="$1"
	text="$2"
	print_section "$title"
	if [ -n "$text" ]; then
		echo "$text"
	else
		echo "(no response)"
	fi
}

print_apn_summary()
{
	cgdcont_text="$1"
	cgpaddr_text="$2"
	print_section "APN / CID summary"
	echo "$cgdcont_text" | awk -F',' '
	/\+CGDCONT:/ {
		cid = $1
		sub(/.*: */, "", cid)
		gsub(/[^0-9]/, "", cid)
		apn = $3
		gsub(/[" \r]/, "", apn)
		if (cid != "" && apn != "") {
			print cid " " apn
		}
	}' | while read -r cid apn; do
		ipv4=$(quectel_cgpaddr_ipv4_for_cid "$cgpaddr_text" "$cid")
		if [ -n "$ipv4" ]; then
			echo "CID ${cid}: ${apn} IPv4=${ipv4}"
		else
			echo "CID ${cid}: ${apn} IPv4=none"
		fi
	done
}

print_carrier_summary()
{
	qcainfo_text="$1"
	print_section "Carrier aggregation summary"
	if ! echo "$qcainfo_text" | grep -q '+QCAINFO:'; then
		echo "No QCAINFO carrier data returned."
		return
	fi
	echo "$qcainfo_text" | awk -F',' '
	/\+QCAINFO:/ {
		role = $1
		sub(/.*: */, "", role)
		gsub(/[" \r]/, "", role)
		freq = $2
		bw = $3
		band = $4
		gsub(/[" \r]/, "", band)
		rsrp = $7
		rsrq = $8
		gsub(/[" \r]/, "", rsrp)
		gsub(/[" \r]/, "", rsrq)
		line = role " " band " arfcn=" freq " bw=" bw
		if (rsrp != "" && rsrp != "-") {
			line = line " rsrp=" rsrp
		}
		if (rsrq != "" && rsrq != "-") {
			line = line " rsrq=" rsrq
		}
		print line
	}'
}

print_temp_summary()
{
	qtemp_text="$1"
	print_section "Thermal summary"
	if ! echo "$qtemp_text" | grep -q '+QTEMP:'; then
		echo "No QTEMP data returned."
		return
	fi
	echo "$qtemp_text" | awk -F',' '
	/\+QTEMP:/ {
		name = $1
		temp = $2
		sub(/.*\+QTEMP:/, "", name)
		gsub(/[" \r]/, "", name)
		gsub(/[" \r]/, "", temp)
		if (temp != "" && temp != "0") {
			print name "=" temp "C"
		}
	}'
}

print_route_summary()
{
	print_section "Plane route / ZeroTier"
	echo "profile=$(cat /tmp/modem_connection_profile 2>/dev/null)"
	echo "provider=$(cat /tmp/modem_provider 2>/dev/null)"
	echo "iface=$(cat /tmp/modem_iface 2>/dev/null)"
	echo "ip=$(cat /tmp/modem_ip 2>/dev/null)"
	echo "gateway=$(cat /tmp/modem_gateway_ip 2>/dev/null)"
	echo
	route -n
	echo
	if [ -x /data/ftp/uavpal/bin/zerotier-one ]; then
		/data/ftp/uavpal/bin/zerotier-one -q info 2>/dev/null
		/data/ftp/uavpal/bin/zerotier-one -q listnetworks 2>/dev/null
	else
		echo "zerotier-one not found"
	fi
}

action="$1"
if [ -z "$action" ]; then
	action="check"
fi
case "$action" in
check | provision)
	;;
*)
	usage
	exit 2
	;;
esac

load_modem_config
detect_usb_modem >/dev/null 2>&1

if ! is_quectel_rm520n; then
	echo "ERROR: Quectel RM520N USB ID 2c7c:0801 was not detected."
	exit 1
fi

echo "quectel_rm520n" >/tmp/modem_provider
quectel_bind_option_driver >/dev/null 2>&1
probe_serial_ctrl_dev "2" >/dev/null 2>&1

if [ -z "$serial_ctrl_dev" ] || [ ! -c "/dev/${serial_ctrl_dev}" ]; then
	echo "ERROR: no Quectel AT control port found."
	exit 1
fi

print_section "Quectel RM520N ECM check"
echo "AT control port: /dev/${serial_ctrl_dev}"

usbnet_mode=$(quectel_usbnet_mode)
qnwinfo=$(at_command "AT+QNWINFO" "OK" "2")
qeng=$(at_command 'AT+QENG="servingcell"' "OK" "2")
cgdcont=$(at_command "AT+CGDCONT?" "OK" "2")
cgpaddr=$(at_command "AT+CGPADDR" "OK" "2")
mpdn_rule=$(at_command 'AT+QMAP="MPDN_rule"' "OK" "2")
mpdn_status=$(at_command 'AT+QMAP="mPDN_status"' "OK" "2")
ippt_nat=$(at_command 'AT+QMAP="IPPT_NAT"' "OK" "2")
qcainfo=$(at_command "AT+QCAINFO" "OK" "3")
qtemp=$(at_command "AT+QTEMP" "OK" "3")

expected_apn="$(conf_read apn)"
expected_cid=""
if [ -n "$expected_apn" ]; then
	expected_cid=$(quectel_cgdcont_cid_for_apn "$cgdcont" "$expected_apn")
fi
expected_ipv4=$(quectel_cgpaddr_ipv4_for_cid "$cgpaddr" "$expected_cid")
rule0_cid=$(quectel_qmap_rule_cid "$mpdn_rule" 0)
rule0_enabled=$(quectel_qmap_rule_enabled "$mpdn_rule" 0)
status0_cid=$(quectel_qmap_status_cid "$mpdn_status" 0)
status0_active=$(quectel_qmap_status_active "$mpdn_status" 0)
active_cid=""
if [ "$status0_active" = "1" ] && [ -n "$status0_cid" ] && [ "$status0_cid" != "0" ]; then
	active_cid="$status0_cid"
elif [ "$rule0_enabled" = "1" ] && [ -n "$rule0_cid" ] && [ "$rule0_cid" != "0" ]; then
	active_cid="$rule0_cid"
elif [ -n "$expected_ipv4" ]; then
	active_cid="$expected_cid"
else
	active_cid=$(quectel_cgdcont_first_data_cid "$cgdcont")
fi
active_apn=$(quectel_cgdcont_apn_for_cid "$cgdcont" "$active_cid")

print_section "ECM summary"
echo "usbnet_mode=${usbnet_mode}"
echo "expected_apn=${expected_apn}"
echo "expected_cid=${expected_cid}"
if [ -z "$expected_apn" ]; then
	echo "expected_apn_ipv4=unknown"
elif [ -n "$expected_ipv4" ]; then
	echo "expected_apn_ipv4=yes"
else
	echo "expected_apn_ipv4=no"
fi
echo "qmap_rule0_cid=${rule0_cid}"
echo "qmap_rule0_enabled=${rule0_enabled}"
echo "qmap_status0_cid=${status0_cid}"
echo "qmap_status0_active=${status0_active}"
echo "active_cid=${active_cid}"
echo "active_apn=${active_apn}"
if [ -z "$expected_apn" ]; then
	echo "qmap_expected=unknown_expected_apn"
elif [ -n "$expected_cid" ] && [ "$rule0_cid" = "$expected_cid" ] && [ "$rule0_enabled" = "1" ]; then
	echo "qmap_expected=ok"
else
	echo "qmap_expected=needs_bench_review"
fi

print_apn_summary "$cgdcont" "$cgpaddr"
print_at_block "QMAP MPDN_rule" "$mpdn_rule"
print_at_block "QMAP mPDN_status" "$mpdn_status"
print_at_block "QMAP IPPT_NAT" "$ippt_nat"
print_at_block "Serving network" "$qnwinfo"
print_at_block "Serving cell" "$qeng"
print_carrier_summary "$qcainfo"
print_at_block "Carrier aggregation raw" "$qcainfo"
print_temp_summary "$qtemp"
print_at_block "Thermal raw" "$qtemp"
print_route_summary

if [ "$action" = "check" ]; then
	exit 0
fi

print_section "Bench provision"
if [ -z "$expected_apn" ]; then
	echo "ERROR: no APN configured in /data/ftp/uavpal/conf/apn; not changing QMAP."
	exit 1
fi

if [ -z "$expected_cid" ]; then
	echo "ERROR: ${expected_apn} was not found in CGDCONT; not changing QMAP."
	exit 1
fi

if [ "$rule0_cid" = "$expected_cid" ] && [ "$rule0_enabled" = "1" ]; then
	echo "QMAP rule 0 already points to ${expected_apn} CID ${expected_cid}."
	echo "No change needed."
	exit 0
fi

echo "Setting QMAP rule 0 to ${expected_apn} CID ${expected_cid}."
provision_result=$(at_command "AT+QMAP=\"MPDN_rule\",0,${expected_cid},0,0,1" "OK" "3")
echo "$provision_result"
if echo "$provision_result" | grep -q "OK"; then
	echo "Provision complete. Reboot the Disco or reset/replug the modem before flight testing."
	exit 0
fi

echo "ERROR: modem did not confirm QMAP rule update."
exit 1
