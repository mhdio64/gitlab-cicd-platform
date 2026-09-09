# Local Lab Testing Guide (Vagrant)

This guide walks you through running a complete, isolated GitLab CI/CD environment on your local Linux machine using Vagrant and Libvirt (KVM) or VirtualBox.

---

## 1. Prerequisites

Ensure you have the following installed on your host:
- [Vagrant](https://www.vagrantup.com/) (`>= 2.2`)
- Either **KVM/Libvirt** (recommended on Linux) or **VirtualBox**
- Minimum system resources:
  - 8 GB free RAM (GitLab VM: 4 GB, Runner VM: 2 GB, Host: 2 GB)
  - 4 CPU cores
  - 30 GB free disk space

---

## 2. Lab Topology

```text
Host Machine (Your Linux PC)
├── Libvirt / VirtualBox Private Network (192.168.56.0/24)
│
├── gitlab-01 (192.168.56.10 / gitlab.192.168.56.10.nip.io)
│   ├── OS: Ubuntu 22.04 LTS
│   ├── Memory: 4096 MB, CPU: 2
│   └── Omnibus GitLab CE (v19.3.1)
│
└── runner-01 (192.168.56.21)
    ├── OS: Ubuntu 22.04 LTS
    ├── Memory: 2048 MB, CPU: 2
    ├── Docker CE (installed automatically)
    └── GitLab Runner (v19.3.1) with Docker Executor
```

> [!NOTE]
> **Why `nip.io`?**
> In local lab environments without custom DNS servers, `*.nip.io` resolves any IP embedded in the hostname automatically.
> `gitlab.192.168.56.10.nip.io` resolves to `192.168.56.10` out of the box from both your browser and the runner VM.

---

## 3. Step-by-Step Lab Execution

### Step 1: Boot the Virtual Machines
Run one of the following commands in the project root:

```bash
# Using Libvirt / KVM (Fastest on Linux):
vagrant up --provider=libvirt

# Or using VirtualBox:
vagrant up --provider=virtualbox
```

Verify both machines are running:
```bash
vagrant status
```

### Step 2: Configure Lab Vault Secrets
Copy the lab vault template:
```bash
cp inventories/lab/group_vars/all/vault.example.yml inventories/lab/group_vars/all/vault.yml
```

Set your desired root password inside `vault.yml` and encrypt it:
```bash
ansible-vault encrypt inventories/lab/group_vars/all/vault.yml
```

### Step 3: Provision GitLab Server (`gitlab-01`)
Deploy Omnibus GitLab onto the server VM:
```bash
ansible-playbook -i inventories/lab/hosts.yml playbooks/gitlab.yml --ask-vault-pass
```

Once completed, open your browser and navigate to:
👉 **`http://gitlab.192.168.56.10.nip.io`**

Log in with:
- **Username**: `root`
- **Password**: Value configured in your `vault.yml`

### Step 4: Obtain Runner Authentication Token
1. In GitLab UI, go to **Admin Area > CI/CD > Runners** (`http://gitlab.192.168.56.10.nip.io/admin/runners`).
2. Click **New instance runner**.
3. Set tags: `general, docker, linux`.
4. Check **Run untagged jobs** (optional).
5. Click **Create runner**.
6. Copy the displayed Runner Authentication Token (starts with `glrt-`).

Update your `vault.yml` with the token:
```bash
ansible-vault edit inventories/lab/group_vars/all/vault.yml
```
```yaml
vault_gitlab_runner_auth_tokens:
  runner-01: "glrt-YOUR_COPIED_TOKEN_HERE"
```

### Step 5: Provision & Register the Runner Fleet
Run the runners playbook to install Docker, GitLab Runner, and register the node:
```bash
ansible-playbook -i inventories/lab/hosts.yml playbooks/runners.yml --ask-vault-pass
```

### Step 6: Validate Entire Platform
Run the functional validation suite:
```bash
ansible-playbook -i inventories/lab/hosts.yml playbooks/validate.yml --ask-vault-pass
```

---

## 4. Teardown & Cleanup

When you are finished testing, cleanly power down and destroy the VMs:

```bash
# Power off VMs:
vagrant halt

# Destroy VMs and free disk space:
vagrant destroy -f
```
