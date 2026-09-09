# Security & Hardening Architecture

This document details the security model, threat mitigations, and hardening policies implemented across the `gitlab-cicd-platform`.

---

## 1. Threat Model: CI/CD as Remote Code Execution (RCE)

In modern DevOps, a CI/CD Runner is functionally an **authorized Remote Code Execution service**. Untrusted or compromised code pushed by developers or third-party pull requests executes directly on runner infrastructure.

### The Hostile Job Assumption
Every pipeline job must be treated as potentially hostile:
- It may attempt to escape container boundaries to compromise the runner host.
- It may scan internal private networks to target databases or other hosts.
- It may attempt to read credentials, host SSH keys, or access the GitLab server filesystem.

To defend against these threats, the platform enforces strict structural security boundaries:

```text
┌────────────────────────────────────────────────────────┐
│                   Untrusted CI Job                     │
└───────────────────────────┬────────────────────────────┘
                            │ Trapped in disposable container
                            ▼
┌────────────────────────────────────────────────────────┐
│              Docker Executor Container                 │
│              - privileged = false                      │
│              - NO Docker socket mounted (/var/run/...) │
│              - Memory & CPU resource quotas            │
│              - Drop unneeded Linux capabilities        │
└───────────────────────────┬────────────────────────────┘
                            │ Controlled cgroups & namespaces
                            ▼
┌────────────────────────────────────────────────────────┐
│                   Runner Host VM                       │
│                   - Dedicated worker VM                │
│                   - Network segmented from prod DBs    │
│                   - No root SSH access allowed         │
└────────────────────────────────────────────────────────┘
```

---

## 2. Runner Security Baseline

### 1. Enforced Non-Privileged Mode (`privileged = false`)
- **Default Policy**: All standard runner profiles (`general`, `container-build`, `deploy`) strictly run with `privileged = false`.
- **Docker Socket Mount Prohibited**: The host Docker socket (`/var/run/docker.sock`) is **never** mounted into job containers by default. Mounting the Docker socket grants full root equivalent access to the host machine.
- **Rootless Image Building**: When pipelines need to build container images, they must use daemonless tools (Kaniko or BuildKit Rootless) instead of Docker-in-Docker.

### 2. Network Segmentation
- Runner VMs must be placed in a dedicated CI/CD subnet.
- Direct inbound access to Runner VMs from the public internet or corporate office LAN is blocked.
- Egress traffic from Runner VMs to sensitive internal production databases or control planes must be blocked by network firewalls.
- Runners only require outbound access to:
  - GitLab Server (`443` HTTPS)
  - Container Registry (`5050` / `443` HTTPS)
  - Outbound internet (for public package repositories like npm, pypi, apt).

### 3. Protected Runners for Deployment
Runners tagged for production deployment (e.g. `runner-03` with profile `deploy`):
- Have `protected = true` set in their registration parameters.
- **Enforcement**: GitLab prevents unprotected branches or forks from executing on protected runners. Only signed tags and protected `main`/`production` branches can run jobs on these machines.

---

## 3. Secrets Management Policy

### Strict Rules:
1. **Zero Plaintext Secrets in Git**: No real passwords, private keys, API tokens, or SMTP credentials may ever be committed to git repositories.
2. **Examples Contain Placeholders Only**: All template inventories use explicit placeholders like `CHANGE_ME` or `vault_...`.
3. **Ansible Vault Encryption**: All runtime secrets must be encrypted using Ansible Vault:
   ```bash
   ansible-vault encrypt inventories/production/group_vars/all/vault.yml
   ```

### Secret Inventory Reference
| Variable Name | Purpose | Storage Location |
| :--- | :--- | :--- |
| `vault_gitlab_root_password` | Initial GitLab web root user password | `vault.yml` |
| `vault_gitlab_runner_auth_tokens` | Dictionary of per-runner `glrt-...` tokens | `vault.yml` |
| `vault_gitlab_admin_api_token` | Admin token for API runner automation | `vault.yml` |
| `vault_gitlab_smtp_password` | SMTP server authentication password | `vault.yml` |
| `vault_external_registry_password` | Password for external container registry | `vault.yml` |
| `vault_gitlab_ssl_certificate_key` | Private key for custom TLS certificates | `vault.yml` |

---

## 4. TLS & Transport Security

Production deployments must use encrypted HTTPS with valid TLS certificates:

### Supported Modes:
1. **Let's Encrypt (`gitlab_server_tls_mode: letsencrypt`)**:
   - Automated certificate issuance and renewal via Omnibus Let's Encrypt integration.
   - Requires valid public DNS resolution and inbound port `80` reachability for ACME challenges.
2. **Custom / Corporate CA (`gitlab_server_tls_mode: custom`)**:
   - Provide your own certificate bundle and private key.
   - Files are validated for existence, format, and key match before applying configuration.
3. **Internal CA Trust on Runners**:
   - When using internal/private CAs, runner hosts automatically import the CA certificate into `/usr/local/share/ca-certificates/` (Debian/Ubuntu) or `/etc/pki/ca-trust/` (RHEL) and run update-ca-trust, ensuring seamless TLS verification for Git clones and Docker pulls.

### Fail-Closed Principle:
The playbook strictly pre-validates TLS certificate files:
- If a certificate path is specified but missing, the playbook **fails immediately**.
- It **never falls back silently to plaintext HTTP**.
