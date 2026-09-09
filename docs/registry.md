# Container Registry Architecture & CI Abstraction

This document explains the dual-mode Container Registry architecture, configuration options, secure container image building patterns, and the unified CI/CD abstraction layer.

---

## 1. Architectural Modes

This platform supports two distinct modes for container image management, controlled via the `registry_mode` variable:

```yaml
# Supported values: 'gitlab' (default) or 'external'
registry_mode: "gitlab"
```

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                           registry_mode: "gitlab"                       │
│                                (Default)                                │
│                                                                         │
│  GitLab Server (Omnibus)                                                │
│  ├── Built-in Container Registry (Port 5050 or HTTPS)                   │
│  ├── Native token authentication via GitLab Rails                       │
│  └── Automatically provides CI_REGISTRY, CI_REGISTRY_USER, etc.         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                          registry_mode: "external"                      │
│                                                                         │
│  GitLab Server (Omnibus)              External Registry (e.g. Harbor)   │
│  └── Internal registry disabled       ├── Independent enterprise storage│
│                                       └── Dedicated credentials         │
│  CI/CD Jobs authenticate directly using unified pipeline variables      │
└─────────────────────────────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> **Strict Architectural Rule Regarding External Registries**:
> GitLab has formally deprecated and does not support third-party container registries as backend replacements for its integrated web UI registry view.
> Therefore, in this platform:
> - **External Registry** means a **target CI/CD image push/pull endpoint**.
> - It does **NOT** attempt unsupported Omnibus backend hacks or reverse proxy integrations.
> - Pipelines receive the target endpoint credentials via CI/CD variables and push/pull directly to the external registry.

---

## 2. Mode 1: Built-in GitLab Container Registry (Default)

### Configuration
In `inventories/<env>/group_vars/gitlab_servers.yml`:
```yaml
gitlab_registry_enable: true

# Option A: Same domain with dedicated port (Default)
gitlab_registry_external_url: "https://gitlab.example.com:5050"

# Option B: Dedicated subdomain (Requires DNS record and wildcard/separate TLS cert)
# gitlab_registry_external_url: "https://registry.example.com"

gitlab_registry_storage_path: "/var/opt/gitlab/gitlab-rails/shared/registry"
```

### Authentication Mechanics
- When a pipeline runs, GitLab automatically injects short-lived job credentials:
  - `CI_REGISTRY`: The registry host and port (e.g., `gitlab.example.com:5050`).
  - `CI_REGISTRY_IMAGE`: The project image path (e.g., `gitlab.example.com:5050/group/project`).
  - `CI_REGISTRY_USER`: `gitlab-ci-token`
  - `CI_REGISTRY_PASSWORD`: Temporary JWT job token (`$CI_JOB_TOKEN`).

---

## 3. Mode 2: External Container Registry

### Configuration
In `inventories/<env>/group_vars/gitlab_servers.yml`:
```yaml
registry_mode: "external"
gitlab_registry_enable: false # Disables built-in Omnibus registry to save RAM/CPU
```

In `inventories/<env>/group_vars/all.yml` (and `vault.yml` for passwords):
```yaml
external_registry:
  url: "harbor.corp.internal"
  username: "cicd-robot"
  # Password stored in vault.yml: vault_external_registry_password
```

Pipelines then use CI/CD variables configured at the instance or group level to push/pull from the external registry.

---

## 4. Unified CI/CD Registry Abstraction

To ensure application CI pipelines do not need to be rewritten when moving between environments or switching registry modes, the platform defines a **unified abstraction interface**:

### Standard Interface Specification
| Normalized Variable | Source when `registry_mode: gitlab` | Source when `registry_mode: external` |
| :--- | :--- | :--- |
| `REGISTRY_URL` | `$CI_REGISTRY` | `$EXTERNAL_REGISTRY_URL` |
| `REGISTRY_IMAGE` | `$CI_REGISTRY_IMAGE` | `$EXTERNAL_REGISTRY_URL/$PROJECT_PATH` |
| `REGISTRY_USER` | `$CI_REGISTRY_USER` | `$EXTERNAL_REGISTRY_USERNAME` |
| `REGISTRY_PASSWORD`| `$CI_REGISTRY_PASSWORD` | `$EXTERNAL_REGISTRY_PASSWORD` |

### Reference CI Implementation (`.gitlab-ci-reference.yml`)
```yaml
# Reusable registry login snippet
.registry_auth: &registry_auth
  before_script:
    - export REGISTRY_URL="${REGISTRY_URL:-$CI_REGISTRY}"
    - export REGISTRY_IMAGE="${REGISTRY_IMAGE:-$CI_REGISTRY_IMAGE}"
    - export REGISTRY_USER="${REGISTRY_USER:-$CI_REGISTRY_USER}"
    - export REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-$CI_REGISTRY_PASSWORD}"
    - echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USER" --password-stdin
```

---

## 5. Secure Container Image Building (Rootless / Non-Privileged)

A major security vulnerability in traditional CI setups is running Docker-in-Docker (DinD) with `privileged = true`. This platform strictly defaults to `privileged = false`.

To build container images inside non-privileged Docker Executor runners, two secure, daemonless methods are recommended:

### Method A: Kaniko (Recommended for Standard Builds)
Kaniko builds container images from a Dockerfile inside a container/VM without relying on a Docker daemon:

```yaml
build-image-kaniko:
  stage: build
  tags:
    - container-build
  image:
    name: gcr.io/kaniko-project/executor:v1.23.2-debug
    entrypoint: [""]
  script:
    - mkdir -p /kaniko/.docker
    - echo "{\"auths\":{\"$REGISTRY_URL\":{\"username\":\"$REGISTRY_USER\",\"password\":\"$REGISTRY_PASSWORD\"}}}" > /kaniko/.docker/config.json
    - /kaniko/executor
        --context "${CI_PROJECT_DIR}"
        --dockerfile "${CI_PROJECT_DIR}/Dockerfile"
        --destination "${REGISTRY_IMAGE}:${CI_COMMIT_SHORT_SHA}"
```

### Method B: BuildKit Rootless
BuildKit can run in rootless mode inside a non-privileged container with `seccomp` unconfined:

```yaml
build-image-buildkit:
  stage: build
  tags:
    - container-build
  image: moby/buildkit:v0.16.0-rootless
  variables:
    BUILDKITD_FLAGS: --oci-worker-no-process-sandbox
  script:
    - mkdir -p ~/.docker
    - echo "{\"auths\":{\"$REGISTRY_URL\":{\"username\":\"$REGISTRY_USER\",\"password\":\"$REGISTRY_PASSWORD\"}}}" > ~/.docker/config.json
    - buildctl-daemonless.sh build
        --frontend dockerfile.v0
        --local context=.
        --local dockerfile=.
        --output type=image,name="${REGISTRY_IMAGE}:${CI_COMMIT_SHORT_SHA}",push=true
```
