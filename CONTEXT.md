# CONTEXT.md — bootstrap

**Repo purpose:** Bootstrap scripts and Ansible automation for managing The Scaffold Rack platform.

**Last updated:** 2026-05-09

---

## 1. What this repo is

This repo holds two things:

1. **One shell script** (`scripts/bootstrap-control-node.sh`) that seeds a fresh Debian box into being an Ansible control node. Narrowly scoped: installs Docker, builds/pulls the `devops-toolkit:latest` container image. Nothing else.

2. **All Ansible content** — inventory, roles, playbooks — that manages every host in the platform from that point forward. This includes configuring the control node itself (zsh, toolkit aliases, completions) via the `control_node` role.

The shell script is the only thing that exists outside Ansible because there's no way to use Ansible to set up the thing that runs Ansible. Once the script finishes and the container image is available, Ansible takes over for everything else — including configuring its own runtime environment on the control node.

## 2. Hosts in scope

| Host | Address | OS | Role |
|---|---|---|---|
| commander | 172.31.200.x | Debian 12 (Bookworm) on Pi 5 | Ansible control node, Gitea host, kb host |
| ai | 172.31.200.20 | Debian | Dedicated AI host (dual GTX 1070 Ti, Ollama, Open WebUI) |
| pve1 | 172.31.200.11 | Debian 13 (Trixie) → Proxmox | Hypervisor |
| pve2 | 172.31.200.12 | Debian 13 (Trixie) → Proxmox | Hypervisor |

commander is both control node *and* a managed host. It's managed via `ansible_connection: local` to sidestep the 2FA-on-external-SSH consideration entirely.

## 3. Architectural decisions (summary)

Full reasoning in `decisions/`. Brief summary here:

- **Automation user is `bob`, UID 990, ed25519 key, NOPASSWD: ALL sudo.** ADR-001. The NOPASSWD: ALL trade-off is documented as "wrong choice for FedRAMP, revisit when compliance work starts." UID 990 is high enough that no Debian package install will collide with it.

- **One shell script lives outside Ansible.** ADR-002. `bootstrap-control-node.sh` is narrowly scoped to Docker + container image. Everything else (including control node configuration) is a playbook.

- **Unified repo, not split.** ADR-003. We considered separating bootstrap-the-shell-script from a dedicated ansible repo, and rejected it. One workflow, one repo, one place to look.

- **Hardening is one role with internal task splits and tags.** ADR-004. UFW for firewall. Tags on each task file mean `--tags ssh` works for targeted re-runs.

- **Gitea push-primary, GitHub push-mirror** (cross-cutting decision). Push to Gitea on commander; Gitea push-mirrors to GitHub publicly.

- **2FA applies to human SSH on commander only.** bob is for outbound automation from commander to managed hosts. commander manages itself via `ansible_connection: local`. No conflict between 2FA and Ansible.

## 4. The two-identity model — andrew and bob

Every managed host has two identities at different stages of its lifecycle:

- **andrew** — the human-provisioned foothold. Created during OS install with sudo (password required, not NOPASSWD). Used exactly once per host: to run `bootstrap.yml` and create bob. Never used for automation thereafter. Andrew passwords differ per host (security hygiene); this only matters at bootstrap time.

- **bob** — the automation identity. Created by `bootstrap.yml` running as andrew. UID 990, ed25519 key auth, NOPASSWD sudo. Every Ansible playbook from `site.yml` onward runs as bob. Andrew is dormant after bootstrap.

This model means there is one irreducibly manual prerequisite per host: andrew must exist with sudo before Ansible can do anything. That's the foothold. Everything past that is automated.

## 5. Repo conventions

These match the broader Scaffold Rack project conventions. Code-Claude follows them without exception:

- **Markdown only** for documentation. Never `.docx`, `.pdf`, or other formats.
- **INSTRUCTIONS.md** (not README.md) for AI-generated rollout/placement docs. README.md is for human readers.
- **No heredocs in scripts.** Use configuration files.
- **Idempotent.** Every script and playbook safe to re-run. Re-running detects existing state and skips with a warning rather than failing or doing destructive work.
- **`tmp/` directory** with `.gitkeep` (`tmp/*` + `!tmp/.gitkeep` in `.gitignore`). Never commit work products from `tmp/` directly — move them to their proper location first.
- **`.example` suffix** for templated files; real values gitignored.
- **Color-coded logging helpers** (`log`/`warn`/`die`) in shell scripts.
- **Secrets never committed.** ed25519 *public* key is fine to commit; private key never.
- **Tokens come from `~/.blackwell`** on the control node, sourced at script runtime.
- **ADRs in `decisions/`** with sections for: Status, Date, Context, Decision, Consequences, Alternatives Considered, Trade-offs Accepted, When This Is the Wrong Choice.
- **3am rule.** Favor simplicity, compartmentalization, explicit-over-clever. Complexity must justify itself against "could I debug this at 3am, exhausted?"
- **CONTEXT.md is authoritative.** Memory is a backup, not a source of truth.
- **Always read files before editing.** Never reconstruct file contents from memory or assumption.

## 6. Directory structure

```
bootstrap/
├── README.md                 # human-facing entry point
├── CONTEXT.md                # this file — Code-Claude reads on every session
├── INSTRUCTIONS.md           # what Code-Claude should do/avoid
├── ansible.cfg               # Ansible configuration
├── .gitignore
├── decisions/                # repo-specific ADRs
│   ├── 001-automation-user-bob.md
│   ├── 002-control-node-shell-script.md
│   ├── 003-unified-bootstrap-and-ansible-repo.md
│   └── 004-hardening-single-role-with-tags.md
├── scripts/
│   └── bootstrap-control-node.sh    # the only shell script
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       ├── all.yml
│       ├── proxmox.yml
│       └── debian.yml
├── files/
│   └── bob.pub               # bob's ed25519 public key (committed)
├── roles/
│   ├── control_node/         # zsh, oh-my-zsh, toolkit aliases, completions
│   ├── bootstrap_bob/        # idempotent: creates bob, key, sudoers
│   ├── baseline/             # hostname, NTP, packages, sources
│   ├── hardening/            # SSH, UFW, fail2ban, sysctl, audit, PAM, banner
│   └── proxmox/              # Debian-to-Proxmox conversion (later)
├── playbooks/
│   ├── ping.yml              # smoke test
│   ├── control-node.yml      # configures control node (zsh, aliases, etc.)
│   ├── bootstrap.yml         # onboard a managed host (run once per host as andrew)
│   ├── site.yml              # everything, idempotent, daily driver (runs as bob)
│   ├── baseline.yml          # baseline only
│   ├── harden.yml            # hardening only
│   └── proxmox.yml           # Proxmox conversion (later)
└── tmp/
    └── .gitkeep
```

## 7. Workflow

### First-time control node setup

This is a five-step sequence on a fresh Debian box. Three manual steps, two automated.

**Manual prerequisites:**

The box must already have:

- Debian 12+ installed
- User with sudo privileges (the foothold for everything)
- Internet access (to install packages and pull images)

**Step 1 — Install git** (manual, one-time):

```bash
sudo apt update
sudo apt install -y git
```

**Step 2 — Clone the bootstrap repo** (manual, one-time):

Ansible can't clone the repo containing Ansible. This step is irreducible.

```bash
git clone https://gitea.mercnet.info/scaffoldrack/bootstrap.git
cd bootstrap
```

**Step 3 — Run bootstrap-control-node.sh** (automated, idempotent):

```bash
./scripts/bootstrap-control-node.sh
```

This installs Docker and builds/pulls the `devops-toolkit:latest` image. Re-running is safe: detects existing Docker installation and existing image, skips with warnings. Script is idempotent.

**Step 4 — Run the control-node playbook in the container** (one-time, awkward but unavoidable):

This is the bootstrap-the-bootstrap step. Ansible isn't installed on the host directly — it lives in the container — and the toolkit aliases haven't been configured yet. So this first invocation uses the raw `docker run` command:

```bash
docker run --rm -it \
  -v $(pwd):/workspace \
  -v ~/.ssh:/root/.ssh:ro \
  -w /workspace \
  --network host \
  devops-toolkit:latest \
  ansible-playbook playbooks/control-node.yml --ask-become-pass
```

The playbook installs zsh, sets it as default shell, drops the toolkit aliases file, configures `.zshrc` to source it, installs oh-my-zsh, generates completions for kubectl and helm.

**Step 5 — Open a new zsh shell:**

```bash
exec zsh
```

From this point forward, the toolkit aliases are active. `ansible-playbook playbooks/site.yml` works because `ansible-playbook` is now an alias that invokes the container with the right mounts.

### Prerequisites for a new managed host

Before `bootstrap.yml` can run against a host, the host needs:

- OS installed (Debian 12+)
- User `andrew` created during OS install, with sudo privileges (password-required is fine)
- SSH key from commander authorized for `andrew@host` (so passwordless SSH login works)
- Static IP configured per the network plan
- Hostname set per inventory naming
- DNS resolution working
- andrew's password recorded in a password manager (different per host)

These are irreducibly manual. Document them in INSTRUCTIONS.md before adding a new host to inventory.

### First-time managed host onboarding

Run once per new target host. Andrew passwords differ per host, so each host runs separately:

```bash
ansible-playbook playbooks/bootstrap.yml --limit ai --ask-become-pass
ansible-playbook playbooks/bootstrap.yml --limit pve1 --ask-become-pass
ansible-playbook playbooks/bootstrap.yml --limit pve2 --ask-become-pass
```

Each invocation prompts for andrew's password on that specific host. The playbook:

1. Creates bob (UID 990)
2. Installs the public key
3. Configures sudoers for NOPASSWD
4. Verifies bob can SSH and sudo
5. Disables SSH password authentication

The verification step (bob can SSH and sudo) MUST succeed before SSH password auth is disabled. If verification fails, the playbook aborts before lockout.

After successful bootstrap, that host is managed by Ansible as bob via key auth. Andrew is dormant; her password is no longer needed for routine operations.

### Daily operations

```bash
ansible-playbook playbooks/site.yml                # everything
ansible-playbook playbooks/site.yml --limit pve1   # one host
ansible-playbook playbooks/harden.yml --tags ssh   # targeted task run
```

Always runs as bob with key auth. Idempotent — re-running enforces desired state.

### Adding a new host

1. Provision OS per prerequisites above
2. Add to `inventory/hosts.yml` in the appropriate group
3. Run `playbooks/bootstrap.yml --limit <host> --ask-become-pass` (one-time)
4. Run `playbooks/site.yml --limit <host>` to bring it to baseline
5. Run `playbooks/site.yml` going forward (recurring)

## 8. Ansible runtime — the devops-toolkit container

All `ansible*` (and `kubectl`, `helm`, `vault`, etc.) commands run inside the `devops-toolkit` container, not on the host directly. This pins tool versions across machines and follows the existing pattern from the work PoC.

The toolkit is consumed via **zsh aliases**, not standalone shell scripts. The aliases are set up by the `control_node` role and live in a sourced file (e.g., `~/.zshrc.d/scaffoldrack-toolkit.zsh`). They invoke `docker run` with appropriate mounts and environment for each tool. Example pattern:

```bash
alias ansible="docker run --rm -it \
  -v $(pwd):/workspace \
  -v ~/.ssh:/home/runner/.ssh:ro \
  -w /workspace \
  --network host \
  devops-toolkit:latest \
  ansible"
```

The control_node role also sets up tab completion (via `compdef` and generated completion files) and helper functions beyond simple aliases.

The container has SSH access to managed hosts because `~/.ssh` is bind-mounted read-only. bob's private key lives there as `~/.ssh/bob_ed25519`.

The toolkit aliases file is committed to the repo at `roles/control_node/files/scaffoldrack-toolkit.zsh` so it's version-controlled and idempotent — re-running the control_node role updates the file in place if it has changed.

## 9. Inventory model

Two relevant groups:

- **`debian`** — every host (commander, ai, pve1, pve2). Receives baseline + hardening.
- **`proxmox`** — pve1, pve2 only. Additionally receives the Proxmox conversion role.

commander has `ansible_connection: local`. Other hosts use `ansible_user: bob` and key auth (post-bootstrap) or `ansible_user: andrew` (during bootstrap, with `--ask-become-pass`).

Host-specific overrides go in `host_vars/<hostname>.yml` if needed; group-level config in `group_vars/`.

## 10. Validation order

Each step gets validated against a low-stakes target before being applied to production-leaning hosts. The order:

1. **commander** for control-node-specific things (`bootstrap-control-node.sh` and `control-node.yml` run here)
2. **ai** for managed-host validation — it's a real host but not a hypervisor, so mistakes are recoverable
3. **pve2** before pve1 — both are hypervisors, but pve2 is the "second" one and gets things first; pve1 follows once pve2 is proven
4. Eventually parity: same configuration applied to all four hosts via `site.yml`

## 11. Secrets handling

- bob's private key: lives at `~/.ssh/bob_ed25519` on the control node. Never committed.
- bob's public key: `files/bob.pub`. Committed.
- bob's sudo password: not used (NOPASSWD).
- andrew's sudo password: typed at bootstrap time via `--ask-become-pass`. Never stored in the repo, never typed twice (one bootstrap per host lifetime).
- ansible-vault: not currently in use. Future addition when there are secrets needing repo-resident encryption (TLS keys, API tokens). Vault password handling will be designed at that time.

## 12. Current state

**Phase 0 — Bootstrap.** Repo is being initialized. The Ansible work proceeds in this order:

1. Repo skeleton (CONTEXT, INSTRUCTIONS, ADRs, .gitignore, ansible.cfg)
2. `scripts/bootstrap-control-node.sh` — Docker + devops-toolkit image only
3. `roles/control_node/` — zsh, oh-my-zsh, toolkit aliases, completions
4. `playbooks/control-node.yml` — applies control_node role to localhost
5. `inventory/hosts.yml` and `group_vars/` — define the four hosts
6. `playbooks/ping.yml` — smoke test, proves connectivity
7. `roles/bootstrap_bob/` — declarative version of the bootstrap user creation
8. `playbooks/bootstrap.yml` — onboard a managed host using bootstrap_bob role
9. `roles/baseline/` — hostname, NTP, packages, sources
10. `roles/hardening/` — SSH, UFW, fail2ban, sysctl, audit, PAM, banner
11. `playbooks/site.yml` — composes the above
12. `roles/proxmox/` — Debian-to-Proxmox conversion (later phase)

## 13. What's NOT in scope here

- **Kubernetes provisioning.** That's the Talos work in the `proxmox` repo.
- **GitOps app deployment.** That's ArgoCD, lives in `platform-services` (eventually).
- **Network configuration.** UDM Pro and VLAN setup is in `network`.
- **Application deployment.** Mailu, Vaultwarden, Wyatt's site, Z's site — those land via ArgoCD on the eventual cluster.
- **Backup orchestration.** Velero is in scope for `platform-services` later.
- **Observability stack.** Grafana/Loki/Tempo/Mimir is in scope for `observability`.
- **Personal dotfiles.** Personal preferences beyond what the `control_node` role provides (custom prompts, non-toolkit aliases, vim/nvim config, etc.) belong in a separate private dotfiles repo, not here.

This repo's job ends at "host is configured, hardened, and ready for whatever comes next."

## 14. Cross-references

- **Platform meta-repo:** `gitea.mercnet.info/scaffoldrack/platform` — overall project map.
- **Cross-cutting decisions:** `notes/decisions/` (private).
- **Tools and templates:** `gitea.mercnet.info/scaffoldrack/tools` — repo scaffolding, conventions, helper scripts.
- **Blog narrative:** `thescaffoldrack.com`.
- **Internal Gitea:** `gitea.mercnet.info/scaffoldrack/bootstrap` — push-primary, GitHub mirror.
- **docker-devops upstream:** `github.com/andrewjkrull/docker-devops` — source of the toolkit container image.
