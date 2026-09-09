# Backup & Disaster Recovery Runbook

This document details the automated backup architecture, retention policies, and the complete step-by-step disaster recovery restore procedure.

---

## 1. Backup Architecture

A functional GitLab backup requires two distinct components:

```text
GitLab Server Storage
│
├── 1. Application Data Backup (Tarball)
│   ├── Git Repositories (Gitaly)
│   ├── PostgreSQL Database
│   ├── Uploads, CI Artifacts, Packages, LFS
│   └── Path: /var/opt/gitlab/backups/<TIMESTAMP>_gitlab_backup.tar
│
└── 2. Secrets & Configuration Backup (Tarball/Encrypted Archive)
    ├── /etc/gitlab/gitlab.rb
    ├── /etc/gitlab/gitlab-secrets.json (CRITICAL: Database encryption keys)
    └── /etc/gitlab/trusted-certs / ssl
```

> [!CAUTION]
> **Why Secrets Must Be Backed Up Separately**:
> For security reasons, the standard GitLab Omnibus backup command (`gitlab-backup create`) deliberately **does NOT** include `/etc/gitlab/gitlab-secrets.json` or `/etc/gitlab/gitlab.rb`.
> If you lose `gitlab-secrets.json`, your database backup is **unrecoverable** because all encrypted database fields (two-factor tokens, CI/CD variables, project tokens) cannot be decrypted!
> The `gitlab_backup` role ensures **both** components are backed up and archived together securely.

---

## 2. Automated Scheduling & Retention

The `gitlab_backup` role sets up a system cron job on the GitLab Server:

### Configuration Variables (`group_vars/gitlab_servers.yml`)
```yaml
# Backup retention in seconds (default: 604800 seconds = 7 days)
gitlab_backup_keep_time: 604800

# Daily Cron Schedule
gitlab_backup_cron_hour: "02"
gitlab_backup_cron_minute: "30"

# Local backup directory
gitlab_backup_path: "/var/opt/gitlab/backups"

# Configuration archive destination (restricted permissions: 0700)
gitlab_backup_config_path: "/var/opt/gitlab/config-backups"
```

### Triggering an On-Demand Backup via Ansible
```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/backup.yml --ask-vault-pass
```

---

## 3. Step-by-Step Disaster Recovery & Restore Runbook

Follow this exact sequence to restore GitLab onto a fresh or recovered virtual machine:

### Prerequisites for Recovery Host
- Same Linux distribution and architecture.
- Network and DNS configured to route traffic to the recovery host.
- **Exact same version and edition of GitLab installed**:
  A backup created on GitLab `17.4.2-ce` **cannot** be restored directly to `17.5.x` or Enterprise Edition without migration.

---

### Step 1: Install Exact GitLab Version on Recovery Machine
Run the GitLab server playbook to install the matching version:
```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/gitlab.yml --ask-vault-pass
```

### Step 2: Restore Configuration & Secrets
Copy the configuration backup archive to the recovery host and unpack `/etc/gitlab`:

```bash
# On recovery server:
tar -xzf /path/to/gitlab_config_backup_<TIMESTAMP>.tar.gz -C /etc/gitlab/

# Verify permissions
chmod 600 /etc/gitlab/gitlab-secrets.json
chmod 600 /etc/gitlab/gitlab.rb

# Apply configuration
gitlab-ctl reconfigure
```

### Step 3: Copy Application Data Tarball to Backup Directory
Place the data tarball into the backup path and ensure ownership belongs to `git`:

```bash
cp <TIMESTAMP>_gitlab_backup.tar /var/opt/gitlab/backups/
chown git:git /var/opt/gitlab/backups/<TIMESTAMP>_gitlab_backup.tar
```

### Step 4: Stop Database Clients
Before restoring database tables, stop the services that connect to PostgreSQL:

```bash
gitlab-ctl stop puma
gitlab-ctl stop sidekiq

# Verify status
gitlab-ctl status
```

### Step 5: Execute Application Restore
Run the restore command with the backup timestamp prefix:

```bash
# Example timestamp: 1725890000_2026_09_09_17.4.2
gitlab-backup restore BACKUP=1725890000_2026_09_09_17.4.2
```
*When prompted to overwrite existing database tables and rewrite authorized keys, confirm with `yes`.*

### Step 6: Restart and Verify Health
Restart all GitLab services:

```bash
gitlab-ctl restart

# Run diagnostic sanity checks
gitlab-rake gitlab:check SANITIZE=true
```

### Step 7: Re-Verify Runner Fleet Connectivity
Once GitLab is running, verify that existing runners reconnect:
```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/runners.yml --ask-vault-pass
```
All runners should transition back to **Online** status in the GitLab Admin interface.
