# Architecture & System Design

This document details the architectural principles, component boundaries, network flows, and design decisions for the GitLab CI/CD Platform.

---

## 1. Platform Scope & Architecture

The GitLab CI/CD Platform provides complete, production-grade automation for self-managed GitLab infrastructure:

```text
                             GitLab CI/CD Platform
                                       │
          ┌────────────────────────────┴────────────────────────────┐
          │                                                         │
GitLab Omnibus Server                                    GitLab Runner Fleet
- Dedicated Linux VM / Bare Metal                        - Dedicated Runner VMs / Bare Metal
- Official GitLab Omnibus Package                        - Native systemd service
- NGINX, Puma, PostgreSQL, Gitaly                        - Docker Executor (isolated jobs)
- Integrated Container Registry                          - Flexible runner profile modeling
- Automated Backup & Disaster Recovery                   - Modern token authentication (glrt-...)
- Prometheus monitoring endpoints                        - Horizontal fleet scalability
```

### Platform Responsibility & Scope
- **GitLab Server Lifecycle**: Manages the complete lifecycle of GitLab Omnibus (installation, version pinning, configuration through `/etc/gitlab/gitlab.rb`, reconfiguration, upgrades, and automated backup schedules).
- **Runner Fleet Orchestration**: Manages the deployment, token-based registration, optional Docker Engine installation, and profile concurrency for the dedicated runner fleet.
- **Infrastructure Validation**: Performs strict pre-flight checks (OS compatibility, CPU architecture, prerequisites, network access, and firewall rules) before mutating target systems.

---

## 2. Target Deployment Topology

The physical/virtual topology separates the GitLab Server from its CI/CD Runner workers:

```text
                                  ┌───────────────────────────┐
                                  │      Client Browsers      │
                                  │       & Git Clients       │
                                  └─────────────┬─────────────┘
                                                │
                                    HTTPS:443 / SSH:22
                                                │
                                                ▼
                                  ┌───────────────────────────┐
                                  │       GitLab Server       │
                                  │         (gitlab-01)       │
                                  │                           │
                                  │  - GitLab Rails / Workhorse
                                  │  - PostgreSQL (Embedded)  │
                                  │  - Redis (Embedded)       │
                                  │  - Gitaly (Git Storage)   │
                                  │  - GitLab Registry (:5050)│
                                  │  - Prometheus Exporters   │
                                  └─────────────┬─────────────┘
                                                │
                          Outbound HTTPS:443    │ Runner Polling & Artifact Push
                                                │
             ┌──────────────────────────────────┼──────────────────────────────────┐
             │                                  │                                  │
             ▼                                  ▼                                  ▼
┌─────────────────────────┐        ┌─────────────────────────┐        ┌─────────────────────────┐
│     Runner Host 01      │        │     Runner Host 02      │        │     Runner Host 03      │
│       (runner-01)       │        │       (runner-02)       │        │       (runner-03)       │
│                         │        │                         │        │                         │
│ - GitLab Runner (systemd│        │ - GitLab Runner (systemd│        │ - GitLab Runner (systemd│
│ - Docker Engine         │        │ - Docker Engine         │        │ - Docker Engine         │
│ - Profile: general      │        │ - Profile: build        │        │ - Profile: deploy       │
│ - Docker Executor       │        │ - Docker Executor       │        │ - Docker Executor       │
│   (privileged = false)  │        │   (privileged = false)  │        │   (privileged = false)  │
└─────────────────────────┘        └─────────────────────────┘        └─────────────────────────┘
```

---

## 3. Strict Architectural Decisions

| Constraint | Decision | Rationale |
| :--- | :--- | :--- |
| **Hosting Environment** | Virtual Machines / Bare Metal | Ensures predictable I/O performance, hardware stability, and simple maintenance without Kubernetes overhead. |
| **GitLab Deployment** | Official Omnibus Linux Package | Recommended, battle-tested standard for self-managed GitLab. Avoids unsupported or complex container-in-container layers. |
| **Dockerized GitLab** | **Strictly Prohibited** | Dockerized GitLab Omnibus adds unnecessary abstraction, storage complexity, and operational fragility on bare VM setups. |
| **Kubernetes / Helm** | **Strictly Prohibited** | Out of scope for this VM/Bare Metal platform. |
| **Jenkins** | **Strictly Prohibited** | GitLab CI/CD is the sole pipeline execution engine. |
| **Runner Colocation** | **Strictly Prohibited** | Runners must never share a host with the GitLab server to prevent CI job memory exhaustion or security compromise of the server. |
| **Runner Package** | Native System Package + systemd | Native system service ensures robust lifecycle management, proper log handling, and zero nested container issues. |
| **Runner Executor** | Docker Executor | Guarantees isolated, reproducible, and disposable environments for every CI job. |
| **Docker Privileged Mode** | **Disabled by default (`false`)** | Prevents hostile or untrusted CI jobs from breaking out of containers and compromising the host system. |

---

## 4. Network Flows & Firewall Matrix

### GitLab Server Inbound Traffic
| Port | Protocol | Source | Purpose |
| :--- | :--- | :--- | :--- |
| `80` | TCP | Any / Reverse Proxy | HTTP (automatically redirected to HTTPS:443 via Omnibus NGINX). |
| `443` | TCP | Developers, Runners, External | Secure HTTPS access to Web UI, Git over HTTPS, API, and Webhooks. |
| `22` (or custom) | TCP | Developers, Admin | Git over SSH and server management. |
| `5050` | TCP | Runners, Developers | GitLab Container Registry HTTPS endpoint (if configured on dedicated port). |
| `9090` | TCP | Monitoring Server | Internal Prometheus metrics (restricted to monitoring subnet). |

### Runner Hosts Traffic
| Direction | Port | Protocol | Destination | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Outbound** | `443` | TCP | GitLab Server (`gitlab-01`) | Long polling for CI jobs, fetching Git repos, uploading build artifacts. |
| **Outbound** | `5050` / `443` | TCP | Container Registry (GitLab/External) | Pulling job base images and pushing built application container images. |
| **Outbound** | `80` / `443` | TCP | Internet / Package Mirrors | Downloading dependencies (npm, PyPI, Maven, apt, etc.) required during CI jobs. |
| **Inbound** | `9252` | TCP | Monitoring Server | GitLab Runner Prometheus metrics (optional, restricted to monitoring subnet). |
| **Inbound** | None | - | General Network | Runners require **zero inbound ports** from the public network or GitLab server. |

---

## 5. Architectural Principles

### 1. Configuration Drives Behavior, Code Remains Constant
A core tenet of this platform is:
> *Configuration changes behavior. Code does not change per customer or project.*

All client-specific and environment-specific settings (domains, certificates, resource quotas, runner counts, tags, tokens) are defined strictly through inventory files (`group_vars`, `host_vars`, and Ansible Vault). Ansible roles and playbooks remain 100% immutable across deployments.

### 2. Idempotency & Meaningful Changes
Running `site.yml` or `runners.yml` multiple times on an already converged infrastructure results in:
- `changed=0` on steady state.
- No redundant service restarts.
- No re-generation of TLS certificates if current certificates remain valid.
- No duplicate runner registrations in GitLab.

### 3. Fail-Closed Design
If an invalid state, unsupported operating system, missing mandatory secret, unreachable dependency, or unreadable TLS certificate is encountered:
- The playbook immediately halts with an unambiguous, descriptive error.
- The system never guesses or silently falls back to an insecure state (e.g., falling back to plaintext HTTP when HTTPS fails).

### 4. Discovery Before Mutation
Before applying any package updates or configuration modifications, pre-flight tasks discover the current state:
- Check existing GitLab installation and installed version.
- Check active services via systemd.
- Check current Runner registrations in `/etc/gitlab-runner/config.toml`.
- Validate Docker daemon responsiveness on runner nodes.
