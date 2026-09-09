# Runner Fleet Scaling & Profiles

This document details how to scale, configure, and manage the GitLab Runner fleet dynamically using inventory definitions and specialized runner profiles.

---

## 1. Fleet Architecture Principles

In this toolkit, GitLab Runners are treated as an **elastic fleet of interchangeable worker nodes**, rather than individual, pet-like servers:

- **Zero-Code Scaling**: Adding 1, 5, or 50 new runner hosts requires **zero changes** to Ansible playbooks or role tasks. You only add the new hosts to your inventory.
- **Dedicated Isolation**: Every runner host is an independent Virtual Machine or Bare Metal server.
- **Job Isolation**: Jobs run inside short-lived, disposable Docker containers managed by the **Docker Executor**.
- **Host Security Baseline**: Docker runs with `privileged = false` by default across all profiles.

---

## 2. Dynamic Fleet Scaling Procedure

To scale out the runner fleet (e.g., adding `runner-04` and `runner-05`):

### Step 1: Provision the VM & Prepare Base OS
Ensure the new target machines (`runner-04`, `runner-05`) have been bootstrapped (e.g., via `ansible-server-bootstrap`) with network, SSH, sudo access, and Docker Engine.

### Step 2: Add Hosts to Inventory (`inventories/production/hosts.yml`)
Add the new hosts under the `gitlab_runners` group:

```yaml
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
        # New Runner Nodes:
        runner-04:
          ansible_host: 192.168.10.24
          gitlab_runner_profile: general
        runner-05:
          ansible_host: 192.168.10.25
          gitlab_runner_profile: high-memory
```

### Step 3: Add Authentication Tokens to Vault
Add the corresponding `glrt-...` tokens to `inventories/production/group_vars/all/vault.yml`:

```yaml
vault_gitlab_runner_auth_tokens:
  runner-01: "glrt-xxxxxxxxxxxxxxxxxxxx"
  runner-02: "glrt-yyyyyyyyyyyyyyyyyyyy"
  runner-03: "glrt-zzzzzzzzzzzzzzzzzzzz"
  runner-04: "glrt-aaaaaaaaaaaaaaaaaaaa"
  runner-05: "glrt-bbbbbbbbbbbbbbbbbbbb"
```

### Step 4: Run the Runners Playbook
Execute only the `runners.yml` playbook, targeting either the whole fleet or the new nodes:

```bash
# Provision only the new runner nodes
ansible-playbook -i inventories/production/hosts.yml playbooks/runners.yml --limit runner-04,runner-05 --ask-vault-pass

# Or verify the entire fleet idempotently
ansible-playbook -i inventories/production/hosts.yml playbooks/runners.yml --ask-vault-pass
```

---

## 3. Runner Profiles Specification

Runner profiles allow operators to standardize runner capabilities for different workload requirements:

| Profile | Target Workload | Tags | Concurrency | Privileged | Memory / CPU Limits | Protected |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `general` | Linting, unit tests, scripts | `docker`, `general`, `linux` | `4` | `false` | Default | `false` |
| `container-build` | Rootless container image builds (BuildKit/Kaniko) | `docker`, `build`, `image-build` | `2` | `false` | 4 GB / 2 CPU | `false` |
| `deploy` | Production / Staging infrastructure deployments | `deploy`, `production-deploy` | `1` | `false` | Default | `true` (Protected branches only) |
| `high-memory` | Large compilations, integration test suites | `heavy-build`, `high-memory` | `1` | `false` | 16 GB / 8 CPU | `false` |

### Customizing Profiles per Host (`host_vars/`)
Any runner host can override profile defaults by placing custom settings in `host_vars/<hostname>.yml`:

```yaml
# inventories/production/host_vars/runner-05.yml
gitlab_runner_profile: "high-memory"
gitlab_runner_tags:
  - "heavy-build"
  - "integration-tests"
  - "c-cpp-compile"

gitlab_runner_docker_memory: "16g"
gitlab_runner_docker_cpus: "4"
gitlab_runner_concurrency: 2
```

---

## 4. Modern Runner Registration Architecture

### The Problem with Deprecated Registration Tokens
In legacy GitLab architectures (< 16.0), runners registered using a shared instance registration token (`CI_RUNNER_REGISTRATION_TOKEN`). This workflow had severe drawbacks:
- Security risk: Anyone possessing the shared registration token could register rogue runners.
- Idempotency issues: Re-running playbooks risked creating duplicate runner instances in GitLab.
- Deprecation: GitLab has deprecated and is removing this workflow.

### Modern Authentication Token Workflow (`glrt-...`)
In GitLab 16.0+ and 17.x:
1. A runner registration record is created in GitLab (via Web UI or GitLab API).
2. GitLab assigns a unique **Runner Authentication Token** prefixed with `glrt-`.
3. The runner host registers once with:
   ```bash
   gitlab-runner register \
     --non-interactive \
     --url "https://gitlab.example.com" \
     --token "glrt-xxxxxxxxxxxxxxxxxxxx" \
     --executor "docker" \
     --docker-image "alpine:latest" ...
   ```
4. The token is saved in `/etc/gitlab-runner/config.toml`. Subsequent requests use this token for authentication.

### Idempotency Enforcement in Ansible
To ensure zero duplicate registrations when re-running `runners.yml`:
1. **State Discovery**: The role inspects `/etc/gitlab-runner/config.toml` to see if a runner with the configured token is already registered.
2. **Health Verification**: Runs `gitlab-runner verify` to test connection validity with GitLab.
3. **Execution Guard**: If the runner is already registered and verified, the registration command is skipped entirely (`changed=false`).

---

## 5. Decommissioning a Runner

To cleanly remove a runner host from the platform:

1. **Pause / Drain Jobs in GitLab UI**:
   Navigate to **Admin > CI/CD > Runners**, select the runner, and set it to **Paused**. Allow active jobs to complete.
2. **Unregister on Host**:
   ```bash
   gitlab-runner unregister --name "<runner-hostname>"
   ```
3. **Remove from Inventory**:
   Delete or comment out the host from `inventories/production/hosts.yml` and `vault.yml`.
