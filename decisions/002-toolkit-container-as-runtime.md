# ADR-002 — devops-toolkit Container as the Ansible Runtime

**Status:** Accepted
**Date:** 2026-05-09 (decision made), 2026-05-10 (formalized as ADR)
**Decision-makers:** Andrew Krull, with chat-Claude as collaborator

## Context

The control node needs Ansible, kubectl, helm, vault, terraform, argocd, and similar infrastructure tooling. These tools have evolving versions, dependencies on specific Python or library versions, and frequent updates. Installing them directly on the control node's host OS leads to:

- Version drift between the control node and the work environment
- Brittle upgrades that risk the control node's stability
- "Works on my machine" failures when CI/CD or another developer runs the same playbooks
- Fragmentation: each tool has its own installation method (apt, snap, pip, brew, manual binary download)

Andrew already has a working pattern from his PoC work: a `devops-toolkit:latest` Docker container image that bundles all platform tools at known versions. Commands run inside the container; the host stays clean.

The question for bootstrap was whether to standardize on this container-based runtime or to install tools directly on commander's host OS.

## Decision

**The `devops-toolkit:latest` container is the runtime for all platform tooling.** Specifically:

- All `ansible*`, `kubectl`, `helm`, `vault`, `terraform`, `argocd`, etc. commands run inside the `devops-toolkit:latest` container.
- The container is consumed via **zsh aliases** set up by `roles/control_node/`. The aliases live in a sourced file (`~/.zshrc.d/scaffoldrack-toolkit.zsh` or similar) and invoke `docker run` with the right mounts and environment.
- The host's OS does NOT have Ansible, kubectl, helm, etc. installed directly. The host has Docker (to run the container) and the standard Debian baseline. That's it.
- The container has SSH access to managed hosts because `~/.ssh` is bind-mounted read-only. bob's private key (`~/.ssh/bob_ed25519`) is reachable from inside.
- The container is rebuilt or pulled when its definition changes. The platform owns the container's Dockerfile.

The bootstrap chain works like this:

1. `scripts/bootstrap-control-node.sh` runs on the host. It installs Docker (the only host-level dependency) and builds-or-pulls `devops-toolkit:latest`.
2. The user manually runs `docker run --rm -v $(pwd):/work -v ~/.ssh:/home/ansible/.ssh:ro -w /work devops-toolkit:latest ansible-playbook playbooks/control-node.yml --ask-become-pass`. This is the **bootstrap-the-bootstrap** step — it's manual because we're configuring the thing that will provide the alias for everything afterward.
3. `playbooks/control-node.yml` configures the control node: zsh, oh-my-zsh, the toolkit aliases, completions.
4. From that point forward, the user runs `ansible-playbook ...` and it transparently invokes the container via the alias. The user experience is "just run Ansible commands"; the container is invisible.

The toolkit aliases file at `roles/control_node/files/scaffoldrack-toolkit.zsh` is the canonical source. To change the alias behavior, edit the committed file and re-run the `control_node` role; don't edit the deployed file directly on commander.

## Consequences

**Positive:**
- The host stays minimal. Debian + Docker + nothing else. Easy to understand, easy to recover, easy to migrate to a new control node.
- Tool versions are pinned in the container's Dockerfile. Reproducible across machines, across time, across operators.
- Upgrades to the toolkit are atomic: rebuild the image, restart shells. No half-upgraded state on the host.
- The same container can be used in CI/CD pipelines, in development, and in production with no environment drift.
- Aliases mean the user doesn't have to think about the container — just run `ansible-playbook` as usual.
- bob's SSH key is bind-mounted read-only into the container; the container can authenticate without copying credentials.

**Negative:**
- **The bootstrap-the-bootstrap step is manual.** The first run of `ansible-playbook playbooks/control-node.yml` happens via raw `docker run`, not via the alias (because the alias isn't installed yet). This is a one-time-per-machine awkwardness; subsequent runs use the alias.
- **zsh is required as a runtime dependency, not a preference.** The toolkit aliases live in zsh format. If a user prefers bash, they're either translating manually or running `zsh -c '...'`. The platform commits to zsh as the operator shell.
- **Docker is a hard dependency on the control node.** If Docker is broken, the toolkit is unreachable, which means Ansible is unreachable, which means most platform operations are unreachable. Mitigation: Docker is well-supported on Debian and rarely breaks; the host is hardened to make Docker's failure domain as small as possible.
- **bind-mount complexity.** The aliases need to mount `pwd`, `~/.ssh`, and possibly other paths into the container. Getting the mounts right requires care (e.g., not mounting the entire home directory; mounting `~/.ssh` read-only; ensuring the container's user has access to the mounted paths).
- **No host-shell direct invocation.** A user who wants to run a one-off `ansible localhost -m setup` from a non-zsh shell, or from a script that doesn't source the aliases, has to either invoke the container directly or write the alias-equivalent. Friction for ad-hoc operations.

**Neutral:**
- Container image size is non-trivial (probably 1-2 GB depending on what's bundled). Acceptable on commander's storage; worth keeping an eye on as the toolkit grows.

## Alternatives Considered

### Alternative 1: Install Ansible and tools directly on the host

apt install ansible, then pip-install or download other tools. Standard Linux-admin pattern.

**Why not chosen:**
- Ansible's apt version is often behind upstream. pip install gets newer but conflicts with apt-managed Python on Debian (PEP 668 territory now).
- Tool version drift between the control node and any other developer machine.
- Upgrades risk breaking the control node. A failed pip install can leave a broken Python environment.
- Doesn't solve the kubectl/helm/vault/terraform problem; each is its own installation pattern.

### Alternative 2: A virtualenv with pip-installed Ansible + native binaries for k8s tools

`python3 -m venv ~/.ansible-venv`, install Ansible there. Drop kubectl/helm binaries in `/usr/local/bin`.

**Why not chosen:**
- Solves Ansible's version pinning but not the cross-tool consistency story.
- Multiple installation idioms for different tools (pip vs. binary download vs. apt).
- Python venv state drifts over time as pip dependencies update.
- Doesn't help if the work-machine or CI runs the same code — they'd need their own equivalent setup.

### Alternative 3: Nix or similar declarative package manager

Use Nix to manage all platform tooling reproducibly.

**Why not chosen:**
- Nix has a real learning curve; Andrew isn't currently a Nix user.
- Not aligned with the broader scaffoldrack toolchain (which is mostly Docker + Ansible + standard Linux).
- May reconsider in a future life of the platform if Nix becomes part of Andrew's standard toolset.

### Alternative 4: Run Ansible from a bastion / dedicated control machine without containers

Dedicate a VM or container that IS the control node, with everything installed inside it. Don't worry about host-level cleanliness.

**Why not chosen:**
- This is essentially the same model we picked, but at a coarser granularity (whole VM vs. on-demand container per command).
- Loses the "one container image, runs anywhere" portability.
- Adds VM management overhead.

The chosen approach is similar in spirit but uses the container as the runtime envelope, not as a VM-replacement.

### Alternative 5: GitHub Codespaces / GitPod / cloud-IDE-based runtime

Run Ansible from a cloud development environment.

**Why not chosen:**
- Adds a cloud dependency for what should be a self-hosted platform.
- Can't reach managed hosts (which are on the home network) without VPN/tunneling complexity.
- Conflicts with the homelab-as-self-hosted vision.

## Trade-offs Accepted

**zsh as required operator shell.** Andrew uses zsh; the platform commits to it. Bash users would need translation or `zsh -c` invocation. We accept this because: zsh is the dominant shell for ops work in 2026, the toolkit aliases are trivial to translate to bash if anyone needs it, and committing to one shell simplifies the integration.

**Manual bootstrap-the-bootstrap step.** The first `ansible-playbook playbooks/control-node.yml` run is via raw `docker run`, not the alias. Annoying once per machine. Acceptable because it's once and the alternative (bootstrap script that does both Docker AND zsh AND alias setup) was explicitly rejected for keeping `bootstrap-control-node.sh` narrowly scoped (per ADR-003).

**Container as a hard dependency.** If the container is broken, the platform is broken. Mitigations: container image is pinned, Docker is well-supported on Debian, image rebuilds are deterministic from the Dockerfile.

**`docker run` overhead per command.** Each Ansible run starts a new container instance. This adds latency (typically 100-500ms per invocation). Acceptable for normal use; might matter for tight automation loops. If it does become an issue, the answer is a long-running container (`docker exec` against a persistent container) — but that's a different runtime model and not on the table today.

## When This Is the Wrong Choice

This decision could be wrong in scenarios where:

- **The control node has resource constraints.** The Pi 5 (commander) has limited resources (CPU, memory, storage). If the toolkit container becomes too heavy or its instantiation latency is unacceptable, a native install on the host might win on performance. We'd revisit; the platform-tooling-on-Pi case is the main risk.
- **Multi-operator workflow with different shell preferences.** If others operate the platform and zsh is a problem, the alias model needs translation work. The container itself is shell-agnostic; only the alias presentation is zsh-specific.
- **Air-gapped operation.** If the control node ever needs to operate without Docker registry access, image pulls fail. We'd need a private registry (probably the platform's own, when it's up) or pre-baked images on the control node.
- **A future Ansible-native GitOps tool replaces the manual ansible-playbook invocation entirely.** If the entire control-node-runs-ansible model gets replaced by something like Argo Workflows or AWX, this whole pattern retires. That's the largest possible change and not on the horizon.

## Cross-references

- `scripts/bootstrap-control-node.sh` — installs Docker and the container (when written)
- `roles/control_node/` — deploys the toolkit aliases (when written)
- `roles/control_node/files/scaffoldrack-toolkit.zsh` — the canonical aliases (when written)
- `playbooks/control-node.yml` — the playbook that runs the role (when written)
- `kb/projects/scaffoldrack/CLAUDE.md` §1 — Scope 2 statement of the runtime model
- `decisions/003-bootstrap-control-node-scope.md` — sibling ADR: why the bootstrap script is narrowly scoped
- `~/Projects/scaffoldrack/projects/docker-devops/` — the kb's record of devops-toolkit container work
