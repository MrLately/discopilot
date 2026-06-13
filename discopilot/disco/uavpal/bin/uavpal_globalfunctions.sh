load_modem_config()
{
	MODEM_PROFILE="auto"
	MODEM_USB_IDS="12d1:* 19d2:* 2c7c:* 1199:* 2dee:* 05c6:* 1bc7:* 413c:*"
	MODEM_ETH_IFACE="auto"
	MODEM_ETH_IFACE_PREFIXES="eth usb wwan enx"
	MODEM_PPP_IFACE="ppp0"
	MODEM_SERIAL_CTRL="auto"
	MODEM_SERIAL_PPP="auto"
	MODEM_ENABLE_USB_MODESWITCH="auto"
	MODEM_USB_MODESWITCH_VENDOR="12d1"
	MODEM_USB_MODESWITCH_ARGS="--huawei-new-mode -s 3"
	MODEM_HILINK_DMZ="1"
	MODEM_HILINK_FULLCONE_NAT="1"
	MODEM_LOW_LATENCY_TXQLEN="100"

	if [ -f /data/ftp/uavpal/conf/modem.conf ]; then
		# shellcheck disable=SC1091
		. /data/ftp/uavpal/conf/modem.conf
	fi

	if [ -n "$MODEM_PPP_IFACE" ]; then
		ppp_if="$MODEM_PPP_IFACE"
	fi
}

detect_usb_modem()
{
	matched_usb_id=""
	matched_usb_vendor=""
	matched_usb_product=""
	matched_usb_desc=""

	while read -r line; do
		usb_id=$(echo "$line" | awk '{for (i=1; i<=NF; i++) if ($i=="ID") { print $(i+1); exit }}' | tr 'A-Z' 'a-z')
		[ -z "$usb_id" ] && continue
		for pattern in $MODEM_USB_IDS; do
			pattern_lc=$(echo "$pattern" | tr 'A-Z' 'a-z')
			case "$usb_id" in
			$pattern_lc)
				matched_usb_id="$usb_id"
				matched_usb_vendor=$(echo "$usb_id" | cut -d ':' -f 1)
				matched_usb_product=$(echo "$usb_id" | cut -d ':' -f 2)
				matched_usb_desc=$(echo "$line" | sed 's/.*ID [0-9A-Fa-f]\{4\}:[0-9A-Fa-f]\{4\} //')
				return 0
				;;
			*)
				;;
			esac
		done
	done <<EOF
$(lsusb 2>/dev/null)
EOF

	return 1
}

is_quectel_rm520n()
{
	quectel_usb_id="$matched_usb_id"
	if [ -z "$quectel_usb_id" ] && [ -f /tmp/modem_usb_id ]; then
		quectel_usb_id=$(head -1 /tmp/modem_usb_id | tr -d '\r\n' | tr -d '\n')
	fi
	case "$quectel_usb_id" in
	2c7c:0801)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

quectel_bind_option_driver()
{
	is_quectel_rm520n || return 1
	echo "quectel_rm520n" >/tmp/modem_provider

	if ls /dev/ttyUSB* >/dev/null 2>&1; then
		return 0
	fi

	if [ -w /sys/bus/usb-serial/drivers/option1/new_id ]; then
		ulogger -s -t uavpal_quectel "... binding Quectel RM520N serial interfaces to option driver"
		echo "2c7c 0801" >/sys/bus/usb-serial/drivers/option1/new_id 2>/dev/null
		sleep 2
	fi

	if ls /dev/ttyUSB* >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

run_usb_modeswitch()
{
	if [ ! -x /data/ftp/uavpal/bin/usb_modeswitch ]; then
		return 0
	fi

	if [ -z "$matched_usb_vendor" ] || [ -z "$matched_usb_product" ]; then
		return 1
	fi

	case "$MODEM_ENABLE_USB_MODESWITCH" in
	0 | false | no | off)
		return 0
		;;
	auto)
		modeswitch_vendor_lc=$(echo "$MODEM_USB_MODESWITCH_VENDOR" | tr 'A-Z' 'a-z')
		if [ "$matched_usb_vendor" != "$modeswitch_vendor_lc" ]; then
			return 0
		fi
		;;
	*)
		;;
	esac

	ulogger -s -t uavpal_drone "... running usb_modeswitch for ${matched_usb_vendor}:${matched_usb_product}"
	/data/ftp/uavpal/bin/usb_modeswitch -v "$matched_usb_vendor" -p "$matched_usb_product" $MODEM_USB_MODESWITCH_ARGS
}

list_network_ifaces()
{
	awk -F ':' 'NR>2 { gsub(/ /, "", $1); if ($1 != "") print $1 }' /proc/net/dev
}

apply_low_latency_queue()
{
	iface="$1"
	target_qlen="$2"

	[ -n "$iface" ] || return 1
	[ -d "/proc/sys/net/ipv4/conf/${iface}" ] || return 1

	case "$target_qlen" in
	'' | *[!0-9]*)
		return 1
		;;
	*)
		;;
	esac
	[ "$target_qlen" -gt 0 ] || return 0

	current_qlen=$(ifconfig "${iface}" 2>/dev/null | sed -n 's/.*txqueuelen:\([0-9][0-9]*\).*/\1/p' | head -n 1)
	if [ -z "$current_qlen" ]; then
		current_qlen=$(ip link show "${iface}" 2>/dev/null | sed -n 's/.*qlen \([0-9][0-9]*\).*/\1/p' | head -n 1)
	fi

	# Only reduce oversized queues. Never raise small queues (for example ppp txqueuelen 3).
	if [ -n "$current_qlen" ] && [ "$current_qlen" -le "$target_qlen" ]; then
		echo "ok=1 iface=${iface} qlen=${current_qlen} ts=$(date +%s)" >/tmp/uavpal_queue_diag
		return 0
	fi

	if ifconfig "${iface}" txqueuelen "${target_qlen}" >/dev/null 2>&1; then
		echo "ok=1 iface=${iface} qlen=${target_qlen} ts=$(date +%s)" >/tmp/uavpal_queue_diag
		ulogger -s -t uavpal_queue "... set ${iface} txqueuelen=${target_qlen} (was ${current_qlen:-unknown})"
		return 0
	fi
	if ip link set dev "${iface}" txqueuelen "${target_qlen}" >/dev/null 2>&1; then
		echo "ok=1 iface=${iface} qlen=${target_qlen} ts=$(date +%s)" >/tmp/uavpal_queue_diag
		ulogger -s -t uavpal_queue "... set ${iface} txqueuelen=${target_qlen} (was ${current_qlen:-unknown})"
		return 0
	fi

	echo "ok=0 iface=${iface} qlen=${target_qlen} ts=$(date +%s)" >/tmp/uavpal_queue_diag
	return 1
}

apply_low_latency_queues()
{
	case "$MODEM_LOW_LATENCY_TXQLEN" in
	'' | *[!0-9]*)
		return 0
		;;
	*)
		;;
	esac
	[ "$MODEM_LOW_LATENCY_TXQLEN" -gt 0 ] || return 0

	if [ -n "$cdc_if" ]; then
		apply_low_latency_queue "$cdc_if" "$MODEM_LOW_LATENCY_TXQLEN"
	fi
	if [ -n "$ppp_if" ]; then
		apply_low_latency_queue "$ppp_if" "$MODEM_LOW_LATENCY_TXQLEN"
	fi
	for iface in $(list_network_ifaces); do
		case "$iface" in
		zt*)
			apply_low_latency_queue "$iface" "$MODEM_LOW_LATENCY_TXQLEN"
			;;
		*)
			;;
		esac
	done
}

is_modem_net_iface_candidate()
{
	iface="$1"

	case "$iface" in
	lo | eth0 | wlan* | zt* | ppp* | sit* | ip6tnl* | tunl* | gre* | gretap* | erspan* | docker* | br* | ifb*)
		return 1
		;;
	*)
		;;
	esac

	dev_path=$(readlink -f "/sys/class/net/${iface}/device" 2>/dev/null)
	if [ -n "$dev_path" ] && echo "$dev_path" | grep -q "/usb"; then
		return 0
	fi

	return 1
}

detect_cdc_iface()
{
	if [ -n "$MODEM_ETH_IFACE" ] && [ "$MODEM_ETH_IFACE" != "auto" ]; then
		if [ -d "/proc/sys/net/ipv4/conf/${MODEM_ETH_IFACE}" ]; then
			cdc_if="$MODEM_ETH_IFACE"
			return 0
		fi
	fi

	for prefix in $MODEM_ETH_IFACE_PREFIXES; do
		for iface in $(list_network_ifaces); do
			case "$iface" in
			${prefix}*)
				if is_modem_net_iface_candidate "$iface"; then
					cdc_if="$iface"
					return 0
				fi
				;;
			*)
				;;
			esac
		done
	done

	for iface in $(list_network_ifaces); do
		if is_modem_net_iface_candidate "$iface"; then
			cdc_if="$iface"
			return 0
		fi
	done

	return 1
}

detect_serial_devices()
{
	if [ -n "$MODEM_SERIAL_CTRL" ] && [ "$MODEM_SERIAL_CTRL" != "auto" ]; then
		serial_ctrl_dev="$MODEM_SERIAL_CTRL"
	fi
	if [ -n "$MODEM_SERIAL_PPP" ] && [ "$MODEM_SERIAL_PPP" != "auto" ]; then
		serial_ppp_dev="$MODEM_SERIAL_PPP"
	fi

	serial_candidates=""
	for dev in /dev/ttyUSB* /dev/ttyACM*; do
		if [ -c "$dev" ]; then
			serial_candidates="$serial_candidates $dev"
		fi
	done

	first_dev=$(echo "$serial_candidates" | awk '{ print $1 }')
	second_dev=$(echo "$serial_candidates" | awk '{ print $2 }')
	serial_dev_count=$(echo "$serial_candidates" | awk '{ print NF }')

	if [ "$MODEM_SERIAL_CTRL" = "auto" ] || [ -z "$MODEM_SERIAL_CTRL" ]; then
		if ! probe_serial_ctrl_dev 1; then
			if [ -n "$first_dev" ]; then
				serial_ctrl_dev=$(basename "$first_dev")
			fi
		fi
	fi

	if [ "$MODEM_SERIAL_PPP" = "auto" ] || [ -z "$MODEM_SERIAL_PPP" ]; then
		if [ -n "$second_dev" ]; then
			serial_ppp_dev=$(basename "$second_dev")
		elif [ -n "$first_dev" ]; then
			serial_ppp_dev=$(basename "$first_dev")
		fi
		if [ -n "$serial_ctrl_dev" ] && [ "$serial_ppp_dev" = "$serial_ctrl_dev" ] && [ "$serial_dev_count" -gt 1 ]; then
			for dev in $serial_candidates; do
				[ -c "$dev" ] || continue
				candidate=$(basename "$dev")
				if [ "$candidate" != "$serial_ctrl_dev" ]; then
					serial_ppp_dev="$candidate"
					break
				fi
			done
		fi
	fi

	if [ -n "$serial_ctrl_dev" ] && [ -c "/dev/${serial_ctrl_dev}" ]; then
		return 0
	fi

	return 1
}

ensure_ethernet_default_route()
{
	route_iface="$1"
	route_gateway="$2"

	if [ -z "$route_iface" ]; then
		route_iface="$cdc_if"
	fi
	if [ -z "$route_gateway" ] && [ -f /tmp/modem_gateway_ip ]; then
		route_gateway=$(head -1 /tmp/modem_gateway_ip | tr -d '\r\n' | tr -d '\n')
	fi
	if [ -z "$route_iface" ] || [ -z "$route_gateway" ]; then
		echo "ok=0 iface=${route_iface} gateway=${route_gateway} ts=$(date +%s)" >/tmp/uavpal_route_diag
		return 1
	fi

	if ip route 2>/dev/null | awk -v dev="$route_iface" -v gw="$route_gateway" '$1=="default" && $3==gw && $5==dev { found=1 } END { exit(found ? 0 : 1) }'; then
		echo "ok=1 iface=${route_iface} gateway=${route_gateway} ts=$(date +%s)" >/tmp/uavpal_route_diag
		return 0
	fi
	if route -n 2>/dev/null | awk -v dev="$route_iface" -v gw="$route_gateway" '$1=="0.0.0.0" && $2==gw && $8==dev { found=1 } END { exit(found ? 0 : 1) }'; then
		echo "ok=1 iface=${route_iface} gateway=${route_gateway} ts=$(date +%s)" >/tmp/uavpal_route_diag
		return 0
	fi

	route_ok=0
	ip route replace default via "$route_gateway" dev "$route_iface" >/dev/null 2>&1
	if [ "$?" -eq 0 ]; then
		route_ok=1
	fi
	if [ "$route_ok" -ne 1 ]; then
		ip route del default dev "$route_iface" >/dev/null 2>&1
		ip route add default via "$route_gateway" dev "$route_iface" >/dev/null 2>&1
		if [ "$?" -eq 0 ]; then
			route_ok=1
		fi
	fi
	if [ "$route_ok" -ne 1 ]; then
		route del default gw "$route_gateway" dev "$route_iface" >/dev/null 2>&1
		route add default gw "$route_gateway" dev "$route_iface" >/dev/null 2>&1
		if [ "$?" -eq 0 ]; then
			route_ok=1
		fi
	fi

	if [ "$route_ok" -eq 1 ]; then
		echo "ok=1 iface=${route_iface} gateway=${route_gateway} ts=$(date +%s)" >/tmp/uavpal_route_diag
		ulogger -s -t uavpal_route "... repaired default route via ${route_gateway} on ${route_iface}"
		return 0
	fi

	echo "ok=0 iface=${route_iface} gateway=${route_gateway} ts=$(date +%s)" >/tmp/uavpal_route_diag
	return 1
}

connect_ethernet()
{
	ulogger -s -t uavpal_connect_ethernet "... bringing up modem network interface ${cdc_if}"
	ifconfig "${cdc_if}" up
	echo "${cdc_if}" >/tmp/modem_iface
	apply_low_latency_queues
	ulogger -s -t uavpal_connect_ethernet "... requesting IP address from modem's DHCP server"
	dhcp_out=$(udhcpc -i "${cdc_if}" -n -t 10 2>&1)
	modem_ip=$(echo "$dhcp_out" | awk '/obtained/ { print $4; exit }')
	modem_gateway_ip=$(echo "$dhcp_out" | awk '/router/ { for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+\./) { print $i; exit } }')

	# udhcpc output formatting varies by firmware/busybox build.
	# Confirm modem IP and gateway from interface/route state as well.
	for i in $(seq 1 4); do
		if [ -z "$modem_ip" ]; then
			modem_ip=$(ifconfig "${cdc_if}" 2>/dev/null | awk '/inet addr:/{ split($2, a, ":"); print a[2]; exit }')
		fi
		if [ -z "$modem_ip" ]; then
			modem_ip=$(ifconfig "${cdc_if}" 2>/dev/null | awk '/inet /{ print $2; exit }')
		fi
		if [ -z "$modem_gateway_ip" ]; then
			modem_gateway_ip=$(ip route 2>/dev/null | awk -v dev="${cdc_if}" '$1=="default" && $5==dev { print $3; exit }')
		fi
		if [ -z "$modem_gateway_ip" ]; then
			modem_gateway_ip=$(route -n 2>/dev/null | awk -v dev="${cdc_if}" '$1=="0.0.0.0" && $8==dev { print $2; exit }')
		fi
		if [ -n "$modem_ip" ] && [ -n "$modem_gateway_ip" ]; then
			break
		fi
		sleep 1
	done

	if [ -z "$modem_gateway_ip" ]; then
		modem_gateway_ip=$(ip route 2>/dev/null | awk -v dev="${cdc_if}" '$1=="default" && $5==dev { print $3; exit }')
	fi
	if [ -z "$modem_gateway_ip" ]; then
		modem_gateway_ip=$(route -n 2>/dev/null | awk -v dev="${cdc_if}" '$1=="0.0.0.0" && $8==dev { print $2; exit }')
	fi
	if [ -z "$modem_gateway_ip" ] && [ -n "$modem_ip" ]; then
		modem_gateway_ip="$(echo "$modem_ip" | cut -d '.' -f 1,2,3).1"
	fi

	if [ -n "$modem_ip" ]; then
		ulogger -s -t uavpal_connect_ethernet "... setting ${cdc_if}'s IP address to ${modem_ip}"
		ifconfig "${cdc_if}" "${modem_ip}" netmask 255.255.255.0
	fi

	if [ -n "$modem_gateway_ip" ]; then
		ulogger -s -t uavpal_connect_ethernet "... setting default route via ${modem_gateway_ip}"
		if ensure_ethernet_default_route "$cdc_if" "$modem_gateway_ip"; then
			echo "${modem_gateway_ip}" >/tmp/modem_gateway_ip
		else
			ulogger -s -t uavpal_connect_ethernet "... failed to install default route via ${modem_gateway_ip} on ${cdc_if}"
			modem_gateway_ip=""
		fi
	fi
	echo "${modem_ip}" >/tmp/modem_ip

	if [ -z "$modem_ip" ] || [ -z "$modem_gateway_ip" ]; then
		ulogger -s -t uavpal_connect_ethernet "... DHCP/router detection failed on ${cdc_if}"
		return 1
	fi

	return 0
}

write_reconnect_diag()
{
	diag_handler="$1"
	diag_fail_count="$2"
	diag_link_ok="$3"
	diag_internet_ok="$4"
	diag_backoff_sec="$5"
	diag_state="$6"

	if [ -z "$diag_state" ]; then
		if [ "$diag_link_ok" -ne "0" ]; then
			diag_state="link_down"
		elif [ "$diag_internet_ok" -ne "0" ]; then
			diag_state="internet_degraded"
		elif [ "$diag_fail_count" -gt "0" ]; then
			diag_state="recovering"
		else
			diag_state="ready"
		fi
	fi

	echo "handler=${diag_handler} state=${diag_state} fail_count=${diag_fail_count} link_ok=${diag_link_ok} internet_ok=${diag_internet_ok} backoff_sec=${diag_backoff_sec} ts=$(date +%s)" >/tmp/uavpal_reconnect_diag
}

modem_has_hilink_api()
{
	if [ -z "$modem_gateway_ip" ] && [ -f /tmp/modem_gateway_ip ]; then
		modem_gateway_ip=$(cat /tmp/modem_gateway_ip)
	fi
	if [ -z "$modem_gateway_ip" ]; then
		return 1
	fi

	probe=$(/data/ftp/uavpal/bin/curl -s -m 2 -X GET "http://${modem_gateway_ip}/api/device/information" 2>/dev/null)
	echo "$probe" | grep -q "<response>" || return 1
	echo "$probe" | grep -q "<DeviceName>" || return 1
	return 0
}

hilink_api()
{
# Usage: hilink_api {get,post} url-context [json-data]
# Note: callers invoking this function using method "post" do not need to process (echoed) return values, as errors are outputted within the function itself, otherwise the response is <response>OK</response>
#       callers invoking this function using method "get" should handle (echoed) return values using var=$(hilink_api)

	if [ "$1" == "post" ]; then
		method="POST"
	else
		method="GET"
	fi
	url="$2"
	data="$3"

	if [ -f /tmp/hilink_router_ip ]; then
		hilink_router_ip=$(head -1 /tmp/hilink_router_ip | tr -d '\r\n' | tr -d '\n')
	fi
	if [ -z "$hilink_router_ip" ]; then
		return
	fi

	sessionInfo=$(/data/ftp/uavpal/bin/curl -s -m 3 -X GET "http://${hilink_router_ip}/api/webserver/SesTokInfo" -H "X-Requested-With: XMLHttpRequest" -H "Referer: http://${hilink_router_ip}/" 2>/dev/null)
	if [ "$?" -ne "0" ] || [ -z "$sessionInfo" ]; then
		ulogger -s -t uavpal_hilink_api "... Error connecting to Hi-Link API"
		return
	fi
	cookie=$(echo "$sessionInfo" | xmllint --xpath 'string(//SesInfo)' - 2>/dev/null | tr -d '\r\n' | tr -d '\n')
	token=$(echo "$sessionInfo" | xmllint --xpath 'string(//TokInfo)' - 2>/dev/null | tr -d '\r\n' | tr -d '\n')
	if [ -z "$cookie" ]; then
		cookie=$(echo "$sessionInfo" | sed -n 's:.*<SesInfo>\([^<]*\)</SesInfo>.*:\1:p' | head -n 1 | tr -d '\r\n' | tr -d '\n')
	fi
	if [ -z "$token" ]; then
		token=$(echo "$sessionInfo" | sed -n 's:.*<TokInfo>\([^<]*\)</TokInfo>.*:\1:p' | head -n 1 | tr -d '\r\n' | tr -d '\n')
	fi
	if [ -f /tmp/hilink_login_required ]; then
		sessionInfoLogin=$(/data/ftp/uavpal/bin/curl -s -m 5 -X POST "http://${hilink_router_ip}/api/user/login" -d "<request><Username>admin</Username><Password>$(echo -n "admin" |base64)</Password><password_type>3</password_type></request>" -H "Cookie: $cookie" -H "__RequestVerificationToken: $token" -H "X-Requested-With: XMLHttpRequest" -H "Referer: http://${hilink_router_ip}/" --dump-header - 2>/dev/null)
		if echo -n "$sessionInfoLogin" | grep '<code>108006\|<code>108007' ; then
			ulogger -s -t uavpal_hilink_api "... Hi-Link authentication error. Please disable password protection or set it to user=admin, password=admin"
			return # break out function
		fi
		login_cookie=$(echo "$sessionInfoLogin" | tr -d '\r' | sed -n 's/^Set-Cookie:[[:space:]]*\([^;]*\).*/\1/p' | head -n 1 | tr -d '\r\n' | tr -d '\n')
		if [ -n "$login_cookie" ]; then
			cookie="$login_cookie"
		fi
		sessionInfoAdm=$(/data/ftp/uavpal/bin/curl -s -m 3 -X GET "http://${hilink_router_ip}/api/webserver/SesTokInfo" -H "Cookie: $cookie" -H "X-Requested-With: XMLHttpRequest" -H "Referer: http://${hilink_router_ip}/" 2>/dev/null)
		token=$(echo "$sessionInfoAdm" | xmllint --xpath 'string(//TokInfo)' - 2>/dev/null | tr -d '\r\n' | tr -d '\n')
		if [ -z "$token" ]; then
			token=$(echo "$sessionInfoAdm" | sed -n 's:.*<TokInfo>\([^<]*\)</TokInfo>.*:\1:p' | head -n 1 | tr -d '\r\n' | tr -d '\n')
		fi
	fi
	if [ "$method" = "POST" ]; then
		result=$(/data/ftp/uavpal/bin/curl -s -m 4 -X POST "http://${hilink_router_ip}${url}" -d "$data" -H "Cookie: $cookie" -H "__RequestVerificationToken: $token" -H "X-Requested-With: XMLHttpRequest" -H "Referer: http://${hilink_router_ip}/" 2>/dev/null)
	else
		result=$(/data/ftp/uavpal/bin/curl -s -m 4 -X GET "http://${hilink_router_ip}${url}" -H "Cookie: $cookie" -H "__RequestVerificationToken: $token" -H "X-Requested-With: XMLHttpRequest" -H "Referer: http://${hilink_router_ip}/" 2>/dev/null)
	fi
	if echo "$result" | grep "<error>" ; then
		error_code=$(echo "$result" | xmllint --xpath 'string(//error/code)' - 2>/dev/null)
		if [ "$error_code" = "100003" ] || [ "$error_code" = "125002" ]; then
			if [ "${HILINK_AUTH_RETRY:-0}" -eq 0 ]; then
				ulogger -s -t uavpal_hilink_api "... Hi-Link authentication required (error ${error_code}). Trying login using user=admin, password=admin"
				touch /tmp/hilink_login_required
				result=$(HILINK_AUTH_RETRY=1 hilink_api "$1" "$2" "$3")
			else
				ulogger -s -t uavpal_hilink_api "... Hi-Link authentication retry failed (error ${error_code})"
			fi
		else
			ulogger -s -t uavpal_hilink_api "... Hi-Link returned Error Code: ${error_code}"
		fi
	fi
	echo "$result"
}

firewall()
{
	# Security: block incoming connections on the Internet interface
	# these connections should only be allowed on Wi-Fi (eth0) and via zerotier (zt*)
	ulogger -s -t uavpal_drone "... applying iptables security rules for interface ${1}"
	iptables -N UAVPAL_INPUT 2>/dev/null
	iptables -F UAVPAL_INPUT 2>/dev/null
	if ! iptables -L INPUT -n 2>/dev/null | grep -q "UAVPAL_INPUT"; then
		iptables -I INPUT -j UAVPAL_INPUT 2>/dev/null
	fi
	ip_block='21 23 51 61 873 8888 9050 44444 67 5353 14551'
	for i in $ip_block; do iptables -A UAVPAL_INPUT -p tcp -i ${1} --dport $i -j DROP; done
}

conf_read()
{
	result=$(head -1 /data/ftp/uavpal/conf/${1})
	echo "$result" |tr -d '\r\n' |tr -d '\n'
}

zerotier_transport_ok()
{
	zt_ok_nwid="$(conf_read zt_networkid)"
	if [ -z "$zt_ok_nwid" ] || [ ! -x /data/ftp/uavpal/bin/zerotier-one ]; then
		return 1
	fi

	zt_ok_line=$(/data/ftp/uavpal/bin/zerotier-one -q listnetworks 2>/dev/null | awk -v nwid="$zt_ok_nwid" '$3==nwid { print; exit }')
	if [ -z "$zt_ok_line" ]; then
		return 1
	fi

	zt_ok_state=$(echo "$zt_ok_line" | awk '{ for (i=1; i<=NF; i++) if ($i=="OK" || $i=="ACCESS_DENIED" || $i=="REQUESTING_CONFIGURATION" || $i=="NOT_FOUND" || $i=="PORT_ERROR") { print $i; exit } }')
	zt_ok_ip=$(echo "$zt_ok_line" | awk '{ for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) { gsub(/,.*/, "", $i); print $i; exit } }')

	if [ "$zt_ok_state" = "OK" ] && [ -n "$zt_ok_ip" ]; then
		return 0
	fi
	return 1
}

at_command_on_dev()
{
	dev="$1"
	command="$2"
	expected_response="$3"
	timeout="$4"

	at_lock_dir="/tmp/uavpal_at_command.lock"
	at_lock_wait=15
	at_lock_count=0
	while ! mkdir "$at_lock_dir" 2>/dev/null; do
		at_lock_owner=""
		if [ -f "${at_lock_dir}/pid" ]; then
			at_lock_owner=$(cat "${at_lock_dir}/pid" 2>/dev/null)
		fi
		if [ -n "$at_lock_owner" ] && ! kill -0 "$at_lock_owner" 2>/dev/null; then
			rm -rf "$at_lock_dir"
			continue
		fi
		at_lock_count=$((at_lock_count + 1))
		if [ "$at_lock_count" -ge "$at_lock_wait" ]; then
			ulogger -s -t uavpal_at_command "... timed out waiting for AT command lock for $command"
			return 1
		fi
		sleep 1
	done
	echo "$$" > "${at_lock_dir}/pid"

	result=$(/data/ftp/uavpal/bin/chat -V -t "$timeout" '' "$command" "$expected_response" '' > /dev/${dev} < /dev/${dev}) 2>&1
	rc="$?"

	if [ -f "${at_lock_dir}/pid" ] && [ "$(cat "${at_lock_dir}/pid" 2>/dev/null)" = "$$" ]; then
		rm -rf "$at_lock_dir"
	fi

	echo "$result"
	return "$rc"
}

probe_serial_ctrl_dev()
{
	probe_timeout="$1"
	if [ -z "$probe_timeout" ]; then
		probe_timeout="1"
	fi

	if is_quectel_rm520n; then
		quectel_bind_option_driver >/dev/null 2>&1
		if [ -c /dev/ttyUSB2 ]; then
			probe_result=$(at_command_on_dev "ttyUSB2" "AT" "OK" "$probe_timeout")
			if [ "$?" -eq "0" ] && echo "$probe_result" | grep -q "OK"; then
				if [ "$serial_ctrl_dev" != "ttyUSB2" ]; then
					ulogger -s -t uavpal_at_command "... using ttyUSB2 as Quectel RM520N control interface"
				fi
				serial_ctrl_dev="ttyUSB2"
				echo "$serial_ctrl_dev" >/tmp/serial_ctrl_dev
				return 0
			fi
		fi
	fi

	candidates=""
	if [ -n "$serial_ctrl_dev" ] && [ -c "/dev/${serial_ctrl_dev}" ]; then
		candidates="$candidates /dev/${serial_ctrl_dev}"
	fi
	for dev in /dev/ttyUSB* /dev/ttyACM*; do
		[ -c "$dev" ] || continue
		candidates="$candidates $dev"
	done

	seen=" "
	for dev in $candidates; do
		[ -c "$dev" ] || continue
		candidate=$(basename "$dev")
		case "$seen" in
			*" $candidate "*)
				continue
				;;
			*)
				;;
		esac
		seen="$seen$candidate "
		if [ -n "$serial_ppp_dev" ] && [ "$candidate" = "$serial_ppp_dev" ]; then
			continue
		fi
		probe_result=$(at_command_on_dev "$candidate" "AT" "OK" "$probe_timeout")
		if [ "$?" -eq "0" ] && echo "$probe_result" | grep -q "OK"; then
			if [ "$serial_ctrl_dev" != "$candidate" ]; then
				ulogger -s -t uavpal_at_command "... using ${candidate} as modem serial control interface"
			fi
			serial_ctrl_dev="$candidate"
			echo "$serial_ctrl_dev" >/tmp/serial_ctrl_dev
			return 0
		fi
	done

	return 1
}

at_command()
{
	command="$1"
	expected_response="$2"
	timeout="$3"

	if [ -z "$timeout" ]; then
		timeout="1"
	fi

	if [ -z "$serial_ctrl_dev" ] && [ -f /tmp/serial_ctrl_dev ]; then
		serial_ctrl_dev=$(head -1 /tmp/serial_ctrl_dev | tr -d '\r\n' | tr -d '\n')
	fi

	if [ -z "$serial_ctrl_dev" ] || [ ! -c "/dev/${serial_ctrl_dev}" ]; then
		probe_serial_ctrl_dev "$timeout" >/dev/null 2>&1
	fi

	if [ -z "$serial_ctrl_dev" ] || [ ! -c "/dev/${serial_ctrl_dev}" ]; then
		ulogger -s -t uavpal_at_command "... no modem serial control interface available for AT command $command"
		return 1
	fi

	result=$(at_command_on_dev "$serial_ctrl_dev" "$command" "$expected_response" "$timeout")
	rc="$?"

	retry_allowed=0
	case "$command" in
	AT\^SYSINFOEX* | AT+CSQ* | AT)
		retry_allowed=1
		;;
	*)
		;;
	esac

	if [ "$rc" -ne "0" ] && [ "$retry_allowed" -eq "1" ]; then
		previous_serial_ctrl_dev="$serial_ctrl_dev"
		serial_ctrl_dev=""
		if probe_serial_ctrl_dev "$timeout" >/dev/null 2>&1 && [ -n "$serial_ctrl_dev" ] && [ "$serial_ctrl_dev" != "$previous_serial_ctrl_dev" ]; then
			result=$(at_command_on_dev "$serial_ctrl_dev" "$command" "$expected_response" "$timeout")
			rc="$?"
		else
			serial_ctrl_dev="$previous_serial_ctrl_dev"
		fi
	fi

	if [ "$rc" -ne "0" ]; then
		ulogger -s -t uavpal_at_command "... Did not receive expected output from AT command $command"
	fi
	echo "$result"
	return "$rc"
}

quectel_usbnet_mode()
{
	is_quectel_rm520n || return 1
	quectel_bind_option_driver >/dev/null 2>&1
	serial_ctrl_dev=""
	probe_serial_ctrl_dev "2" >/dev/null 2>&1
	mode_result=$(at_command 'AT+QCFG="usbnet"' "OK" "2")
	mode_rc="$?"
	echo "$mode_result" | sed -n 's/.*+QCFG: "usbnet",\([0-9][0-9]*\).*/\1/p' | tail -n 1
	return "$mode_rc"
}

quectel_cgdcont_cid_for_apn()
{
	cgdcont_text="$1"
	wanted_apn="$2"
	echo "$cgdcont_text" | awk -F',' -v wanted="$wanted_apn" '
	/\+CGDCONT:/ {
		cid = $1
		sub(/.*: */, "", cid)
		gsub(/[^0-9]/, "", cid)
		apn = $3
		gsub(/[" \r]/, "", apn)
		if (cid != "" && apn == wanted) {
			print cid
			exit
		}
	}'
}

quectel_cgdcont_apn_for_cid()
{
	cgdcont_text="$1"
	wanted_cid="$2"
	echo "$cgdcont_text" | awk -F',' -v wanted="$wanted_cid" '
	/\+CGDCONT:/ {
		cid = $1
		sub(/.*: */, "", cid)
		gsub(/[^0-9]/, "", cid)
		apn = $3
		gsub(/[" \r]/, "", apn)
		if (cid == wanted) {
			print apn
			exit
		}
	}'
}

quectel_cgdcont_first_data_cid()
{
	cgdcont_text="$1"
	echo "$cgdcont_text" | awk -F',' '
	/\+CGDCONT:/ {
		cid = $1
		sub(/.*: */, "", cid)
		gsub(/[^0-9]/, "", cid)
		apn = $3
		gsub(/[" \r]/, "", apn)
		if (cid != "" && apn != "" && apn !~ /^ims$/ && apn !~ /emergency/) {
			print cid
			exit
		}
	}'
}

quectel_cgpaddr_ipv4_for_cid()
{
	cgpaddr_text="$1"
	wanted_cid="$2"
	echo "$cgpaddr_text" | awk -F',' -v wanted="$wanted_cid" '
	/\+CGPADDR:/ {
		cid = $1
		sub(/.*: */, "", cid)
		gsub(/[^0-9]/, "", cid)
		ip = $2
		gsub(/[" \r]/, "", ip)
		if (cid == wanted && ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && ip != "0.0.0.0") {
			print ip
			exit
		}
	}'
}

quectel_qmap_rule_cid()
{
	qmap_text="$1"
	wanted_rule="$2"
	echo "$qmap_text" | awk -F',' -v wanted="$wanted_rule" '
	/\+QMAP:.*MPDN_rule/ {
		rule = $2
		cid = $3
		gsub(/[^0-9]/, "", rule)
		gsub(/[^0-9]/, "", cid)
		if (rule == wanted) {
			print cid
			exit
		}
	}'
}

quectel_qmap_rule_enabled()
{
	qmap_text="$1"
	wanted_rule="$2"
	echo "$qmap_text" | awk -F',' -v wanted="$wanted_rule" '
	/\+QMAP:.*MPDN_rule/ {
		rule = $2
		enabled = $6
		gsub(/[^0-9]/, "", rule)
		gsub(/[^0-9]/, "", enabled)
		if (rule == wanted) {
			print enabled
			exit
		}
	}'
}

quectel_qmap_status_cid()
{
	qmap_text="$1"
	wanted_rule="$2"
	echo "$qmap_text" | awk -F',' -v wanted="$wanted_rule" '
	/\+QMAP:.*MPDN_status/ {
		rule = $2
		cid = $3
		gsub(/[^0-9]/, "", rule)
		gsub(/[^0-9]/, "", cid)
		if (rule == wanted) {
			print cid
			exit
		}
	}'
}

quectel_qmap_status_active()
{
	qmap_text="$1"
	wanted_rule="$2"
	echo "$qmap_text" | awk -F',' -v wanted="$wanted_rule" '
	/\+QMAP:.*MPDN_status/ {
		rule = $2
		active = $5
		gsub(/[^0-9]/, "", rule)
		gsub(/[^0-9]/, "", active)
		if (rule == wanted) {
			print active
			exit
		}
	}'
}

quectel_require_ecm()
{
	is_quectel_rm520n || return 0
	echo "quectel_rm520n" >/tmp/modem_provider

	quectel_mode=""
	for quectel_wait in $(seq 1 10); do
		quectel_mode=$(quectel_usbnet_mode)
		if [ -n "$quectel_mode" ]; then
			break
		fi
		sleep 2
	done

	quectel_ts=$(date +%s)
	if [ "$quectel_mode" = "1" ]; then
		echo "provider=quectel_rm520n usbnet_mode=1 ecm_ok=1 error= ts=${quectel_ts}" >/tmp/uavpal_quectel_setup_diag
		ulogger -s -t uavpal_quectel "... RM520N detected in ECM usbnet=1"
		return 0
	fi

	if [ -z "$quectel_mode" ]; then
		detect_cdc_iface
		if [ "$?" -eq "0" ] && [ "$cdc_if" = "usb0" ]; then
			quectel_error="quectel_usbnet_unknown_data_iface_present"
			echo "provider=quectel_rm520n usbnet_mode= ecm_ok=1 error=${quectel_error} ts=${quectel_ts}" >/tmp/uavpal_quectel_setup_diag
			ulogger -s -t uavpal_quectel "... RM520N usbnet mode not ready over AT, but usb0 is present; continuing generic Ethernet startup"
			return 0
		fi
		quectel_error="quectel_usbnet_unknown"
		ulogger -s -t uavpal_quectel "... RM520N detected but usbnet mode could not be verified"
	else
		quectel_error="quectel_usbnet_not_ecm"
		ulogger -s -t uavpal_quectel "... RM520N usbnet=${quectel_mode}; ECM usbnet=1 is required"
	fi
	echo "provider=quectel_rm520n usbnet_mode=${quectel_mode} ecm_ok=0 error=${quectel_error} ts=${quectel_ts}" >/tmp/uavpal_quectel_setup_diag
	return 1
}

send_message()
{
	# delay sending of messages if modem is not yet online
	for i in $(seq 0 5); do
		check_connection
	done
	if [ $? -ne 0 ]; then
		ulogger -s -t uavpal_send_message "... Cannot send message (no connection). Exiting send_message function!"
		exit 1 # exit function
	fi

	if [ -z "$serial_ctrl_dev" ] && [ -f /tmp/serial_ctrl_dev ]; then
		serial_ctrl_dev=$(head -1 /tmp/serial_ctrl_dev | tr -d '\r\n' | tr -d '\n')
	fi

	phone_no="$(conf_read phonenumber)"
	if [ "$phone_no" != "+XXYYYYYYYYY" ]; then
		if [ -f "/tmp/hilink_router_ip" ]; then
			ulogger -s -t uavpal_send_message "... sending SMS to ${phone_no} (via Hi-Link API)"
			hilink_api "post" "/api/sms/send-sms" "<request><Index>-1</Index><Phones><Phone>${phone_no}</Phone></Phones><Sca></Sca><Content>${1}</Content><Length>-1</Length><Reserved>-1</Reserved><Date>-1</Date></request>"
		elif [ -n "$serial_ctrl_dev" ] && [ -c "/dev/${serial_ctrl_dev}" ]; then
			ulogger -s -t uavpal_send_message "... sending SMS to ${phone_no} (via ${serial_ctrl_dev})"
			at_command "AT+CMGF=1\rAT+CMGS=\"${phone_no}\"\r${1}\32" "OK" "2"
		else
			ulogger -s -t uavpal_send_message "... cannot send SMS: no modem serial control interface available"
		fi
	fi

	# Pushbullet notifications removed; keep SMS-only behavior.
}

connect_hilink()
{
	connect_ethernet

	hilink_ip="$modem_ip"
	hilink_router_ip="$modem_gateway_ip"
	if [ -z "$hilink_router_ip" ] && [ -n "$hilink_ip" ]; then
		hilink_router_ip="$(echo "$hilink_ip" | cut -d '.' -f 1,2,3).1"
	fi
	if [ -z "$hilink_router_ip" ]; then
		ulogger -s -t uavpal_connect_hilink "... unable to detect Hi-Link router IP"
		return 1
	fi

	echo "$hilink_router_ip" >/tmp/hilink_router_ip
	hilink_profiles=$(hilink_api "get" "/api/dialup/profiles")
	hilink_apn_index=$(echo $hilink_profiles | xmllint --xpath "string(//CurrentProfile)" -)
	hilink_apn=$(echo $hilink_profiles | xmllint --xpath "string(//Profile[${hilink_apn_index}]/ApnName)" -)
	ulogger -s -t uavpal_connect_hilink "... connecting to mobile network using APN \"${hilink_apn}\" (configured in the Hi-Link Web UI)"
}

connect_stick()
{
	ulogger -s -t uavpal_connect_stick "... running pppd to establish connection to mobile network using APN \"$(conf_read apn)\" (configured in the conf/apn file)"
	killall -9 pppd >/dev/null 2>&1
	killall -9 chat >/dev/null 2>&1
	/data/ftp/uavpal/bin/pppd \
		${serial_ppp_dev} \
		connect "/data/ftp/uavpal/bin/chat -v -f  /data/ftp/uavpal/conf/chatscript -T $(conf_read apn)" \
		noipdefault \
		defaultroute \
		replacedefaultroute \
		hide-password \
		noauth \
		persist \
		usepeerdns \
		maxfail 0 \
		lcp-echo-failure 10 \
		lcp-echo-interval 6 \
		holdoff 5

	ppp_wait_loops=250
	while [ "$ppp_wait_loops" -gt "0" ]; do
		if [ -d "/proc/sys/net/ipv4/conf/${ppp_if}" ]; then
			break
		fi
		usleep 100000
		ppp_wait_loops=$((ppp_wait_loops - 1))
	done

	if [ ! -d "/proc/sys/net/ipv4/conf/${ppp_if}" ]; then
		ulogger -s -t uavpal_connect_stick "... PPP interface \"${ppp_if}\" did not come up (serial PPP dev: ${serial_ppp_dev}, serial CTRL dev: ${serial_ctrl_dev})"
		killall -9 pppd >/dev/null 2>&1
		killall -9 chat >/dev/null 2>&1
		return 1
	fi

	ulogger -s -t uavpal_connect_stick "... interface \"${ppp_if}\" is up"
	echo "${ppp_if}" >/tmp/modem_iface
	echo "ok=1 iface=${ppp_if} gateway= ts=$(date +%s)" >/tmp/uavpal_route_diag
	apply_low_latency_queues
	echo $serial_ctrl_dev >/tmp/serial_ctrl_dev
	return 0
}

connection_handler_hilink()
{
	fail_count=0
	backoff_sec=1
	internet_soft_fail_threshold=12
	while true; do
		apply_low_latency_queues
		check_modem_link_ethernet
		link_ok=$?
		check_connection
		internet_ok=$?
		write_reconnect_diag "hilink" "$fail_count" "$link_ok" "$internet_ok" "$backoff_sec"

		if [ "$link_ok" -eq "0" ] && [ "$internet_ok" -eq "0" ]; then
			fail_count=0
			backoff_sec=1
			sleep 5
			continue
		fi

		fail_count=$((fail_count + 1))

		# If modem link still looks healthy, tolerate longer transient Internet check failures before reconnecting.
		if [ "$link_ok" -eq "0" ] && [ "$internet_ok" -ne "0" ] && [ "$fail_count" -lt "$internet_soft_fail_threshold" ]; then
			if [ "$fail_count" -eq "2" ]; then
				ulogger -s -t uavpal_connection_handler_hilink "... transient Internet check failure detected (fail_count=${fail_count}), waiting before reconnect"
			fi
			sleep 5
			continue
		fi

		# If modem link itself is bad, reconnect sooner.
		if [ "$link_ok" -ne "0" ] && [ "$fail_count" -lt "2" ]; then
			sleep 5
			continue
		fi

		ulogger -s -t uavpal_connection_handler_hilink "... reconnecting (link_ok=${link_ok}, internet_ok=${internet_ok}, fail_count=${fail_count}, backoff=${backoff_sec}s)"
		sleep "$backoff_sec"
		ulogger -s -t uavpal_connection_handler_hilink "... toggling Hi-Link data connection and renewing Ethernet session"
		hilink_api "post" "/api/dialup/mobile-dataswitch" "<request><dataswitch>0</dataswitch></request>"
		sleep 1
		hilink_api "post" "/api/dialup/mobile-dataswitch" "<request><dataswitch>1</dataswitch></request>"
		killall -9 udhcpc
		ifconfig ${cdc_if} down
		if [ -f /tmp/hilink_router_ip ]; then
			ip route del default via "$(cat /tmp/hilink_router_ip)" dev ${cdc_if} >/dev/null 2>&1
		fi
		rm -f /tmp/modem_gateway_ip /tmp/modem_ip
		sleep 1
		connect_hilink
		fail_count=0
		backoff_sec=$((backoff_sec * 2))
		if [ "$backoff_sec" -gt "10" ]; then
			backoff_sec=10
		fi
		sleep 5
	done
}

connection_handler_ethernet()
{
	fail_count=0
	backoff_sec=1
	internet_soft_fail_threshold=12
	while true; do
		apply_low_latency_queues
		ensure_ethernet_default_route "$cdc_if" >/dev/null 2>&1
		check_modem_link_ethernet
		link_ok=$?
		check_connection
		internet_ok=$?
		write_reconnect_diag "ethernet" "$fail_count" "$link_ok" "$internet_ok" "$backoff_sec"

		if [ "$link_ok" -eq "0" ] && [ "$internet_ok" -eq "0" ]; then
			fail_count=0
			backoff_sec=1
			sleep 5
			continue
		fi

		fail_count=$((fail_count + 1))

		if [ "$link_ok" -eq "0" ] && [ "$internet_ok" -ne "0" ] && zerotier_transport_ok; then
			write_reconnect_diag "ethernet" "$fail_count" "$link_ok" "$internet_ok" "$backoff_sec" "internet_degraded_zt_ok"
			if [ "$fail_count" -eq "2" ] || [ "$fail_count" -eq "$internet_soft_fail_threshold" ] || [ $((fail_count % 12)) -eq "0" ]; then
				ulogger -s -t uavpal_connection_handler_ethernet "... Internet check degraded, but ZeroTier is OK; keeping modem data path alive"
			fi
			sleep 5
			continue
		fi

		if [ "$link_ok" -eq "0" ] && [ "$internet_ok" -ne "0" ] && [ "$fail_count" -lt "$internet_soft_fail_threshold" ]; then
			if [ "$fail_count" -eq "2" ]; then
				ulogger -s -t uavpal_connection_handler_ethernet "... transient Internet check failure detected (fail_count=${fail_count}), waiting before reconnect"
			fi
			sleep 5
			continue
		fi

		if [ "$link_ok" -ne "0" ] && [ "$fail_count" -lt "2" ]; then
			sleep 5
			continue
		fi

		ulogger -s -t uavpal_connection_handler_ethernet "... reconnecting (link_ok=${link_ok}, internet_ok=${internet_ok}, fail_count=${fail_count}, backoff=${backoff_sec}s)"
		sleep "$backoff_sec"
		ulogger -s -t uavpal_connection_handler_ethernet "... renewing generic Ethernet modem session"
		killall -9 udhcpc
		ifconfig ${cdc_if} down
		if [ -f /tmp/modem_gateway_ip ]; then
			ip route del default via "$(cat /tmp/modem_gateway_ip)" dev ${cdc_if} >/dev/null 2>&1
		fi
		rm -f /tmp/modem_gateway_ip /tmp/modem_ip
		sleep 1
		connect_ethernet
		fail_count=0
		backoff_sec=$((backoff_sec * 2))
		if [ "$backoff_sec" -gt "10" ]; then
			backoff_sec=10
		fi
		sleep 5
	done
}

connection_handler_stick()
{ 
	fail_count=0
	backoff_sec=1
	internet_soft_fail_threshold=12
	while true; do
		apply_low_latency_queues
		check_modem_link_stick
		link_ok=$?
		check_connection
		internet_ok=$?
		write_reconnect_diag "stick" "$fail_count" "$link_ok" "$internet_ok" "$backoff_sec"

		if [ "$link_ok" -eq "0" ] && [ "$internet_ok" -eq "0" ]; then
			fail_count=0
			backoff_sec=1
			sleep 5
			continue
		fi

		fail_count=$((fail_count + 1))

		if [ "$link_ok" -eq "0" ] && [ "$internet_ok" -ne "0" ] && [ "$fail_count" -lt "$internet_soft_fail_threshold" ]; then
			if [ "$fail_count" -eq "2" ]; then
				ulogger -s -t uavpal_connection_handler_stick "... transient Internet check failure detected (fail_count=${fail_count}), waiting before reconnect"
			fi
			sleep 5
			continue
		fi

		if [ "$link_ok" -ne "0" ] && [ "$fail_count" -lt "2" ]; then
			sleep 5
			continue
		fi

		ulogger -s -t uavpal_connection_handler_stick "... reconnecting (link_ok=${link_ok}, internet_ok=${internet_ok}, fail_count=${fail_count}, backoff=${backoff_sec}s)"
		sleep "$backoff_sec"
		ulogger -s -t uavpal_connection_handler_stick "... restarting PPP session"
		killall -9 pppd
		killall -9 chat
		ifconfig ${ppp_if} down
		sleep 1
		connect_stick
		fail_count=0
		backoff_sec=$((backoff_sec * 2))
		if [ "$backoff_sec" -gt "10" ]; then
			backoff_sec=10
		fi
		sleep 5
	done
}

check_modem_link_ethernet()
{
	if [ -z "$cdc_if" ] || [ ! -d "/proc/sys/net/ipv4/conf/${cdc_if}" ]; then
		return 1
	fi

	ifconfig "${cdc_if}" 2>/dev/null | grep -q "RUNNING" || return 1

	modem_link_gateway=""
	if [ -f /tmp/modem_gateway_ip ]; then
		modem_link_gateway=$(head -1 /tmp/modem_gateway_ip | tr -d '\r\n' | tr -d '\n')
	fi
	if [ -z "$modem_link_gateway" ]; then
		modem_link_gateway=$(ip route 2>/dev/null | awk -v dev="$cdc_if" '$1=="default" && $5==dev {print $3; exit}')
	fi
	if [ -z "$modem_link_gateway" ]; then
		modem_link_gateway=$(route -n 2>/dev/null | awk -v dev="$cdc_if" '$1=="0.0.0.0" && $8==dev {print $2; exit}')
	fi

	# Link health should be based on modem iface and routing state only.
	# Some modems/gateways drop ICMP even when data is healthy.
	if [ -n "$modem_link_gateway" ]; then
		return 0
	fi

	return 1
}

check_modem_link_stick()
{
	if [ -z "$ppp_if" ] || [ ! -d "/proc/sys/net/ipv4/conf/${ppp_if}" ]; then
		return 1
	fi

	ifconfig "${ppp_if}" 2>/dev/null | grep -q "RUNNING" || return 1
	return 0
}

check_connection()
{
	# Prefer TCP connectivity checks over ICMP:
	# many mobile carriers/modem gateways deprioritize or block ping,
	# while application traffic over TCP is still working.
	tcp_destinations="1.1.1.1 8.8.8.8"
	nc_cmd=""
	if command -v nc >/dev/null 2>&1; then
		nc_cmd="nc"
	elif [ -x /bin/busybox ] && /bin/busybox | grep -w nc >/dev/null 2>&1; then
		nc_cmd="/bin/busybox nc"
	fi
	if [ -n "$nc_cmd" ]; then
		for check in $tcp_destinations; do
			$nc_cmd -w 2 "$check" 443 < /dev/null >/dev/null 2>&1
			if [ $? -eq 0 ]; then
				return 0
			fi
		done
	fi

	# Fallback for environments without nc.
	ping_destinations="8.8.8.8 192.5.5.241 199.7.83.42" # google-public-dns-a.google.com, f.root-servers.org, l.root-servers.org
	for check in $ping_destinations; do
		ping -W 2 -c 1 "$check" >/dev/null 2>&1
		if [ $? -eq 0 ]; then
			return 0
		fi
		sleep 1
	done

	# none of the reachability checks succeeded
	return 1
}
