#!/bin/bash
# Monitoring Playbook Runner
# This script runs monitoring playbooks with proper environment setup

export ANSIBLE_CONFIG="/opt/ansible/venv/ansible-monitoring.cfg"
export ANSIBLE_COLLECTIONS_PATH="/opt/ansible/collections"
export ANSIBLE_PYTHON_INTERPRETER="/opt/ansible/venv/bin/python"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <playbook.yml>"
    echo "Example: $0 playbooks/alpha/install-grafana-monitoring.yml"
    exit 1
fi

echo "Running: /opt/ansible/venv/bin/ansible-playbook $@"
echo "Config: $ANSIBLE_CONFIG"
echo ""

sudo -E "/opt/ansible/venv/bin/ansible-playbook" "$@"
