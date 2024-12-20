#!/bin/bash

declare -A peer_names

function echo_line() {
  local key="$1"
  local value="$2"
  local style="$3"

  if [[ -t 1 ]]; then
    echo -e "${style}\e[1m${key}\e[0m${style}: ${value}\e[0m"
  else
    echo "${key}: ${value}"
  fi
}

function load_peer_names() {
  local config_path="$1"
  local default_peer_name="(unknown)"

  local last_peer_name="${default_peer_name}"

  while IFS= read -r line; do
    if [[ "${line}" =~ ^###\ Client\ (.*) ]]; then
      last_peer_name="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^PublicKey[[:space:]]*=[[:space:]]*(.*) ]]; then
      peer_pubkey="${BASH_REMATCH[1]}"
      peer_names["${peer_pubkey}"]="${last_peer_name}"
      last_peer_name="${default_peer_name}"
    fi
  done < "${config_path}"
}

function show() {
  wg show | while IFS= read -r line; do
    if [[ "${line}" =~ ^[[:space:]]*(.*)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      if [[ "${key}" == "interface" ]]; then
        echo_line "${key}" "${value}" "\e[32m"
      elif [[ "${key}" == "peer" ]]; then
        echo_line "peer" "${peer_names["${value}"]}" "\e[33m"
        echo_line "  public key" "${value}"
      else
        echo_line "  ${key}" "${value}"
      fi
    else
      echo ""
    fi
  done
}

source /etc/wireguard/params
load_peer_names "/etc/wireguard/${SERVER_WG_NIC}.conf"
show
