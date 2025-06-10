#!/bin/bash

# Ansible System-Wide Installation Script for Ubuntu
# This script installs Ansible in /opt for all users and configures it for local execution
# Handles partial installations and can be safely re-run

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
ANSIBLE_CFG_FILE="/etc/ansible/ansible.cfg"

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

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
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

# Check if component already exists
component_exists() {
    local component="$1"
    local path="$2"
    
    case "$component" in
        "directory")
            [[ -d "$path" ]]
            ;;
        "file")
            [[ -f "$path" ]]
            ;;
        "symlink")
            [[ -L "$path" ]]
            ;;
        "user")
            getent passwd "$path" > /dev/null 2>&1
            ;;
        "group")
            getent group "$path" > /dev/null 2>&1
            ;;
        "command")
            command -v "$path" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Clean up incorrect installations
cleanup_incorrect_state() {
    log_info "Checking for incorrect installation states..."
    
    # Fix ansible.cfg if it's a directory instead of a file
    if [[ -d "$ANSIBLE_CFG_FILE" ]]; then
        log_warning "Found $ANSIBLE_CFG_FILE as directory, removing..."
        rm -rf "$ANSIBLE_CFG_FILE"
        log_success "Cleaned up incorrect ansible.cfg directory"
    fi
    
    # Check for broken symlinks
    local symlinks=("/usr/local/bin/ansible" "/usr/local/bin/ansible-playbook" "/usr/local/bin/ansible-galaxy" "/usr/local/bin/ansible-vault" "/usr/local/bin/ansible-config" "/usr/local/bin/ansible-inventory" "/usr/local/bin/ansible-doc")
    
    for symlink in "${symlinks[@]}"; do
        if [[ -L "$symlink" ]] && [[ ! -e "$symlink" ]]; then
            log_warning "Found broken symlink: $symlink, removing..."
            rm -f "$symlink"
        fi
    done
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
    
    local packages=("python3" "python3-pip" "python3-venv" "software-properties-common" "curl" "git" "sudo")
    local missing_packages=()
    
    # Check which packages are missing
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages+=("$package")
        fi
    done
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_skip "All prerequisites already installed"
        return 0
    fi
    
    log_info "Installing missing packages: ${missing_packages[*]}"
    apt install -y "${missing_packages[@]}"
    log_success "Prerequisites installed"
}

# Create necessary directories
create_directories() {
    log_info "Creating directory structure..."
    
    local directories=("$ANSIBLE_HOME" "$ANSIBLE_CONFIG" "$ANSIBLE_PLAYBOOKS" "/var/log/ansible")
    local created_any=false
    
    for dir in "${directories[@]}"; do
        if ! component_exists "directory" "$dir"; then
            mkdir -p "$dir"
            chmod 755 "$dir"
            log_info "Created directory: $dir"
            created_any=true
        fi
    done
    
    if [[ "$created_any" == "true" ]]; then
        log_success "Directory structure created"
    else
        log_skip "Directory structure already exists"
    fi
}

# Install Ansible via pip in virtual environment
install_ansible() {
    if component_exists "directory" "$ANSIBLE_VENV" && component_exists "file" "$ANSIBLE_VENV/bin/ansible"; then
        log_skip "Ansible virtual environment already exists"
        local existing_version=$("$ANSIBLE_VENV/bin/ansible" --version | head -n1)
        log_info "Existing installation: $existing_version"
    else
        log_info "Installing Ansible in $ANSIBLE_VENV..."
        
        # Remove partial installation if exists
        [[ -d "$ANSIBLE_VENV" ]] && rm -rf "$ANSIBLE_VENV"
        
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
        
        log_success "Ansible installed in virtual environment"
    fi
    
    # Create/update symlinks
    create_symlinks
}

# Create symlinks for system-wide access
create_symlinks() {
    log_info "Creating symlinks for system-wide access..."
    
    local binaries=("ansible" "ansible-playbook" "ansible-galaxy" "ansible-vault" "ansible-config" "ansible-inventory" "ansible-doc")
    local created_any=false
    
    for binary in "${binaries[@]}"; do
        local target_path="$ANSIBLE_VENV/bin/$binary"
        local symlink_path="/usr/local/bin/$binary"
        
        if [[ -f "$target_path" ]]; then
            if ! component_exists "symlink" "$symlink_path" || [[ "$(readlink "$symlink_path")" != "$target_path" ]]; then
                ln -sf "$target_path" "$symlink_path"
                log_info "Created symlink: $symlink_path -> $target_path"
                created_any=true
            fi
        fi
    done
    
    if [[ "$created_any" == "true" ]]; then
        log_success "Symlinks created"
    else
        log_skip "Symlinks already exist and are correct"
    fi
}

# Create ansible group and user (optional)
create_ansible_user() {
    local user_created=false
    local group_created=false
    
    # Create ansible group if it doesn't exist
    if ! component_exists "group" "ansible"; then
        groupadd -r ansible
        log_info "Created ansible group"
        group_created=true
    else
        log_skip "Ansible group already exists"
    fi
    
    # Create ansible user if it doesn't exist
    if ! component_exists "user" "ansible"; then
        useradd -r -g ansible -d "$ANSIBLE_HOME" -s /bin/bash -c "Ansible System User" ansible
        log_info "Created ansible user"
        user_created=true
    else
        log_skip "Ansible user already exists"
    fi
    
    # Set ownership (always do this to ensure correct permissions)
    chown -R ansible:ansible "$ANSIBLE_HOME"
    chown -R ansible:ansible "$ANSIBLE_PLAYBOOKS"
    chown -R ansible:ansible "/var/log/ansible"
    
    # Add ansible user to sudo group for privilege escalation
    if ! groups ansible | grep -q sudo; then
        usermod -aG sudo ansible
        log_info "Added ansible user to sudo group"
    else
        log_skip "Ansible user already in sudo group"
    fi
    
    # Configure sudoers for ansible user (passwordless sudo)
    if [[ ! -f "/etc/sudoers.d/ansible" ]]; then
        echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
        chmod 440 /etc/sudoers.d/ansible
        log_info "Configured passwordless sudo for ansible user"
    else
        log_skip "Sudoers configuration for ansible already exists"
    fi
    
    if [[ "$user_created" == "true" || "$group_created" == "true" ]]; then
        log_success "Ansible user and group configured"
    else
        log_success "Ansible user and group verified"
    fi
}

# Set up environment for all users
setup_environment() {
    local env_file="/etc/profile.d/ansible.sh"
    
    if component_exists "file" "$env_file"; then
        log_skip "Environment configuration already exists"
        return 0
    fi
    
    log_info "Setting up environment for all users..."
    
    # Create profile script for all users
    cat > "$env_file" << 'EOF'
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
    
    chmod 644 "$env_file"
    
    # Source the environment for current session
    source "$env_file"
    
    log_success "Environment configured for all users"
}

# Create system-wide inventory file
create_system_inventory() {
    if component_exists "file" "$ANSIBLE_INVENTORY"; then
        log_skip "System inventory already exists"
        return 0
    fi
    
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
    if component_exists "file" "$ANSIBLE_CFG_FILE"; then
        log_skip "System configuration already exists"
        return 0
    fi
    
    log_info "Creating system-wide Ansible configuration..."
    
    # Ensure the directory exists and it's not a file
    mkdir -p "$ANSIBLE_CONFIG"
    
    # Remove if it exists as directory (cleanup function should have handled this)
    [[ -d "$ANSIBLE_CFG_FILE" ]] && rm -rf "$ANSIBLE_CFG_FILE"
    
    # Create the configuration file with explicit path
    cat > "$ANSIBLE_CFG_FILE" << 'EOF'
# Ansible System-Wide Configuration
[defaults]
inventory = /etc/ansible/hosts
library = /opt/ansible/library
module_utils = /opt/ansible/module_utils
collections_path = /opt/ansible/collections:/usr/share/ansible/collections
remote_tmp = /tmp/.ansible-${USER}/tmp
local_tmp = /tmp/.ansible-${USER}/tmp
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
roles_path = /opt/ansible/playbooks/roles
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
    
    chmod 644 "$ANSIBLE_CFG_FILE"
    log_success "System-wide configuration created at $ANSIBLE_CFG_FILE"
}

# Create sample playbooks
create_sample_playbooks() {
    local playbooks_exist=false
    
    # Check if key playbooks already exist
    if component_exists "file" "$ANSIBLE_PLAYBOOKS/hello-world.yml" && component_exists "file" "$ANSIBLE_PLAYBOOKS/system-setup.yml"; then
        log_skip "Sample playbooks already exist"
        playbooks_exist=true
    fi
    
    if [[ "$playbooks_exist" == "false" ]]; then
        log_info "Creating sample playbooks..."
        
        # Create roles directory
        mkdir -p "$ANSIBLE_PLAYBOOKS/roles"
        mkdir -p "$ANSIBLE_PLAYBOOKS/group_vars"
        mkdir -p "$ANSIBLE_PLAYBOOKS/host_vars"
        mkdir -p "$ANSIBLE_PLAYBOOKS/templates"
    fi
    
    # Sample playbook for local system management
    if ! component_exists "file" "$ANSIBLE_PLAYBOOKS/system-setup.yml"; then
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
    fi

    # Create template file
    if ! component_exists "file" "$ANSIBLE_PLAYBOOKS/templates/system_info.j2"; then
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
    fi

    # Hello world playbook
    if ! component_exists "file" "$ANSIBLE_PLAYBOOKS/hello-world.yml"; then
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
    fi

    # Set proper permissions
    chown -R ansible:ansible "$ANSIBLE_PLAYBOOKS"
    chmod -R 755 "$ANSIBLE_PLAYBOOKS"
    
    if [[ "$playbooks_exist" == "false" ]]; then
        log_success "Sample playbooks created in $ANSIBLE_PLAYBOOKS"
    fi
}

# Create ansible collections directory
setup_collections() {
    local collections_path="$ANSIBLE_HOME/collections"
    
    if component_exists "directory" "$collections_path/ansible_collections"; then
        log_skip "Ansible collections already installed"
        return 0
    fi
    
    log_info "Setting up Ansible collections..."
    
    mkdir -p "$collections_path"
    
    # Install common collections
    source "$ANSIBLE_VENV/bin/activate"
    
    # Install collections with error handling
    local collections=("community.general" "ansible.posix")
    for collection in "${collections[@]}"; do
        if ! ansible-galaxy collection install "$collection" --collections-path "$collections_path" --force; then
            log_warning "Failed to install collection: $collection"
        else
            log_info "Installed collection: $collection"
        fi
    done
    
    # Set permissions
    chown -R ansible:ansible "$collections_path"
    
    log_success "Ansible collections installed"
}

# Check installation status
check_installation_status() {
    log_info "Checking current installation status..."
    
    # Check virtual environment
    if component_exists "directory" "$ANSIBLE_VENV"; then
        log_info "✓ Virtual environment exists"
    else
        log_warning "✗ Virtual environment missing"
    fi
    
    # Check symlinks
    if component_exists "command" "ansible"; then
        log_info "✓ Ansible command available"
    else
        log_warning "✗ Ansible command not available"
    fi
    
    # Check configuration
    if component_exists "file" "$ANSIBLE_CFG_FILE"; then
        log_info "✓ Configuration file exists"
    else
        log_warning "✗ Configuration file missing"
    fi
    
    # Check inventory
    if component_exists "file" "$ANSIBLE_INVENTORY"; then
        log_info "✓ Inventory file exists"
    else
        log_warning "✗ Inventory file missing"
    fi
    
    # Check user
    if component_exists "user" "ansible"; then
        log_info "✓ Ansible user exists"
    else
        log_warning "✗ Ansible user missing"
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying Ansible installation..."
    
    # Source environment
    if component_exists "file" "/etc/profile.d/ansible.sh"; then
        source "/etc/profile.d/ansible.sh"
    fi
    
    # Check Ansible version
    if component_exists "command" "ansible"; then
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
    if timeout 30 ansible local -m ping 2>/dev/null; then
        log_success "Local connection test passed"
    else
        log_warning "Local connection test failed (may work after logout/login)"
    fi
    
    # Test sample playbook
    if component_exists "file" "/opt/ansible/playbooks/hello-world.yml"; then
        log_info "Testing sample playbook..."
        if timeout 60 ansible-playbook "/opt/ansible/playbooks/hello-world.yml" 2>/dev/null; then
            log_success "Sample playbook executed successfully"
        else
            log_warning "Sample playbook test failed (may work after logout/login)"
        fi
    fi
}

# Display usage information
show_usage() {
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

# Recovery function for common issues
recover_from_issues() {
    log_info "Attempting to recover from common issues..."
    
    # Fix permissions
    if component_exists "directory" "$ANSIBLE_HOME"; then
        chown -R ansible:ansible "$ANSIBLE_HOME" 2>/dev/null || true
    fi
    
    if component_exists "directory" "/var/log/ansible"; then
        chown -R ansible:ansible "/var/log/ansible" 2>/dev/null || true
    fi
    
    # Fix broken symlinks
    local binaries=("ansible" "ansible-playbook" "ansible-galaxy" "ansible-vault" "ansible-config" "ansible-inventory" "ansible-doc")
    for binary in "${binaries[@]}"; do
        local symlink_path="/usr/local/bin/$binary"
        local target_path="$ANSIBLE_VENV/bin/$binary"
        
        if [[ -L "$symlink_path" ]] && [[ ! -e "$symlink_path" ]]; then
            rm -f "$symlink_path"
            if [[ -f "$target_path" ]]; then
                ln -sf "$target_path" "$symlink_path"
            fi
        fi
    done
    
    log_success "Recovery completed"
}

# Main installation function
main() {
    log_info "Starting Ansible system-wide installation for Ubuntu..."
    log_info "This script can be safely re-run and will handle partial installations."
    
    check_privileges
    check_ubuntu
    cleanup_incorrect_state
    check_installation_status
    
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
    
    recover_from_issues
    verify_installation
    show_usage
    
    log_success "Ansible system-wide installation and configuration completed!"
    log_info "If some tests failed, logout and login again to load environment variables."
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: sudo $0 [options]"
        echo ""
        echo "This script installs Ansible system-wide in /opt for all users."
        echo "It can be safely re-run and will handle partial installations."
        echo ""
        echo "Options:"
        echo "  --status        Show current installation status"
        echo "  --verify        Verify current installation"
        echo "  --cleanup       Clean up incorrect states and retry"
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
    --status)
        check_installation_status
        exit 0
        ;;
    --verify)
        verify_installation
        exit 0
        ;;
    --cleanup)
        cleanup_incorrect_state
        recover_from_issues
        log_success "Cleanup completed"
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
