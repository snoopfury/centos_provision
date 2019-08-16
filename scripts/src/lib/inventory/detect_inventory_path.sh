#!/usr/bin/env bash

detect_inventory_path(){
  paths=("${INVENTORY_PATH}" /root/.keitaro/installer_config .keitaro/installer_config /root/hosts.txt hosts.txt)
  for path in "${paths[@]}"; do
    if [[ -f "${path}" ]]; then
      DETECTED_INVENTORY_PATH="${path}"
      return
    fi
  done
  debug "Inventory file not found"
}
