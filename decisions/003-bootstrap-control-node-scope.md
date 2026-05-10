# ADR-003 — `bootstrap-control-node.sh` Has Narrow Scope (Docker + Container Only)

**Status:** Accepted
**Date:** 2026-05-09 (decision made), 2026-05-10 (formalized as ADR)
**Decision-makers:** Andrew Krull, with chat-Claude as collaborator

## Context

The control node needs to be set up before Ansible can do any work. There's a chicken-and-egg problem: Ansible can configure machines, but the control node IS a machine, and it needs Ansible to run on it before it can run Ansible. Some bootstrapping has to happen outside Ansible.

The question is *how much* bootstrapping happens outside Ansible. The narrowest possible answer is "just enough to make Ansible runnable." The broadest possible answer is "everything the operator needs on day one."

A bootstrap script that does too much becomes:
- A second source of truth for control-node configuration (alongside Ansible roles)
- An untested, ad-hoc imperative blob that drifts from what Ansible would do
- A maintenance burden that gets edited when "just one more thing" needs to land
- Hard to validate (can't test against a fresh VM the way idempotent Ansible roles can be)

A bootstrap script that does too little leaves the operator with an unworkable system that requires significant manual setup before Ansible can take over.

The right answer is somewhere in the middle, with a clear principle for where the line is.

## Decision

**`scripts/bootstrap-control-node.sh` does exactly two things:**

1. Installs Docker (apt-installable, idempotent)
2. Builds or pulls the `devops-toolkit:latest` container image

That's the whole script. Everything else — zsh installation, oh-my-zsh setup, toolkit alias deployment, completions generation, kubectl-completion-bash setup, ssh config, anything that configures the operator's environment beyond bare runnable-Ansible — happens via Ansible roles after the script completes.

The script is the thinnest possible "bootstrap-the-bootstrap" surface: it produces the runtime (Docker + container), and after that, Ansible takes over.

The principle: **anything that can be done by Ansible should be done by Ansible.** The shell script exists only because Ansible can't yet run on the host. The moment Ansible can run (i.e., Docker + container are available), we switch to Ansible for everything.

If a request would expand the script beyond Docker + container image, push back and propose an Ansible role instead. Specific examples of things that have come up and were rejected:

- "Also install zsh while you're there" → No. `roles/control_node/` installs zsh.
- "Also drop the toolkit aliases file" → No. `roles/control_node/files/scaffoldrack-toolkit.zsh` is deployed by the role.
- "Also generate bob's keypair" → No. That's an operator task (per ADR-001's runbook); when automated, it'll be in `roles/bootstrap_bob/` or a separate provisioning step, not in the bootstrap script.
- "Also set up oh-my-zsh" → No. `roles/control_node/` handles that.

The script is allowed to:

- Be idempotent (safe to re-run)
- Use the standard logging helpers (`log` / `warn` / `die`)
- Detect existing state (Docker installed? container present?) and skip with `warn` rather than re-doing work
- Print clear next steps at the end (the bootstrap-the-bootstrap manual run)

The script is NOT allowed to:

- Modify `~/.zshrc`, `~/.bashrc`, or any shell rc files
- Install any Linux package other than Docker and Docker's dependencies
- Create any user accounts
- Write any configuration outside of what Docker and the container image require
- Deploy any tool aliases or wrappers

## Consequences

**Positive:**
- The script stays simple. ~50-100 lines max. Easy to read, easy to validate, easy to run on a fresh VM and trust.
- Single source of truth for control-node configuration is Ansible (specifically `roles/control_node/`). The shell script doesn't compete.
- Recovery is clean: if the control node is rebuilt, the operator runs the script (gets Docker + container) and then runs the bootstrap-the-bootstrap step (gets the rest via Ansible). No "did I remember to also do X manually?" surface.
- Easy to test against fresh VMs. The script either succeeds or fails; success means "Ansible can now run from this host."
- Aligns with the tooling-vs-declarative-state distinction (`kb/meta/2026-05-10-tooling-vs-declarative-state.md`): the script is tooling (run on demand to install Docker + container); everything else is declarative state belonging in Ansible.

**Negative:**
- **The bootstrap-the-bootstrap step is an explicit two-stage process.** Run script. Then manually run `ansible-playbook playbooks/control-node.yml` via raw `docker run`. The operator has to know about both stages.
- **Re-running the script doesn't get you a fully-configured machine.** It gets you Docker + container. The operator still has to run the bootstrap-the-bootstrap step. Documentation has to be clear about this; otherwise someone re-runs the script expecting full setup and gets confused.

**Neutral:**
- The "two stages" is genuinely two stages because of the bootstrap chicken-and-egg. This isn't a workaround; it's the actual shape of the problem.

## Alternatives Considered

### Alternative 1: One big bootstrap script that does everything

Install Docker, build container, install zsh, configure shell rc files, deploy aliases, set up oh-my-zsh, generate completions, all in one script.

**Why not chosen:**
- The script becomes the thing that knows how to configure control nodes. Ansible has a `roles/control_node/` role, but now we have two systems doing the same job. They drift.
- "One more thing" syndrome: every time the operator wishes the bootstrap had set up X, X gets added to the script. Eventually the script is unmaintainable.
- Re-running is dangerous because the script isn't structured as idempotent declarative reconciliation; it's just imperative steps that may or may not be safe to re-run depending on what was added.
- Hard to test: changes to the script can break in subtle ways that only show up on real fresh VMs.

### Alternative 2: No script at all; everything via Ansible from a peer machine

The first time, the operator runs Ansible from another machine (Cyclone, the work machine, another control node) targeting the new control node, with `--ask-become-pass`. That installs Docker, etc. on the new control node, and after that the new control node operates itself.

**Why not chosen:**
- Requires an existing Ansible-capable peer to bootstrap a new control node. Chicken-and-egg moves to a different machine but isn't eliminated.
- For a single-control-node platform, there's no peer. The first control node has no one to bootstrap it.
- Even with peers, the operational cost (set up SSH from peer to new node, manage credentials) is higher than just running a local script.
- May be a viable model in a later life of the platform, when there are multiple control nodes and a bootstrap-from-peer pattern is genuinely simpler than a script.

### Alternative 3: Configuration management tool that runs locally (e.g., Puppet, Salt, or Ansible-pull)

Ansible-pull lets a host pull and apply its own configuration without a central control node. The first run could happen locally with a small wrapper.

**Why not chosen:**
- Adds a different operational pattern (pull-based) that doesn't match the rest of the platform (push-based Ansible from control node).
- The "small wrapper" turns into a script that does Docker + ansible-pull, which is roughly equivalent to the current design but in a less-conventional shape.
- Doesn't actually shrink the bootstrap surface; it just moves it.

### Alternative 4: Cloud-init or similar provisioning hooks

Have the OS image's first-boot hooks install Docker + container.

**Why not chosen:**
- Tied to specific OS provisioning patterns. commander is a Pi 5 with a manually-flashed Debian image; cloud-init isn't the natural choice there.
- Couples bootstrap to the OS install method. If the OS is reinstalled differently, the cloud-init story doesn't help.
- A simple shell script is more portable across whatever provisioning method gets used.

### Alternative 5: The script does Docker only; container build/pull is also Ansible's job

Even narrower scope: the script JUST installs Docker. The container image gets built or pulled by Ansible.

**Why not chosen:**
- Creates a third stage: install Docker (script) → pull container image (?) → bootstrap-the-bootstrap. The third stage requires Docker AND ansible AND access to the registry; that's a manual `docker pull` or a separate step.
- The "build or pull container" operation is a clean unit of work that pairs naturally with the Docker install in a single script.
- Docker installation and image acquisition are both "make Ansible runnable" — they belong together as one pre-Ansible stage.
- Marginal benefit doesn't justify the extra ceremony.

## Trade-offs Accepted

**Two-stage bootstrap process is explicit and documented.** The bootstrap script is stage 1; the manual `ansible-playbook playbooks/control-node.yml` invocation is stage 2. Operators have to know about both. We accept this because the alternative (one mega-script) creates worse problems with maintainability and drift.

**The script is a "stop-gap" by design.** Its job is bridging the gap between "fresh OS" and "Ansible can run." Everything else is Ansible's job. We accept the script's narrow scope even though it would be tempting to make it do more.

**Re-running the script alone doesn't fully restore a control node.** The operator has to also re-run the bootstrap-the-bootstrap step. README and CONTEXT.md make this clear.

## When This Is the Wrong Choice

This decision could be wrong in scenarios where:

- **The two-stage process becomes a real source of operator error.** If operators (especially future ones) keep getting confused about when to run the script vs. when to run the bootstrap-the-bootstrap step, the design is failing them. We'd revisit by either documenting harder or merging the two stages.
- **Ansible-pull or a similar pattern becomes the standard.** If the platform shifts to a pull-based model, this script's role changes or disappears.
- **The operator wants to bootstrap a machine without Ansible at all.** Edge case; not a current scenario. If it appears, we'd write a different script for that case rather than expanding this one.
- **The control node grows to need things that genuinely can't be done via Ansible.** Hard to imagine; Ansible can do almost anything. If we hit a real wall, we'd reconsider.

## Cross-references

- `scripts/bootstrap-control-node.sh` — the implementation (when written)
- `roles/control_node/` — what the script explicitly does NOT do; lives in Ansible (when written)
- `playbooks/control-node.yml` — the bootstrap-the-bootstrap step's playbook (when written)
- `decisions/002-toolkit-container-as-runtime.md` — sibling: why the toolkit container is the runtime
- `kb/meta/2026-05-10-tooling-vs-declarative-state.md` — the framing that situates this script as tooling (Docker + container install) and everything else as declarative state (Ansible)
