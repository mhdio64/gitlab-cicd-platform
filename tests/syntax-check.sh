#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

INVENTORY="${ROOT_DIR}/inventories/example/hosts.yml"

echo "==> Validating Ansible inventory..."
ansible-inventory -i "${INVENTORY}" --list > /dev/null

echo "==> Running playbook syntax checks..."
PLAYBOOKS=("site.yml" "gitlab.yml" "runners.yml" "validate.yml" "backup.yml")

for pb in "${PLAYBOOKS[@]}"; do
    pb_path="${ROOT_DIR}/playbooks/${pb}"
    if [[ -f "${pb_path}" ]]; then
        echo "Checking syntax: ${pb}"
        ansible-playbook -i "${INVENTORY}" "${pb_path}" --syntax-check
    else
        echo "Playbook ${pb} not yet created, skipping."
    fi
done

echo "==> Syntax checks completed!"
