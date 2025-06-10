#!/bin/bash

# Lean Ansible System-Wide Installation Script for Ubuntu
# Installs Ansible in /opt for all users with proper permissions and configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Installation paths
ANSIBLE_HOME="/opt/ansible"
ANSIBLE_VENV="$ANSIBLE_HOME/venv"
ANSIBLE_CONFIG="/etc/ansible"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; }

# Check privileges
check_privileges() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "This script requires root privileges. Run with: sudo $0"
        exit 1
    fi
}

# Check Ubuntu
check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "This script is designed for Ubuntu only"
        exit 1
    fi
    log_info "Ubuntu $(lsb_release -rs) detected"
}

# Clean up any incorrect states
cleanup_incorrect_state() {
    # Fix ansible.cfg if it's a directory
    if [[ -d "/etc/ansible/ansible.cfg" ]]; then
        rm -rf "/etc/ansible/ansible.cfg"
    fi
    
    # Remove broken symlinks
    for cmd in ansible ansible-playbook ansible-galaxy ansible-vault ansible-config ansible-inventory ansible-doc; do
        local symlink_path="/usr/local/bin/$cmd"
        if [[ -L "$symlink_path" ]] && [[ ! -e "$symlink_path" ]]; then
            rm -f "$symlink_path"
        fi
    done
}

# Install prerequisites
install_prerequisites() {
    log_info "Installing prerequisites..."
    apt update -qq
    apt install -y python3 python3-pip python3-venv software-properties-common curl git sudo
}

# Create directory structure
create_directories() {
    log_info "Setting up directories..."
    mkdir -p "$ANSIBLE_HOME" "$ANSIBLE_CONFIG" "$ANSIBLE_HOME/playbooks" "$ANSIBLE_HOME/collections"
    
    # Create log directory with proper permissions for all users
    mkdir -p /var/log/ansible
    chmod 755 /var/log/ansible
    touch /var/log/ansible/ansible.log
    chmod 666 /var/log/ansible/ansible.log  # Allow all users to write
}

# Install Ansible
install_ansible() {
    if [[ -f "$ANSIBLE_VENV/bin/ansible" ]]; then
        log_skip "Ansible already installed"
        return 0
    fi
    
    log_info "Installing Ansible..."
    python3 -m venv "$ANSIBLE_VENV"
    source "$ANSIBLE_VENV/bin/activate"
    pip install --upgrade pip
    pip install ansible jmespath netaddr dnspython
    
    # Create symlinks for system-wide access
    for cmd in ansible ansible-playbook ansible-galaxy ansible-vault ansible-config ansible-inventory ansible-doc; do
        ln -sf "$ANSIBLE_VENV/bin/$cmd" "/usr/local/bin/$cmd"
    done
    
    log_success "Ansible installed"
}

# Create ansible user
create_ansible_user() {
    if getent passwd ansible > /dev/null 2>&1; then
        log_skip "Ansible user already exists"
    else
        log_info "Creating ansible user..."
        groupadd -r ansible 2>/dev/null || true
        useradd -r -g ansible -d "$ANSIBLE_HOME" -s /bin/bash -c "Ansible System User" ansible
        usermod -aG sudo ansible
        echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
        chmod 440 /etc/sudoers.d/ansible
    fi
    
    # Always fix ownership
    chown -R ansible:ansible "$ANSIBLE_HOME" /var/log/ansible
}

# Setup environment
setup_environment() {
    if [[ -f "/etc/profile.d/ansible.sh" ]]; then
        log_skip "Environment already configured"
        return 0
    fi
    
    log_info "Configuring environment..."
    cat > "/etc/profile.d/ansible.sh" << 'EOF'
# Ansible Environment
export ANSIBLE_CONFIG="/etc/ansible/ansible.cfg"
export ANSIBLE_HOME="/opt/ansible"
export ANSIBLE_INVENTORY="/etc/ansible/hosts"
export PATH="/usr/local/bin:$PATH"
EOF
    chmod 644 "/etc/profile.d/ansible.sh"
    source "/etc/profile.d/ansible.sh"
}

# Create inventory
create_inventory() {
    if [[ -f "/etc/ansible/hosts" ]]; then
        log_skip "Inventory already exists"
        return 0
    fi
    
    log_info "Creating inventory..."
    cat > "/etc/ansible/hosts" << 'EOF'
# Ansible Inventory
[local]
localhost ansible_connection=local

[local:vars]
ansible_python_interpreter=/usr/bin/python3
EOF
    chmod 644 "/etc/ansible/hosts"
}

# Create configuration
create_config() {
    if [[ -f "/etc/ansible/ansible.cfg" ]]; then
        log_skip "Configuration already exists"
        return 0
    fi
    
    log_info "Creating configuration..."
    cat > "/etc/ansible/ansible.cfg" << 'EOF'
[defaults]
inventory = /etc/ansible/hosts
collections_path = /opt/ansible/collections:/usr/share/ansible/collections
roles_path = /opt/ansible/playbooks/roles
host_key_checking = False
stdout_callback = yaml
retry_files_enabled = False
log_path = /var/log/ansible/ansible.log
nocows = 1

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
ssh_args = -C -o ControlMaster=auto -o ControlPersist=60s
EOF
    chmod 644 "/etc/ansible/ansible.cfg"
}

# Create sample playbook
create_sample_playbook() {
    local playbook="/opt/ansible/playbooks/hello.yml"
    if [[ -f "$playbook" ]]; then
        log_skip "Sample playbook already exists"
        return 0
    fi
    
    log_info "Creating sample playbook..."
    mkdir -p "/opt/ansible/playbooks"
    cat > "$playbook" << 'EOF'
---
- name: Hello World
  hosts: local
  gather_facts: yes
  tasks:
    - name: Display system info
      debug:
        msg: |
          Hello from Ansible!
          Host: {{ ansible_hostname }}
          OS: {{ ansible_distribution }} {{ ansible_distribution_version }}
          Architecture: {{ ansible_architecture }}
    
    - name: Create test file
      copy:
        content: "Ansible is working! {{ ansible_date_time.iso8601 }}"
        dest: /tmp/ansible-test.txt
        mode: '0644'
EOF
    chown -R ansible:ansible "/opt/ansible/playbooks"
}

# Install collections
install_collections() {
    if [[ -d "/opt/ansible/collections/ansible_collections/community" ]]; then
        log_skip "Collections already installed"
        return 0
    fi
    
    log_info "Installing collections..."
    source "$ANSIBLE_VENV/bin/activate"
    ansible-galaxy collection install community.general --collections-path /opt/ansible/collections
    ansible-galaxy collection install ansible.posix --collections-path /opt/ansible/collections
    chown -R ansible:ansible /opt/ansible/collections
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Test ansible command
    if ! ansible --version > /dev/null 2>&1; then
        log_error "Ansible command failed"
        return 1
    fi
    
    # Test configuration
    if ! ansible-config dump > /dev/null 2>&1; then
        log_error "Configuration test failed"
        return 1
    fi
    
    # Test local connection
    if ! timeout 30 ansible local -m ping > /dev/null 2>&1; then
        log_warning "Ping test failed (may need logout/login)"
    fi
    
    # Test collections
    if ansible-galaxy collection list | grep -q community.general; then
        log_success "Collections verified"
    else
        log_warning "Collections may not be properly configured"
    fi
    
    log_success "Installation verified"
}

# Show usage
show_usage() {
    cat << EOF

${GREEN}Ansible Installation Complete!${NC}

${BLUE}Quick Commands:${NC}
  ansible --version                    # Check version
  ansible local -m ping                # Test connection
  ansible local -m setup               # Gather system facts
  ansible-playbook /opt/ansible/playbooks/hello.yml

${BLUE}Files Created:${NC}
  /opt/ansible/                        # Installation directory
  /etc/ansible/ansible.cfg             # Configuration
  /etc/ansible/hosts                   # Inventory
  /opt/ansible/playbooks/hello.yml     # Sample playbook
  /var/log/ansible/ansible.log         # Log file

${BLUE}Next Steps:${NC}
  1. Logout and login to load environment
  2. Run: ansible-playbook /opt/ansible/playbooks/hello.yml
  3. Create your playbooks in /opt/ansible/playbooks/
  4. Add remote hosts to /etc/ansible/hosts

${BLUE}Documentation:${NC}
  https://docs.ansible.com/

EOF
}

# Main function
main() {
    log_info "Starting lean Ansible installation..."
    
    check_privileges
    check_ubuntu
    cleanup_incorrect_state
    install_prerequisites
    create_directories
    install_ansible
    create_ansible_user
    setup_environment
    create_inventory
    create_config
    create_sample_playbook
    install_collections
    verify_installation
    show_usage
    
    log_success "Installation completed! Please logout and login to activate environment."
}

# Handle arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: sudo $0"
        echo "Installs Ansible system-wide in /opt for all users"
        exit 0
        ;;
    --verify)
        verify_installation
        exit 0
        ;;
esac

# Check if running with sudo
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run with sudo"
    exit 1
fi

main "$@"
