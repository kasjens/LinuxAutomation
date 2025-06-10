#!/bin/bash

# Ansible System-Wide Installation Script for Ubuntu
# This script installs Ansible in /opt for all users and configures it for local execution

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation paths
ANSIBLE_HOME="/opt/ansible"
ANSIBLE_VENV="$ANSIBLE_HOME/venv"
ANSIBLE_CONFIG="/etc/ansible"
ANSIBLE_PLAYBOOKS="/opt/ansible/playbooks"
ANSIBLE_INVENTORY="/etc/ansible/hosts"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "This script requires root privileges or sudo access."
        log_info "Please run with: sudo $0"
        exit 1
    fi
    log_info "Running with sufficient privileges"
}

# Check Ubuntu version
check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "This script is designed for Ubuntu. Detected OS:"
        cat /etc/os-release | grep PRETTY_NAME
        exit 1
    fi
    
    local ubuntu_version=$(lsb_release -rs)
    log_info "Detected Ubuntu version: $ubuntu_version"
}

# Update package lists
update_packages() {
    log_info "Updating package lists..."
    apt update
    log_success "Package lists updated"
}

# Install prerequisites
install_prerequisites() {
    log_info "Installing prerequisites..."
    apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        software-properties-common \
        curl \
        git \
        sudo
    log_success "Prerequisites installed"
}

# Create necessary directories
create_directories() {
    log_info "Creating directory structure..."
    
    # Create main directories
    mkdir -p "$ANSIBLE_HOME"
    mkdir -p "$ANSIBLE_CONFIG"
    mkdir -p "$ANSIBLE_PLAYBOOKS"
    mkdir -p "/var/log/ansible"
    
    # Set proper permissions
    chmod 755 "$ANSIBLE_HOME"
    chmod 755 "$ANSIBLE_CONFIG"
    chmod 755 "$ANSIBLE_PLAYBOOKS"
    chmod 755 "/var/log/ansible"
    
    log_success "Directory structure created"
}

# Install Ansible via pip in virtual environment
install_ansible() {
    log_info "Installing Ansible in $ANSIBLE_VENV..."
    
    # Create virtual environment
    python3 -m venv "$ANSIBLE_VENV"
    
    # Activate virtual environment and install
    source "$ANSIBLE_VENV/bin/activate"
    
    # Upgrade pip
    python3 -m pip install --upgrade pip
    
    # Install Ansible and useful modules
    python3 -m pip install \
        ansible \
        ansible-core \
        jmespath \
        netaddr \
        dnspython
    
    # Create symlinks for system-wide access
    ln -sf "$ANSIBLE_VENV/bin/ansible" /usr/local/bin/ansible
    ln -sf "$ANSIBLE_VENV/bin/ansible-playbook" /usr/local/bin/ansible-playbook
    ln -sf "$ANSIBLE_VENV/bin/ansible-galaxy" /usr/local/bin/ansible-galaxy
    ln -sf "$ANSIBLE_VENV/bin/ansible-vault" /usr/local/bin/ansible-vault
    ln -sf "$ANSIBLE_VENV/bin/ansible-config" /usr/local/bin/ansible-config
    ln -sf "$ANSIBLE_VENV/bin/ansible-inventory" /usr/local/bin/ansible-inventory
    ln -sf "$ANSIBLE_VENV/bin/ansible-doc" /usr/local/bin/ansible-doc
    
    log_success "Ansible installed in virtual environment"
}

# Create system-wide inventory file
create_system_inventory() {
    log_info "Creating system-wide inventory file..."
    
    cat > "$ANSIBLE_INVENTORY" << 'EOF'
# Ansible System-Wide Inventory
[local]
localhost ansible_connection=local

[local:vars]
ansible_python_interpreter=/usr/bin/python3

# Example groups for local management
[workstations]
# Add workstation hostnames here

[servers]
# Add server hostnames here

[all:vars]
# Global variables
ansible_user=ansible
ansible_become=yes
ansible_become_method=sudo
EOF
    
    chmod 644 "$ANSIBLE_INVENTORY"
    log_success "System-wide inventory created at $ANSIBLE_INVENTORY"
}

# Create system-wide ansible.cfg
create_system_config() {
    log_info "Creating system-wide Ansible configuration..."
    
    # Ensure the directory exists
    mkdir -p "$ANSIBLE_CONFIG"
    
    # Create the configuration file with explicit path
    cat > "/etc/ansible/ansible.cfg" << 'EOF'
# Ansible System-Wide Configuration
[defaults]
inventory = $ANSIBLE_INVENTORY
library = $ANSIBLE_HOME/library
module_utils = $ANSIBLE_HOME/module_utils
remote_tmp = /tmp/.ansible-\${USER}/tmp
local_tmp = /tmp/.ansible-\${USER}/tmp
forks = 5
poll_interval = 15
sudo_user = root
ask_sudo_pass = False
ask_pass = False
transport = smart
remote_port = 22
module_lang = C
module_set_locale = False
gathering = implicit
gather_subset = all
gather_timeout = 10
roles_path = $ANSIBLE_PLAYBOOKS/roles
host_key_checking = False
stdout_callback = yaml
callback_whitelist = timer, mail
ansible_managed = Ansible managed: {file} modified on %Y-%m-%d %H:%M:%S by {uid} on {host}
display_skipped_hosts = False
display_ok_hosts = True
display_failed_stderr = True
system_warnings = True
deprecation_warnings = True
command_warnings = False
bin_ansible_callbacks = True
nocows = 1
retry_files_enabled = False
retry_files_save_path = /var/log/ansible
log_path = /var/log/ansible/ansible.log

[inventory]
enable_plugins = host_list, script, auto, yaml, ini, toml

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[paramiko_connection]
record_host_keys = False

[ssh_connection]
ssh_args = -C -o ControlMaster=auto -o ControlPersist=60s
control_path_dir = /tmp/.ansible-cp
control_path = %(directory)s/ansible-ssh-%%h-%%p-%%r
pipelining = True
scp_if_ssh = True
transfer_method = smart

[persistent_connection]
connect_timeout = 30
command_timeout = 30

[accelerate]
accelerate_port = 5099
accelerate_timeout = 30
accelerate_connect_timeout = 5.0
accelerate_daemon_timeout = 30

[selinux]
special_context_filesystems = nfs,vboxsf,fuse,ramfs,9p

[colors]
highlight = white
verbose = blue
warn = bright purple
error = red
debug = dark gray
deprecate = purple
skip = cyan
unreachable = red
ok = green
changed = yellow
diff_add = green
diff_remove = red
diff_lines = cyan
EOF
    
    chmod 644 "/etc/ansible/ansible.cfg"
    log_success "System-wide configuration created at /etc/ansible/ansible.cfg"
}

# Set up environment for all users
setup_environment() {
    log_info "Setting up environment for all users..."
    
    # Create profile script for all users
    cat > "/etc/profile.d/ansible.sh" << 'EOF'
# Ansible Environment Setup
export ANSIBLE_CONFIG="/etc/ansible/ansible.cfg"
export ANSIBLE_HOME="/opt/ansible"
export ANSIBLE_INVENTORY="/etc/ansible/hosts"
export ANSIBLE_PLAYBOOKS="/opt/ansible/playbooks"
export ANSIBLE_LOG_PATH="/var/log/ansible/ansible.log"

# Add ansible bin to PATH if not already there
if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    export PATH="/usr/local/bin:$PATH"
fi
EOF
    
    chmod 644 "/etc/profile.d/ansible.sh"
    
    # Source the environment for current session
    source "/etc/profile.d/ansible.sh"
    
    log_success "Environment configured for all users"
}

# Create ansible group and user (optional)
create_ansible_user() {
    log_info "Creating ansible system user and group..."
    
    # Create ansible group if it doesn't exist
    if ! getent group ansible > /dev/null 2>&1; then
        groupadd -r ansible
        log_info "Created ansible group"
    fi
    
    # Create ansible user if it doesn't exist
    if ! getent passwd ansible > /dev/null 2>&1; then
        useradd -r -g ansible -d "$ANSIBLE_HOME" -s /bin/bash -c "Ansible System User" ansible
        log_info "Created ansible user"
    fi
    
    # Set ownership
    chown -R ansible:ansible "$ANSIBLE_HOME"
    chown -R ansible:ansible "$ANSIBLE_PLAYBOOKS"
    chown -R ansible:ansible "/var/log/ansible"
    
    # Add ansible user to sudo group for privilege escalation
    usermod -aG sudo ansible
    
    # Configure sudoers for ansible user (passwordless sudo)
    echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
    chmod 440 /etc/sudoers.d/ansible
    
    log_success "Ansible user and group configured"
}

# Create sample playbooks
create_sample_playbooks() {
    log_info "Creating sample playbooks..."
    
    # Create roles directory
    mkdir -p "$ANSIBLE_PLAYBOOKS/roles"
    mkdir -p "$ANSIBLE_PLAYBOOKS/group_vars"
    mkdir -p "$ANSIBLE_PLAYBOOKS/host_vars"
    
    # Sample playbook for local system management
    cat > "$ANSIBLE_PLAYBOOKS/system-setup.yml" << 'EOF'
---
# System Setup Playbook for Local Management
- name: Local System Setup and Configuration
  hosts: local
  gather_facts: yes
  become: yes
  vars:
    common_packages:
      - htop
      - vim
      - curl
      - wget
      - git
      - tree
      - unzip
  
  tasks:
    - name: Display system information
      debug:
        msg: |
          Managing local system: {{ ansible_hostname }}
          OS: {{ ansible_os_family }}
          Distribution: {{ ansible_distribution }} {{ ansible_distribution_version }}
          Architecture: {{ ansible_architecture }}
          Python: {{ ansible_python_version }}
    
    - name: Update package cache
      apt:
        update_cache: yes
        cache_valid_time: 3600
    
    - name: Install common packages
      apt:
        name: "{{ common_packages }}"
        state: present
    
    - name: Ensure log directory exists
      file:
        path: /var/log/ansible
        state: directory
        owner: ansible
        group: ansible
        mode: '0755'
    
    - name: Create system info file
      template:
        src: system_info.j2
        dest: /tmp/system_info.txt
        mode: '0644'
      vars:
        timestamp: "{{ ansible_date_time.iso8601 }}"
    
    - name: Display completion message
      debug:
        msg: "System setup completed successfully!"
EOF

    # Create template directory and file
    mkdir -p "$ANSIBLE_PLAYBOOKS/templates"
    cat > "$ANSIBLE_PLAYBOOKS/templates/system_info.j2" << 'EOF'
System Information Report
=========================
Generated by Ansible on {{ timestamp }}

Hostname: {{ ansible_hostname }}
FQDN: {{ ansible_fqdn }}
Operating System: {{ ansible_distribution }} {{ ansible_distribution_version }}
Kernel: {{ ansible_kernel }}
Architecture: {{ ansible_architecture }}
CPU Cores: {{ ansible_processor_vcpus }}
Memory: {{ (ansible_memtotal_mb / 1024) | round(2) }} GB
Disk Usage: {{ ansible_mounts[0].size_total | filesizeformat }}

Network Interfaces:
{% for interface in ansible_interfaces %}
  {{ interface }}: {{ ansible_default_ipv4.address if interface == ansible_default_ipv4.interface else 'N/A' }}
{% endfor %}

Ansible Version: {{ ansible_version.full }}
Python Version: {{ ansible_python_version }}
EOF

    # Hello world playbook
    cat > "$ANSIBLE_PLAYBOOKS/hello-world.yml" << 'EOF'
---
# Simple Hello World Playbook
- name: Hello World from Ansible
  hosts: local
  gather_facts: no
  tasks:
    - name: Say hello
      debug:
        msg: "Hello World! Ansible is working correctly on {{ inventory_hostname }}"
    
    - name: Show current date and time
      debug:
        msg: "Current date/time: {{ ansible_date_time.iso8601 }}"
      when: ansible_date_time is defined
EOF

    # Set proper permissions
    chown -R ansible:ansible "$ANSIBLE_PLAYBOOKS"
    chmod -R 755 "$ANSIBLE_PLAYBOOKS"
    
    log_success "Sample playbooks created in $ANSIBLE_PLAYBOOKS"
}

# Create ansible collections directory
setup_collections() {
    log_info "Setting up Ansible collections..."
    
    local collections_path="$ANSIBLE_HOME/collections"
    mkdir -p "$collections_path"
    
    # Install common collections
    source "$ANSIBLE_VENV/bin/activate"
    ansible-galaxy collection install community.general --collections-path "$collections_path"
    ansible-galaxy collection install ansible.posix --collections-path "$collections_path"
    
    # Set permissions
    chown -R ansible:ansible "$collections_path"
    
    log_success "Ansible collections installed"
}

# Verify installation
verify_installation() {
    log_info "Verifying Ansible installation..."
    
    # Source environment
    source "/etc/profile.d/ansible.sh"
    
    # Check Ansible version
    if command -v ansible &> /dev/null; then
        local ansible_version=$(ansible --version | head -n1)
        log_success "Ansible installed: $ansible_version"
    else
        log_error "Ansible command not found"
        return 1
    fi
    
    # Check configuration
    log_info "Testing configuration..."
    if ansible-config dump &> /dev/null; then
        log_success "Configuration is valid"
    else
        log_error "Configuration test failed"
        return 1
    fi
    
    # Test local connection
    log_info "Testing local connection..."
    if ansible local -m ping; then
        log_success "Local connection test passed"
    else
        log_error "Local connection test failed"
        return 1
    fi
    
    # Test sample playbook
    log_info "Testing sample playbook..."
    if ansible-playbook "/opt/ansible/playbooks/hello-world.yml"; then
        log_success "Sample playbook executed successfully"
    else
        log_error "Sample playbook execution failed"
        return 1
    fi
}

# Display usage information
show_usage() {
    source "/etc/profile.d/ansible.sh"
    
    cat << EOF

${GREEN}Ansible System-Wide Installation Complete!${NC}

${BLUE}Installation Locations:${NC}
  Ansible Home:       /opt/ansible
  Configuration:      /etc/ansible/ansible.cfg
  Inventory:          /etc/ansible/hosts
  Playbooks:          /opt/ansible/playbooks
  Virtual Environment: /opt/ansible/venv
  Log Files:          /var/log/ansible/

${BLUE}Quick Start Commands (available to all users):${NC}
  ansible --version                        # Check version
  ansible local -m ping                    # Test connection
  ansible local -m setup                   # Gather facts
  ansible-playbook /opt/ansible/playbooks/hello-world.yml
  ansible-playbook /opt/ansible/playbooks/system-setup.yml

${BLUE}User Management:${NC}
  System user:        ansible (passwordless sudo)
  All users can run:  ansible commands from /usr/local/bin/
  Environment:        Configured in /etc/profile.d/ansible.sh

${BLUE}Example Commands:${NC}
  # Run ad-hoc commands locally
  ansible local -m shell -a "uptime"
  ansible local -m apt -a "name=htop state=present"
  
  # Manage system configuration
  ansible-playbook /opt/ansible/playbooks/system-setup.yml
  
  # Check logs
  tail -f /var/log/ansible/ansible.log

${BLUE}File Permissions:${NC}
  - All users can read configuration and inventory
  - Playbooks directory: /opt/ansible/playbooks (group writeable for ansible group)
  - Logs: /var/log/ansible/ (ansible user/group)

${BLUE}Next Steps:${NC}
  1. Add users to 'ansible' group: usermod -aG ansible username
  2. Logout and login to load environment variables
  3. Start creating your playbooks in /opt/ansible/playbooks
  4. Customize inventory in /etc/ansible/hosts

${BLUE}Documentation:${NC}
  Official docs: https://docs.ansible.com/
  Configuration: cat /etc/ansible/ansible.cfg
  Inventory: cat /etc/ansible/hosts

EOF
}

# Main installation function
main() {
    log_info "Starting Ansible system-wide installation for Ubuntu..."
    
    check_privileges
    check_ubuntu
    update_packages
    install_prerequisites
    create_directories
    install_ansible
    create_ansible_user
    setup_environment
    create_system_inventory
    create_system_config
    create_sample_playbooks
    setup_collections
    verify_installation
    show_usage
    
    log_success "Ansible system-wide installation and configuration completed!"
    log_info "Please logout and login again to load environment variables for all users."
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: sudo $0 [options]"
        echo ""
        echo "This script installs Ansible system-wide in /opt for all users."
        echo ""
        echo "Options:"
        echo "  --help, -h      Show this help message"
        echo ""
        echo "Installation locations:"
        echo "  /opt/ansible/           - Ansible installation"
        echo "  /etc/ansible/           - Configuration and inventory"
        echo "  /opt/ansible/playbooks/ - Shared playbooks directory"
        echo "  /var/log/ansible/       - Log files"
        echo ""
        exit 0
        ;;
esac

# Check if running with sudo
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root or with sudo"
    log_info "Usage: sudo $0"
    exit 1
fi

# Run main function
main "$@"
