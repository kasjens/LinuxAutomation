# Linux Automation with Ansible

A comprehensive Ansible setup for Linux system automation, configuration management, and infrastructure deployment.

## 🚀 Overview

This project provides a complete Ansible automation environment with:
- **System-wide Ansible installation** in `/opt/ansible` 
- **Organized project structure** for scalable automation
- **Environment separation** (development, staging, production)
- **Collection management** with community modules
- **Sample playbooks** and roles for common tasks

## 📋 Prerequisites

- Ubuntu 20.04+ (tested on Ubuntu 24.04)
- sudo privileges
- Basic knowledge of YAML and Linux administration

## 🛠️ Installation

### Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/kasjens/linux-automation.git
   cd linux-automation
   ```

2. **Run the Ansible installation script:**
   ```bash
   sudo ./install-ansible-local.sh
   ```

3. **Logout and login** to load environment variables

4. **Verify installation:**
   ```bash
   ansible --version
   ansible local -m ping
   ```

### Manual Setup

If you prefer to set up the project structure manually:

```bash
# Create project structure
mkdir -p ~/ansible-projects
cd ~/ansible-projects

# Copy project files (if you have them)
# Or create from scratch using the structure below
```

## 📁 Project Structure

```
~/ansible-projects/                    # Main projects directory
├── ansible.cfg                        # Project-specific configuration
├── requirements.yml                   # Collections and roles
├── inventories/                       # Environment inventories
│   ├── development/
│   │   ├── hosts.yml                  # Dev servers
│   │   └── group_vars/                # Dev-specific variables
│   ├── staging/
│   │   └── hosts.yml                  # Staging servers
│   └── production/
│       └── hosts.yml                  # Production servers
├── playbooks/                         # Automation playbooks
│   ├── site.yml                       # Main deployment
│   ├── webservers.yml                 # Web server setup
│   ├── databases.yml                  # Database configuration
│   └── maintenance.yml                # System maintenance
├── roles/                             # Custom roles
│   ├── common/                        # Base system setup
│   ├── webserver/                     # Web server role
│   └── security/                      # Security hardening
├── group_vars/                        # Global variables
├── host_vars/                         # Host-specific variables
├── files/                             # Static files
├── templates/                         # Jinja2 templates
└── scripts/                           # Helper scripts
```

## 🎯 Quick Start Guide

### 1. Test Your Installation

```bash
# Check Ansible version
ansible --version

# Test local connection
ansible local -m ping

# Run sample playbook
ansible-playbook /opt/ansible/playbooks/hello.yml
```

### 2. Create Your First Playbook

```bash
cd ~/ansible-projects

# Create a simple system info playbook
cat > playbooks/system-info.yml << 'EOF'
---
- name: Gather System Information
  hosts: local
  gather_facts: yes
  tasks:
    - name: Display system facts
      debug:
        msg: |
          Hostname: {{ ansible_hostname }}
          OS: {{ ansible_distribution }} {{ ansible_distribution_version }}
          CPU: {{ ansible_processor_vcpus }} cores
          Memory: {{ (ansible_memtotal_mb/1024)|round(1) }} GB
          
    - name: Check disk usage
      shell: df -h /
      register: disk_usage
      
    - name: Show disk usage
      debug:
        var: disk_usage.stdout_lines
EOF

# Run your playbook
ansible-playbook playbooks/system-info.yml
```

### 3. Set Up Your Inventory

```bash
# Edit the development inventory
cat > inventories/development/hosts.yml << 'EOF'
---
all:
  children:
    local:
      hosts:
        localhost:
          ansible_connection: local
    
    webservers:
      hosts:
        # web01:
        #   ansible_host: 192.168.1.10
        #   ansible_user: ubuntu
    
    databases:
      hosts:
        # db01:
        #   ansible_host: 192.168.1.20
        #   ansible_user: ubuntu
EOF
```

## 🔧 Common Commands

### Basic Operations
```bash
# Test connectivity
ansible all -m ping

# Run ad-hoc commands
ansible local -m shell -a "uptime"
ansible local -m apt -a "name=htop state=present" --become

# Check syntax
ansible-playbook playbooks/site.yml --syntax-check

# Dry run (check mode)
ansible-playbook playbooks/site.yml --check --diff
```

### Deployment Commands
```bash
# Deploy to development
ansible-playbook playbooks/site.yml -i inventories/development/hosts.yml

# Deploy to specific hosts
ansible-playbook playbooks/site.yml --limit "webservers"

# Deploy with specific tags
ansible-playbook playbooks/site.yml --tags "security,monitoring"

# Deploy to production (with confirmation)
ansible-playbook playbooks/site.yml -i inventories/production/hosts.yml --ask-become-pass
```

### Collection Management
```bash
# List installed collections
ansible-galaxy collection list

# Install collections from requirements
ansible-galaxy install -r requirements.yml

# Update collections
ansible-galaxy collection install community.general --force
```

## 🛡️ Security Best Practices

### Use Ansible Vault for Secrets
```bash
# Create encrypted file
ansible-vault create group_vars/all/vault.yml

# Edit encrypted file
ansible-vault edit group_vars/all/vault.yml

# Run playbook with vault
ansible-playbook playbooks/site.yml --ask-vault-pass
```

### SSH Key Management
```bash
# Generate SSH key for automation
ssh-keygen -t ed25519 -f ~/.ssh/ansible_key -C "ansible@$(hostname)"

# Copy to remote hosts
ssh-copy-id -i ~/.ssh/ansible_key.pub user@remote-host
```

## 🔍 Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Check sudo privileges
ansible local -m shell -a "sudo whoami"

# Use become flag
ansible-playbook playbooks/site.yml --become --ask-become-pass
```

**2. SSH Connection Issues**
```bash
# Test SSH connectivity
ansible all -m ping -vvv

# Skip host key checking (for lab environments)
export ANSIBLE_HOST_KEY_CHECKING=False
```

**3. Module Not Found**
```bash
# Check collections path
ansible-config dump | grep collections_path

# Reinstall collections
ansible-galaxy collection install community.general --force
```

**4. Windows Line Endings (WSL users)**
```bash
# Fix line endings in scripts
dos2unix script-name.sh
# or
sed -i 's/\r$//' script-name.sh
```

### Debug Commands
```bash
# View configuration
ansible-config dump

# Check inventory
ansible-inventory --list

# Verbose output
ansible-playbook playbooks/site.yml -vvv

# Check logs
tail -f /var/log/ansible/ansible.log
```

## 📚 Example Use Cases

### System Administration
- **User Management**: Create users, manage SSH keys, set up sudo
- **Package Management**: Install software, update systems
- **Service Management**: Configure and manage systemd services
- **Security Hardening**: Apply security policies, configure firewalls

### Infrastructure Deployment
- **Web Servers**: Deploy Nginx, Apache, configure SSL
- **Databases**: Install and configure MySQL, PostgreSQL
- **Monitoring**: Set up Prometheus, Grafana, log aggregation
- **Container Orchestration**: Deploy Docker, manage containers

### Automation Tasks
- **Backup Automation**: Scheduled backups, rotation policies
- **Log Management**: Logrotate, centralized logging
- **Health Checks**: System monitoring, alerting
- **Compliance**: Security scanning, policy enforcement

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am 'Add my feature'`
4. Push to branch: `git push origin feature/my-feature`
5. Submit a Pull Request

### Code Standards
- Use descriptive task names
- Add comments for complex logic
- Test playbooks before committing
- Follow YAML formatting standards
- Use ansible-vault for sensitive data

## 📖 Learning Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [YAML Syntax](https://docs.ansible.com/ansible/latest/reference_appendices/YAMLSyntax.html)
- [Jinja2 Templates](https://jinja.palletsprojects.com/en/3.0.x/templates/)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/kasjens/linux-automation/issues)
- **Discussions**: [GitHub Discussions](https://github.com/kasjens/linux-automation/discussions)
- **Documentation**: Check the `docs/` directory for detailed guides

## 🏷️ Version

Current version: 1.0.0

**Changelog:**
- v1.0.0: Initial release with system-wide Ansible installation
- System-wide installation script
- Basic project structure
- Sample playbooks and roles
- Documentation and examples

---

**Happy Automating!** 🎉
