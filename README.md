# GitLab CI/CD Platform

Production-grade, reusable, secure, idempotent, and scalable Ansible platform for bootstrapping and operating self-managed GitLab and a dedicated GitLab Runner fleet on Virtual Machines / Bare Metal.

---

## 🌟 Key Features & Architectural Highlights

- **Dedicated Infrastructure**: Clean topology separation — dedicated GitLab Server (`gitlab-01`) and a horizontally scalable fleet of dedicated Runners (`runner-01` .. `runner-N`).
- **Official Omnibus Linux Package**: Pinned versioning (`gitlab_version: "x.y.z"`, `gitlab_edition: "ce"` or `"ee"`). Safe package holds and zero accidental upgrades.
- **Enterprise Runner Fleet**:
  - Native system package & systemd service on dedicated runner VMs.
  - **Docker Executor** by default for isolated, reproducible, disposable job environments.
  - **Fail-Safe Security**: `privileged = false` is strictly enforced by default. No indiscriminate Docker socket mounts.
  - **Modern Token Registration**: Automated, idempotent registration using GitLab 16+ Runner Authentication Tokens (`glrt-...`). No deprecated registration tokens.
  - **Runner Profiles**: Flexible profile modeling (`general`, `container-build`, `deploy`, `high-memory`).
  - **Zero-Code Scaling**: Adding 1 or 50 new runners only requires adding entries to the inventory.
- **Dual Container Registry Modes**:
  - **Mode 1 (`gitlab` — Default)**: Native GitLab Container Registry with HTTPS, TLS, and integrated authentication.
  - **Mode 2 (`external`)**: External target push/pull credentials (e.g., Harbor, Docker Hub) with a **unified CI abstraction** (`REGISTRY_URL`, `REGISTRY_IMAGE`, `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`).
- **Production TLS & Fail-Closed Validation**: Let's Encrypt, custom corporate CA, or user-provided certificates. Strict fail-closed verification — never falls back silently to plaintext HTTP.
- **Disaster Recovery Ready**: Automated application backup and configuration/secret archive (`gitlab-secrets.json`, `gitlab.rb`) with configurable cron schedules, retention policies, and step-by-step restore playbooks.
- **Comprehensive Observability & Health Checks**: Exposes Prometheus metrics, readiness/liveness endpoints, and automated validation playbooks.

---

## 🏗️ Architecture Overview

```text
                    ┌───────────────────────┐
                    │      Developers       │
                    └───────────┬───────────┘
                                │
                              HTTPS (443) / SSH (22)
                                │
                                ▼
                    ┌───────────────────────┐
                    │    GitLab Server      │
                    │                       │
                    │ GitLab Omnibus        │
                    │ GitLab Container Reg. │ (Port 5050 or HTTPS)
                    │ (gitlab-01)           │
                    └───────────┬───────────┘
                                │
             HTTPS (API/Jobs)   │ Runner Authentication (glrt-...)
                                │
             ┌──────────────────┼──────────────────┐
             │                  │                  │
             ▼                  ▼                  ▼
       ┌────────────┐     ┌────────────┐     ┌────────────┐
       │ Runner 01  │     │ Runner 02  │     │ Runner 03  │
       │ (General)  │     │ (Build)    │     │ (Deploy)   │
       │            │     │            │     │            │
       │ Docker     │     │ Docker     │     │ Docker     │
       │ Executor   │     │ Executor   │     │ Executor   │
       └────────────┘     └────────────┘     └────────────┘
```

> [!IMPORTANT]
> **Strict Boundaries**:
> - **NO Kubernetes / Helm**: This platform is designed specifically for Linux Virtual Machines and Bare Metal hosts.
> - **NO Dockerized GitLab Omnibus**: The GitLab server runs via the official Omnibus Linux package.
> - **NO Jenkins**: GitLab CI/CD is the primary and only CI/CD engine in this stack.
> - **Separation of Concerns**: This platform validates all OS prerequisites before mutation and manages the dedicated GitLab platform lifecycle.

---

## 📋 Prerequisites & Supported OS

### Supported Distributions
| Operating System | Version | GitLab Omnibus Support | GitLab Runner Support |
| :--- | :--- | :--- | :--- |
| **Ubuntu** | 22.04 LTS (Jammy) | Official | Official |
| **Ubuntu** | 24.04 LTS (Noble) | Official | Official |
| **Debian** | 12 (Bookworm) | Official | Official |
| **Rocky Linux / AlmaLinux** | 9 | Official | Official |
| **RHEL** | 9 | Official | Official |

### Host Prerequisites
1. **GitLab Server (`gitlab-01`)**:
   - Minimum: 4 vCPU, 8 GB RAM (16 GB recommended for 100+ users).
   - Storage: Minimum 50 GB SSD (adjust for repositories, artifacts, and registry storage).
   - Fully Qualified Domain Name (FQDN) resolvable via DNS (e.g., `gitlab.example.com`).
2. **Runner Hosts (`runner-01` .. `runner-N`)**:
   - Minimum: 2 vCPU, 4 GB RAM (scalable according to job profiles).
   - Docker Engine installed and running (can be validated or provisioned).
   - Outbound HTTPS network connectivity to the GitLab Server and package repositories.
3. **Ansible Control Node**:
   - `ansible-core >= 2.15` (tested with 2.20+)
   - Python 3.10+
   - Collections: `ansible.posix`, `community.general`, `community.docker`

---

## 🚀 Quick Start Guide

### 1. Clone & Setup Project Inventory
Create a copy of the example inventory for your target environment:

```bash
cp -r inventories/example inventories/production
```

### 2. Configure Inventory & Variables

Edit `inventories/production/hosts.yml`:
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

Edit `inventories/production/group_vars/gitlab_servers.yml`:
```yaml
gitlab_server_external_url: "https://gitlab.example.com"
gitlab_server_version: "19.3.1"
gitlab_server_edition: "ce"

gitlab_registry_enable: true
gitlab_registry_external_url: "https://gitlab.example.com:5050"
```

### 3. Setup Secrets with Ansible Vault
Create an encrypted vault file for sensitive credentials:

```bash
ansible-vault create inventories/production/group_vars/all/vault.yml
```

Define required secrets in the vault:
```yaml
vault_gitlab_root_password: "YourSecureRootPassword"
vault_gitlab_runner_auth_tokens:
  runner-01: "glrt-xxxxxxxxxxxxxxxxxxxx"
  runner-02: "glrt-yyyyyyyyyyyyyyyyyyyy"
  runner-03: "glrt-zzzzzzzzzzzzzzzzzzzz"
```

### 4. Run Provisioning

Execute the full site playbook:
```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml --ask-vault-pass
```

Or run targeted playbooks:
```bash
# Provision GitLab Server only
ansible-playbook -i inventories/production/hosts.yml playbooks/gitlab.yml --ask-vault-pass

# Scale / update Runner fleet only
ansible-playbook -i inventories/production/hosts.yml playbooks/runners.yml --ask-vault-pass

# Run functional validation suite
ansible-playbook -i inventories/production/hosts.yml playbooks/validate.yml --ask-vault-pass

# Trigger backup
ansible-playbook -i inventories/production/hosts.yml playbooks/backup.yml --ask-vault-pass
```

---

## 📁 Repository Structure

```text
gitlab-cicd-platform/
├── ansible.cfg                  # Optimized Ansible configurations
├── requirements.yml             # Required Ansible collections
├── .ansible-lint                # Linter configuration
├── .gitignore                   # Ignore sensitive files and temp directories
│
├── inventories/
│   └── example/                 # Reusable template inventory
│       ├── hosts.yml
│       ├── group_vars/
│       │   ├── all.yml
│       │   ├── gitlab_servers.yml
│       │   └── gitlab_runners.yml
│       └── host_vars/
│           ├── gitlab-01.yml
│           ├── runner-01.yml
│           ├── runner-02.yml
│           └── runner-03.yml
│
├── playbooks/
│   ├── site.yml                 # Master orchestration
│   ├── gitlab.yml               # Server & registry provisioning
│   ├── runners.yml              # Runner fleet setup & registration
│   ├── validate.yml             # Health check & functional tests
│   ├── backup.yml               # Backup trigger and verification
│   └── restore.yml              # Disaster recovery runbook
│
├── roles/
│   ├── gitlab_common/           # OS validation & fail-closed pre-checks
│   ├── gitlab_server/           # Omnibus package, gitlab.rb, TLS, reconfigure
│   ├── gitlab_registry/         # Container registry configuration
│   ├── gitlab_runner/           # Runner package & systemd service
│   ├── runner_docker_executor/  # Docker executor settings, non-privileged guards
│   ├── runner_registration/     # glrt-... token registration & idempotency
│   ├── gitlab_backup/           # Backup scripts, crons, and retention
│   └── gitlab_validation/      # Service health, API, runner, and registry validation
│
├── docs/                        # Deep architectural and operational runbooks
│   ├── architecture.md
│   ├── installation.md
│   ├── runner-scaling.md
│   ├── registry.md
│   ├── security.md
│   ├── backup-restore.md
│   └── upgrade.md
│
├── examples/
│   └── ci-pipelines/            # Reference pipelines demonstrating registry abstraction
│
└── tests/                       # Automated lint and syntax validation scripts
    ├── lint.sh
    └── syntax-check.sh
```

---

## 🔒 Security Model & Best Practices

1. **Non-Privileged CI by Default**: All runners run with `privileged = false`. BuildKit and rootless image builders are used for container builds.
2. **Network Segmentation**: CI jobs cannot access host SSH keys, GitLab server internal filesystems, or internal cluster secrets.
3. **Protected Runners**: Runners designated for production deployment (`runner-deploy`) are flagged as `protected = true` and only execute on protected branches/tags.
4. **Secrets Hygiene**: No plaintext secrets exist in code or Git commits. All tokens and passwords reside in Ansible Vault.
5. **Fail-Closed Strategy**: Any inconsistency (unsupported OS, missing TLS certificates, invalid token) immediately halts execution with an explicit error.

---

## 📚 Documentation Links

- 🏛️ [Architecture & Network Flows](docs/architecture.md)
- 🛠️ [Installation & Operations Guide](docs/installation.md)
- 🧪 [Local Lab Testing Guide (Vagrant)](docs/lab-setup.md)
- ⚡ [Runner Fleet Scaling & Profiles](docs/runner-scaling.md)
- 📦 [Container Registry: Built-in vs External](docs/registry.md)
- 🛡️ [Security & Hardening Model](docs/security.md)
- 💾 [Backup, Disaster Recovery & Restore Runbook](docs/backup-restore.md)
- 🔄 [Upgrade & Maintenance Policy](docs/upgrade.md)

---

## 📄 License

MIT License — Copyright (c) 2026 Mahdi
