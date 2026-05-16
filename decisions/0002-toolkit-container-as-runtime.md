---
status: accepted
date: 2026-05-09
decision-makers: Andrew Krull (with chat-Claude as collaborator)
---

# Use the `devops-toolkit` Container as the Ansible Runtime

## Context and Problem Statement

The control node needs Ansible, kubectl, helm, vault, terraform, argocd, and similar infrastructure tooling. These tools have evolving versions, dependencies on specific Python or library versions, and frequent updates. Installing them directly on the control node's host OS leads to:

* Version drift between the control node and the work environment
* Brittle upgrades that risk the control node's stability
* "Works on my machine" failures when CI/CD or another developer runs the same playbooks
* Fragmentation: each tool has its own installation method (apt, snap, pip, brew, manual binary download)

Andrew already has a working pattern from the PoC: a `devops-toolkit:latest` Docker container image that bundles all platform tools at known versions.

The question for bootstrap was whether to standardize on this container-based runtime or to install tools directly on commander's host OS.

## Decision Drivers

* Minimal host-OS footprint on the control node
* Reproducibility across machines, across time, across operators
* Atomic upgrades of the toolset (rebuild image, restart shells)
* Same runtime for development, CI, and production
* Self-hosted; no cloud dependency

## Considered Options

* Container-based runtime via `devops-toolkit:latest` with zsh aliases
* Install Ansible and tools directly on the host
* Python virtualenv for Ansible + native binaries for k8s tools
* Nix or similar declarative package manager
* Dedicated control VM with everything installed inside it
* Cloud IDE (GitHub Codespaces / GitPod) as the runtime

## Decision Outcome

Chosen option: **"Container-based runtime via `devops-toolkit:latest` with zsh aliases"**, because it keeps the host minimal, pins tool versions in the Dockerfile, makes upgrades atomic, and produces a single artifact that runs identically in dev, CI, and production.

Specifically:

* All `ansible*`, `kubectl`, `helm`, `vault`, `terraform`, `argocd`, etc. commands run inside `devops-toolkit:latest`.
* The container is consumed via zsh aliases set up by `roles/control_node/`. The aliases live in a sourced file (`~/.zshrc.d/scaffoldrack-toolkit.zsh` or similar) and invoke `docker run` with the right mounts and environment.
* The host's OS does NOT have Ansible, kubectl, helm, etc. installed directly. The host has Docker (to run the container) and the standard Debian baseline. That's it.
* The container has SSH access to managed hosts because `~/.ssh` is bind-mounted read-only. bob's private key (`~/.ssh/bob_ed25519`) is reachable from inside.
* The container is rebuilt or pulled when its definition changes. The platform owns the container's Dockerfile.

The bootstrap chain works like this:

1. `scripts/bootstrap-control-node.sh` runs on the host. It installs Docker (the only host-level dependency) and builds-or-pulls `devops-toolkit:latest`.
2. The user manually runs `sudo docker run --rm -v $(pwd):/work -v ~/.ssh:/home/ansible/.ssh:ro -w /work devops-toolkit:latest ansible-playbook playbooks/control-node.yml --ask-become-pass`. This is the **bootstrap-the-bootstrap** step — it's manual because we're configuring the thing that will provide the alias for everything afterward.
3. `playbooks/control-node.yml` configures the control node: zsh, oh-my-zsh, the toolkit aliases, completions.
4. From that point forward, the user runs `ansible-playbook ...` and it transparently invokes the container via the alias. The user experience is "just run Ansible commands"; the container is invisible.

The toolkit aliases file at `roles/control_node/files/scaffoldrack-toolkit.zsh` is the canonical source. To change the alias behavior, edit the committed file and re-run the `control_node` role; don't edit the deployed file directly on commander.

### Consequences

* Good, because the host stays minimal — Debian + Docker + nothing else. Easy to understand, recover, and migrate.
* Good, because tool versions pin in the container's Dockerfile; reproducible across machines, time, and operators.
* Good, because upgrades are atomic: rebuild the image, restart shells. No half-upgraded state.
* Good, because the same container can be used in CI/CD, development, and production with no environment drift.
* Good, because aliases mean the user doesn't think about the container — just runs `ansible-playbook` as usual.
* Good, because bob's SSH key is bind-mounted read-only into the container; the container can authenticate without copying credentials.
* Bad, because the bootstrap-the-bootstrap step is manual. The first run of `ansible-playbook playbooks/control-node.yml` is via raw `docker run`, not via the alias. One-time-per-machine awkwardness.
* Bad, because zsh becomes a required runtime dependency, not a preference. The toolkit aliases live in zsh format.
* Bad, because Docker is a hard dependency on the control node. If Docker is broken, the toolkit is unreachable.
* Bad, because bind-mount complexity: aliases need to mount `pwd`, `~/.ssh`, and possibly other paths correctly into the container.
* Bad, because there is no host-shell direct invocation. Users wanting one-off `ansible localhost -m setup` from non-zsh shells have to invoke the container directly.
* Neutral, because container image size is non-trivial (1-2 GB depending on bundling). Acceptable on commander's storage; worth watching as the toolkit grows.

### Confirmation

`type ansible-playbook` on a configured control node shows the toolkit alias definition (not a binary path). `ansible localhost -m ping` works through the alias. `docker run --rm devops-toolkit:latest which ansible kubectl helm` returns binary paths inside the container.

## Pros and Cons of the Options

### Container-based runtime via `devops-toolkit:latest` with zsh aliases

See the Consequences section above.

### Install Ansible and tools directly on the host

`apt install ansible`, then pip-install or download other tools.

* Bad, because Ansible's apt version is often behind upstream.
* Bad, because pip install gets newer but conflicts with apt-managed Python on Debian (PEP 668 territory now).
* Bad, because tool version drift between the control node and any other developer machine.
* Bad, because upgrades risk breaking the control node. A failed pip install can leave a broken Python environment.
* Bad, because doesn't solve the kubectl/helm/vault/terraform problem; each is its own installation pattern.

### Python virtualenv for Ansible + native binaries for k8s tools

`python3 -m venv ~/.ansible-venv` for Ansible, drop kubectl/helm binaries in `/usr/local/bin`.

* Good, because solves Ansible's version pinning.
* Bad, because doesn't solve cross-tool consistency.
* Bad, because multiple installation idioms (pip vs. binary download vs. apt).
* Bad, because Python venv state drifts over time as pip dependencies update.
* Bad, because doesn't help if work-machine or CI runs the same code — they'd need their own equivalent setup.

### Nix or similar declarative package manager

* Good, because produces reproducible tool environments across machines.
* Bad, because Nix has a real learning curve; Andrew isn't currently a Nix user.
* Bad, because not aligned with the broader scaffoldrack toolchain (mostly Docker + Ansible + standard Linux).
* Neutral, because may reconsider if Nix becomes part of Andrew's standard toolset.

### Dedicated control VM with everything installed inside it

* Bad, because essentially the same model as the chosen option but at coarser granularity.
* Bad, because loses "one container image, runs anywhere" portability.
* Bad, because adds VM management overhead.

### Cloud IDE (GitHub Codespaces / GitPod) as the runtime

* Bad, because adds a cloud dependency for what should be a self-hosted platform.
* Bad, because can't reach managed hosts (on home network) without VPN/tunneling complexity.
* Bad, because conflicts with the homelab-as-self-hosted vision.

## More Information

### Trade-offs explicitly accepted

* **zsh as required operator shell.** Andrew uses zsh; the platform commits to it. Bash users would need translation or `zsh -c` invocation. Accepted because zsh is dominant for ops work, aliases are trivial to translate, and committing to one shell simplifies integration.
* **Manual bootstrap-the-bootstrap step.** First `ansible-playbook playbooks/control-node.yml` run is via raw `docker run`. Acceptable because it's once-per-machine and the alternative (bootstrap script doing Docker AND zsh AND alias setup) was explicitly rejected for keeping `bootstrap-control-node.sh` narrowly scoped (see ADR-0003).
* **Container as a hard dependency.** If the container is broken, the platform is broken. Mitigations: container image pinned, Docker well-supported on Debian, image rebuilds deterministic from the Dockerfile.
* **`docker run` overhead per command.** Each Ansible run starts a new container instance — 100-500ms latency per invocation. Acceptable for normal use; if it becomes an issue, the answer is a long-running container with `docker exec` — but that's a different runtime model and not on the table today.

### When this is the wrong choice

* **The control node has resource constraints.** The Pi 5 (commander) has limited CPU, memory, storage. If the toolkit container becomes too heavy or its instantiation latency is unacceptable, a native install might win on performance. The platform-tooling-on-Pi case is the main risk.
* **Multi-operator workflow with different shell preferences.** If others operate the platform and zsh is a problem, the alias model needs translation work. The container itself is shell-agnostic; only the alias presentation is zsh-specific.
* **Air-gapped operation.** If the control node ever operates without Docker registry access, image pulls fail. Would need a private registry (probably the platform's own, when it's up) or pre-baked images on the control node.
* **A future Ansible-native GitOps tool replaces manual ansible-playbook invocation.** If the entire control-node-runs-ansible model gets replaced by something like Argo Workflows or AWX, this whole pattern retires. Not on the horizon.

### Cross-references

* `scripts/bootstrap-control-node.sh` — installs Docker and the container (when written)
* `roles/control_node/` — deploys the toolkit aliases (when written)
* `roles/control_node/files/scaffoldrack-toolkit.zsh` — the canonical aliases (when written)
* `playbooks/control-node.yml` — the playbook that runs the role (when written)
* `kb/projects/scaffoldrack/CLAUDE.md` §1 — Scope 2 statement of the runtime model
* `decisions/0003-bootstrap-control-node-scope.md` — sibling ADR: why the bootstrap script is narrowly scoped
* `decisions/0005-no-docker-group-modification.md` — sibling ADR: why the script doesn't add users to the docker group
* `~/Projects/scaffoldrack/projects/docker-devops/` — the kb's record of devops-toolkit container work
