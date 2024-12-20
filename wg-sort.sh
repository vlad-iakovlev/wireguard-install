#!/bin/bash

declare -a peer_names
declare -A peer_public_keys
declare -A peer_prehashed_keys
declare -A peer_allowed_ips

function load_peers() {
	local config_path="$1"

	local last_peer_name

	while IFS= read -r line; do
		if [[ "${line}" =~ ^###\ Client\ (.*) ]]; then
			last_peer_name="${BASH_REMATCH[1]}"
			peer_names+=("${last_peer_name}")
		elif [[ "${last_peer_name}" != "" ]]; then
			if [[ "${line}" =~ ^PublicKey[[:space:]]*=[[:space:]]*(.*) ]]; then
				peer_public_keys["${last_peer_name}"]="${BASH_REMATCH[1]}"
			elif [[ "${line}" =~ ^PresharedKey[[:space:]]*=[[:space:]]*(.*) ]]; then
				peer_prehashed_keys["${last_peer_name}"]="${BASH_REMATCH[1]}"
			elif [[ "${line}" =~ ^AllowedIPs[[:space:]]*=[[:space:]]*(.*) ]]; then
				peer_allowed_ips["${last_peer_name}"]="${BASH_REMATCH[1]}"
			fi
		fi
	done < "${config_path}"
}

function echo_interface() {
	echo "[Interface]"
	echo "Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64"
	echo "ListenPort = ${SERVER_PORT}"
	echo "PrivateKey = ${SERVER_PRIV_KEY}"

	if pgrep firewalld; then
		FIREWALLD_IPV4_ADDRESS=$(echo "${SERVER_WG_IPV4}" | cut -d"." -f1-3)".0"
		FIREWALLD_IPV6_ADDRESS=$(echo "${SERVER_WG_IPV6}" | sed 's/:[^:]*$/:0/')
		echo "PostUp = firewall-cmd --zone=public --add-interface=${SERVER_WG_NIC} && firewall-cmd --add-port ${SERVER_PORT}/udp && firewall-cmd --add-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS}/24 masquerade' && firewall-cmd --add-rich-rule='rule family=ipv6 source address=${FIREWALLD_IPV6_ADDRESS}/24 masquerade'"
		echo "PostDown = firewall-cmd --zone=public --add-interface=${SERVER_WG_NIC} && firewall-cmd --remove-port ${SERVER_PORT}/udp && firewall-cmd --remove-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS}/24 masquerade' && firewall-cmd --remove-rich-rule='rule family=ipv6 source address=${FIREWALLD_IPV6_ADDRESS}/24 masquerade'" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
	else
		echo "PostUp = iptables -I INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT"
		echo "PostUp = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT"
		echo "PostUp = iptables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT"
		echo "PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE"
		echo "PostUp = ip6tables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT"
		echo "PostUp = ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE"
		echo "PostDown = iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT"
		echo "PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT"
		echo "PostDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT"
		echo "PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE"
		echo "PostDown = ip6tables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT"
		echo "PostDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE"
	fi
}

function echo_peers() {
	for peer_name in "${peer_names[@]}"; do
		echo ""
		echo "### Client ${peer_name}"
		echo "[Peer]"
		echo "PublicKey = ${peer_public_keys["${peer_name}"]}"
		echo "PresharedKey = ${peer_prehashed_keys["${peer_name}"]}"
		echo "AllowedIPs = ${peer_allowed_ips["${peer_name}"]}"
	done
}

function refresh_wg() {
	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")
}

source /etc/wireguard/params
load_peers "/etc/wireguard/${SERVER_WG_NIC}.conf"
peer_names=(`printf '%s\n' "${peer_names[@]}" | sort`)
echo_interface > "/etc/wireguard/${SERVER_WG_NIC}.conf"
echo_peers >> "/etc/wireguard/${SERVER_WG_NIC}.conf"
refresh_wg
