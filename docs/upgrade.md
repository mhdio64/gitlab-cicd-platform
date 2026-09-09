# Upgrade & Maintenance Policy

This document details the version pinning strategy, supported upgrade paths, pre-upgrade checklists, and controlled execution procedures for GitLab Server and Runner fleet updates.

---

## 1. Version Pinning Strategy

To ensure zero accidental or uncontrolled production outages, this platform enforces explicit **version pinning**:

- **No `latest` Tags**: The variables `gitlab_server_version` and `gitlab_runner_version` must be set to explicit semantic version numbers (e.g., `17.4.2`).
- **Package Hold / Versionlock**: On both Debian/Ubuntu (`apt-mark hold`) and RHEL/Rocky (`versionlock`), the installed packages are locked. Running generic OS upgrades (`apt upgrade` or `dnf upgrade`) will never inadvertently update GitLab or GitLab Runner.
- **Controlled Operation**: Upgrades are treated as conscious, planned maintenance events executed through Ansible playbooks.

---

## 2. Official GitLab Upgrade Path Policy

GitLab does **not** support skipping major or certain minor releases during upgrades. You must follow the official multi-step upgrade path:

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Current Ver  │ ──> │ Required     │ ──> │ Latest Minor │ ──> │ Next Major   │
│ (e.g. 16.11) │     │ Stop 17.0.x  │     │ Stop 17.3.x  │     │ (e.g. 17.4.x)│
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

> [!IMPORTANT]
> **Check Required Upgrade Stops**:
> Before choosing a target version, consult the [GitLab Official Upgrade Path Tool](https://gitlab-com.gitlab.io/support/toolbox/upgrade-path/).
> Ensure all **Batched Background Migrations** from the previous version have fully finished before applying the next version.

---

## 3. Pre-Upgrade Checklist

Before initiating any GitLab server upgrade:

1. **Verify Background Migrations are Completed**:
   SSH into `gitlab-01` and execute:
   ```bash
   gitlab-rails runner -e production 'puts Gitlab::Database::BackgroundMigration::BatchedMigration.queued.count'
   ```
   *The count must return `0` before proceeding.*

2. **Trigger a Full Backup**:
   Run the platform backup playbook:
   ```bash
   ansible-playbook -i inventories/production/hosts.yml playbooks/backup.yml --ask-vault-pass
   ```
   Confirm that both application data and configuration archives were created successfully in `/var/opt/gitlab/backups` and `/var/opt/gitlab/config-backups`.

3. **Check Disk Space**:
   Ensure at least 15 GB of free space is available on `/` and `/var/opt/gitlab` for database migrations and package unpacks.

---

## 4. Upgrading GitLab Server

Follow this procedure to upgrade the server:

### Step 1: Update Target Version in Variables
Edit `inventories/production/group_vars/gitlab_servers.yml`:
```yaml
# Update from 17.3.5 to 17.4.2
gitlab_server_version: "17.4.2"
```

### Step 2: Run GitLab Server Playbook
Execute the dedicated playbook:
```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/gitlab.yml --ask-vault-pass
```

The playbook will:
1. Temporarily unhold the existing package.
2. Install the target pinned version.
3. Automatically execute `gitlab-ctl reconfigure` to perform database migrations.
4. Re-apply the package hold.
5. Verify that all GitLab services are healthy.

### Step 3: Validate Post-Upgrade Health
Run the automated validation playbook:
```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/validate.yml --ask-vault-pass
```

---

## 5. GitLab Runner Fleet Upgrade & Compatibility

### Version Compatibility Matrix
According to official GitLab policy:
- A GitLab Runner version can be **the same as or older than** the GitLab Server version.
- A GitLab Runner version **must not be newer** than the GitLab Server version (e.g., do not run Runner 17.4 on GitLab Server 17.3).

```text
Runner Version <= GitLab Server Version  (Supported)
Runner Version >  GitLab Server Version  (UNSUPPORTED / May fail job artifacts/API)
```

### Runner Fleet Upgrade Procedure
1. Update `gitlab_runner_version` in `inventories/production/group_vars/gitlab_runners.yml`:
   ```yaml
   gitlab_runner_version: "17.4.0"
   ```
2. Execute the runner playbook:
   ```bash
   ansible-playbook -i inventories/production/hosts.yml playbooks/runners.yml --ask-vault-pass
   ```
   *Tip: To avoid interrupting active CI jobs, perform rolling updates using `--limit` or `serial` execution.*
