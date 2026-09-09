# Installation & Operations Runbook

This guide covers the step-by-step procedure for deploying a production-ready GitLab CI/CD platform and Runner fleet from scratch using Ansible.

---

## 1. Prerequisites Checklist

Before executing the Ansible playbooks, ensure the following prerequisites are met:

### Control Node
- Linux or macOS machine with `ansible-core >= 2.15` (tested with 2.20+).
- Python 3.10+ with `pyyaml` and `jinja2`.
- Git installed.
- Install required Ansible collections:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

### Target Infrastructure (VMs / Bare Metal)
1. **Operating System**: Supported Linux distribution (Ubuntu 22.04/24.04 LTS, Debian 12, or Rocky/AlmaLinux 9).
2. **SSH Connectivity**:
   - Passwordless SSH access using public key authentication for the Ansible user (`ansible_user`).
   - Sudo access without password (`NOPASSWD`) configured for the Ansible user.
3. **DNS Records**:
   - GitLab Web & Git: e.g., `gitlab.example.com` pointing to `gitlab-01` IP.
   - GitLab Registry: e.g., `registry.example.com` or `gitlab.example.com:5050` pointing to `gitlab-01` IP.
4. **Hardware Sizing**:
   - **GitLab Server (`gitlab-01`)**: Minimum 4 vCPU, 8 GB RAM, 50 GB SSD storage.
   - **Runner Hosts (`runner-01` .. `runner-N`)**: Minimum 2 vCPU, 4 GB RAM per host.

---

## 2. Inventory Setup

Clone the repository and duplicate the example inventory into your target environment folder (e.g., `production`):

```bash
cp -r inventories/example inventories/production
```

### Configure Hosts (`inventories/production/hosts.yml`)
```yaml
all:
  children:
    gitlab_servers:
      hosts:
        gitlab-01:
          ansible_host: 192.168.10.10
    gitlab_runners:
      hosts:
        runner-01:
          ansible_host: 192.168.10.21
          gitlab_runner_profile: general
        runner-02:
          ansible_host: 192.168.10.22
          gitlab_runner_profile: container-build
        runner-03:
          ansible_host: 192.168.10.23
          gitlab_runner_profile: deploy
```

---

## 3. Variable Configuration

### Global Settings (`inventories/production/group_vars/all.yml`)
```yaml
# Environment identifier
environment_name: "production"

# Default OS package state (present | latest) - Always 'present' in production for stability
package_state: "present"

# Optional corporate proxy settings
http_proxy: ""
https_proxy: ""
no_proxy: "localhost,127.0.0.1,192.168.10.0/24"
```

### GitLab Server Settings (`inventories/production/group_vars/gitlab_servers.yml`)
```yaml
# GitLab Package Version & Edition
gitlab_server_version: "19.3.1"
gitlab_server_edition: "ce" # 'ce' (Community) or 'ee' (Enterprise)

# Public URL (Enforces HTTPS)
gitlab_server_external_url: "https://gitlab.example.com"

# TLS Configuration (letsencrypt | custom | existing)
gitlab_server_tls_mode: "letsencrypt"
gitlab_server_letsencrypt_contact_emails:
  - "devops-alerts@example.com"

# Internal Container Registry
gitlab_registry_enable: true
gitlab_registry_external_url: "https://gitlab.example.com:5050"

# Data Backup Settings
gitlab_backup_keep_time: 604800 # 7 days retention in seconds
gitlab_backup_cron_hour: "02"
gitlab_backup_cron_minute: "30"
```

### GitLab Runners Settings (`inventories/production/group_vars/gitlab_runners.yml`)
```yaml
# Runner Package Version
gitlab_runner_version: "19.3.1"

# Target GitLab Instance URL
gitlab_runner_coordinator_url: "https://gitlab.example.com"

# Global Concurrent Job Limit on each Runner Host
gitlab_runner_concurrent: 4

# Check interval in seconds
gitlab_runner_check_interval: 5
```

---

## 4. Secret Management with Ansible Vault

Store all sensitive secrets (root passwords, runner authentication tokens, private keys) in an encrypted vault:

```bash
ansible-vault create inventories/production/group_vars/all/vault.yml
```

Inside `vault.yml`:
```yaml
# Initial root password (used during first bootstrap)
vault_gitlab_root_password: "SuperSecretSecurePassword123!"

# GitLab Runner Authentication Tokens (glrt-...)
# Generated from GitLab UI or API for each designated runner
vault_gitlab_runner_auth_tokens:
  runner-01: "glrt-xxxxxxxxxxxxxxxxxxxx"
  runner-02: "glrt-yyyyyyyyyyyyyyyyyyyy"
  runner-03: "glrt-zzzzzzzzzzzzzzzzzzzz"

# Optional: GitLab Admin API Token for programmatic runner creation
vault_gitlab_admin_api_token: ""

# Optional: SMTP / Alert credentials
vault_gitlab_smtp_password: ""
```

---

## 5. Execution Procedures

### Step 1: Pre-Flight Syntax & Connectivity Check
Verify SSH access and inventory parsing across all hosts:

```bash
ansible all -i inventories/production/hosts.yml -m ping
ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml --syntax-check
```

### Step 2: Deploy Complete Platform
Run the master orchestration playbook:

```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml --ask-vault-pass
```

### Step 3: Targeted Runs (Day-2 Operations)
When performing maintenance or partial updates, execute dedicated playbooks:

- **GitLab Server Update / Reconfigure**:
  ```bash
  ansible-playbook -i inventories/production/hosts.yml playbooks/gitlab.yml --ask-vault-pass
  ```
- **Deploy or Update Runner Fleet**:
  ```bash
  ansible-playbook -i inventories/production/hosts.yml playbooks/runners.yml --ask-vault-pass
  ```
- **Execute Platform Validation Suite**:
  ```bash
  ansible-playbook -i inventories/production/hosts.yml playbooks/validate.yml --ask-vault-pass
  ```
- **Trigger On-Demand Backup**:
  ```bash
  ansible-playbook -i inventories/production/hosts.yml playbooks/backup.yml --ask-vault-pass
  ```

---

## 6. Post-Installation Verification

Once the playbook execution finishes with `failed=0`:

1. **Web Interface Access**:
   Navigate to `https://gitlab.example.com` in your browser. Verify the TLS certificate is valid.
2. **Login as Administrator**:
   - Username: `root`
   - Password: Value configured in `vault_gitlab_root_password`.
3. **Verify Runner Fleet**:
   Navigate to **Admin Area > CI/CD > Runners** (`https://gitlab.example.com/admin/runners`).
   - Confirm all hosts (`runner-01`, `runner-02`, etc.) are listed with **Online** status.
   - Confirm tags (`general`, `container-build`, `deploy`) and executor type (`docker`) match host variables.
4. **Test Container Registry**:
   Log in to the container registry from a local or runner machine:
   ```bash
   docker login gitlab.example.com:5050 -u root -p <Personal_Access_Token>
   ```
