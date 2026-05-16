---
status: accepted
date: 2026-05-09
decision-makers: Andrew Krull (with chat-Claude as collaborator)
---

# Keep `bootstrap-control-node.sh` Narrowly Scoped (Docker + Container Only)

## Context and Problem Statement

The control node needs to be set up before Ansible can do any work. There's a chicken-and-egg problem: Ansible can configure machines, but the control node IS a machine, and it needs Ansible to run on it before it can run Ansible. Some bootstrapping has to happen outside Ansible.

The question is *how much* bootstrapping happens outside Ansible. The narrowest possible answer is "just enough to make Ansible runnable." The broadest possible answer is "everything the operator needs on day one."

A bootstrap script that does too much becomes:

* A second source of truth for control-node configuration (alongside Ansible roles)
* An untested, ad-hoc imperative blob that drifts from what Ansible would do
* A maintenance burden that gets edited when "just one more thing" needs to land
* Hard to validate (can't test against a fresh VM the way idempotent Ansible roles can be)

A bootstrap script that does too little leaves the operator with an unworkable system that requires significant manual setup before Ansible can take over.

The right answer is somewhere in the middle, with a clear principle for where the line is.

## Decision Drivers

* Avoid a second source of truth competing with Ansible roles
* Resist "one more thing" scope creep
* Allow validation against fresh VMs (script either succeeds or fails)
* Keep recovery simple and predictable
* Apply the tooling-vs-declarative-state distinction: the script is tooling; everything else is declarative state belonging in Ansible

## Considered Options

* `bootstrap-control-node.sh` does exactly two things: install Docker, build/pull the container image
* One big bootstrap script that does everything (install Docker, build container, install zsh, configure shell rc files, deploy aliases, set up oh-my-zsh, generate completions)
* No script at all; bootstrap via Ansible from a peer machine with `--ask-become-pass`
* Configuration-management tool that runs locally (Ansible-pull, Puppet, Salt)
* Cloud-init or similar provisioning hooks at OS install time
* The script does Docker only; container build/pull is also Ansible's job

## Decision Outcome

Chosen option: **"`bootstrap-control-node.sh` does exactly two things: install Docker, build/pull the container image"**, because it produces the runtime (Docker + container) needed for Ansible and stops there. Everything else — zsh installation, oh-my-zsh setup, toolkit alias deployment, completions generation, kubectl-completion-bash setup, ssh config, anything that configures the operator's environment beyond bare runnable-Ansible — happens via Ansible roles after the script completes.

The principle: **anything that can be done by Ansible should be done by Ansible.** The shell script exists only because Ansible can't yet run on the host. The moment Ansible can run (i.e., Docker + container are available), we switch to Ansible for everything.

If a request would expand the script beyond Docker + container image, push back and propose an Ansible role instead. Specific examples of requests that have come up and been rejected:

* "Also install zsh while you're there" → No. `roles/control_node/` installs zsh.
* "Also drop the toolkit aliases file" → No. `roles/control_node/files/scaffoldrack-toolkit.zsh` is deployed by the role.
* "Also generate bob's keypair" → No. That's an operator task (per ADR-0001's runbook); when automated, it'll be in `roles/bootstrap_bob/` or a separate provisioning step, not in the bootstrap script.
* "Also set up oh-my-zsh" → No. `roles/control_node/` handles that.

The script is allowed to:

* Be idempotent (safe to re-run)
* Use the standard logging helpers (`log` / `warn` / `die`)
* Detect existing state (Docker installed? container present?) and skip with `warn` rather than re-doing work
* Print clear next steps at the end (the bootstrap-the-bootstrap manual run)

The script is NOT allowed to:

* Modify `~/.zshrc`, `~/.bashrc`, or any shell rc files
* Install any Linux package other than Docker and Docker's dependencies
* Create any user accounts
* Modify existing accounts' group memberships (see ADR-0005)
* Write any configuration outside of what Docker and the container image require
* Deploy any tool aliases or wrappers

### Consequences

* Good, because the script stays simple. ~50-100 lines max. Easy to read, validate, and run on a fresh VM and trust.
* Good, because single source of truth for control-node configuration is Ansible (specifically `roles/control_node/`). The shell script doesn't compete.
* Good, because recovery is clean: if the control node is rebuilt, the operator runs the script (gets Docker + container) and then runs the bootstrap-the-bootstrap step (gets the rest via Ansible). No "did I remember to also do X manually?" surface.
* Good, because the script either succeeds or fails on a fresh VM. Success means "Ansible can now run from this host."
* Good, because aligns with the tooling-vs-declarative-state distinction (`kb/meta/2026-05-10-tooling-vs-declarative-state.md`).
* Bad, because the bootstrap-the-bootstrap step is an explicit two-stage process. Run script. Then manually run `sudo docker run ... ansible-playbook playbooks/control-node.yml`. The operator has to know about both stages.
* Bad, because re-running the script doesn't get you a fully-configured machine — it gets you Docker + container. The operator still has to run the bootstrap-the-bootstrap step. Documentation has to be clear about this.
* Neutral, because the "two stages" is genuinely two stages because of the bootstrap chicken-and-egg. This isn't a workaround; it's the actual shape of the problem.

### Confirmation

After running the script on a fresh VM: `command -v docker` succeeds, `docker image inspect devops-toolkit:latest` succeeds, the script's "next steps" output points to the bootstrap-the-bootstrap `sudo docker run` invocation. Re-running the script produces "already done, skipping" warns for both steps.

## Pros and Cons of the Options

### `bootstrap-control-node.sh` does exactly two things

See the Consequences section above.

### One big bootstrap script that does everything

Install Docker, build container, install zsh, configure shell rc files, deploy aliases, set up oh-my-zsh, generate completions, all in one script.

* Bad, because the script becomes the thing that knows how to configure control nodes. Ansible has a `roles/control_node/` role; now two systems do the same job. They drift.
* Bad, because "one more thing" syndrome: every time the operator wishes the bootstrap had set up X, X gets added to the script. Eventually unmaintainable.
* Bad, because re-running is dangerous: the script isn't structured as idempotent declarative reconciliation; it's just imperative steps that may or may not be safe to re-run.
* Bad, because hard to test: changes can break in subtle ways that only show up on real fresh VMs.

### No script at all; bootstrap via Ansible from a peer machine

First time, run Ansible from another machine (work machine, peer) targeting the new control node with `--ask-become-pass`. Installs Docker, etc. on the new control node, after which it operates itself.

* Bad, because requires an existing Ansible-capable peer to bootstrap a new control node. Chicken-and-egg moves but isn't eliminated.
* Bad, because for a single-control-node platform, there's no peer. The first control node has no one to bootstrap it.
* Bad, because even with peers, the operational cost (set up SSH from peer to new node, manage credentials) is higher than just running a local script.
* Neutral, because may be viable in a later life of the platform with multiple control nodes.

### Configuration-management tool that runs locally (Ansible-pull, Puppet, Salt)

Ansible-pull lets a host pull and apply its own configuration without a central control node.

* Bad, because adds a different operational pattern (pull-based) that doesn't match the rest of the platform (push-based from control node).
* Bad, because the "small wrapper" turns into a script that does Docker + ansible-pull, roughly equivalent to the current design in less-conventional shape.
* Bad, because doesn't actually shrink the bootstrap surface; just moves it.

### Cloud-init or similar provisioning hooks

Have the OS image's first-boot hooks install Docker + container.

* Bad, because tied to specific OS provisioning patterns. commander is a Pi 5 with a manually-flashed Debian image; cloud-init isn't the natural choice.
* Bad, because couples bootstrap to the OS install method. If the OS is reinstalled differently, cloud-init doesn't help.
* Bad, because a simple shell script is more portable across whatever provisioning method gets used.

### The script does Docker only; container build/pull is also Ansible's job

Even narrower scope. The script JUST installs Docker. Container image is built or pulled by Ansible.

* Bad, because creates a third stage: install Docker (script) → pull container image (?) → bootstrap-the-bootstrap. The third stage requires Docker AND ansible AND access to the registry; that's a manual `docker pull` or a separate step.
* Bad, because "build or pull container" is a clean unit that pairs naturally with Docker install in one script.
* Bad, because Docker installation and image acquisition are both "make Ansible runnable" — they belong together.
* Neutral, because the marginal benefit doesn't justify the extra ceremony.

## More Information

### Trade-offs explicitly accepted

* **Two-stage bootstrap process is explicit and documented.** Script is stage 1; manual `sudo docker run ... ansible-playbook playbooks/control-node.yml` is stage 2. Operators have to know about both. Accepted because the alternative (one mega-script) creates worse problems with maintainability and drift.
* **The script is a "stop-gap" by design.** Its job is bridging "fresh OS" and "Ansible can run." Everything else is Ansible's job. Accepted even though it would be tempting to make the script do more.
* **Re-running the script alone doesn't fully restore a control node.** The operator has to also re-run the bootstrap-the-bootstrap step. README and CONTEXT.md make this clear.

### When this is the wrong choice

* **The two-stage process becomes a real source of operator error.** If operators (especially future ones) keep getting confused about when to run the script vs. when to run the bootstrap-the-bootstrap step, the design is failing them. Revisit by documenting harder or merging the two stages.
* **Ansible-pull or a similar pattern becomes the standard.** If the platform shifts to a pull-based model, this script's role changes or disappears.
* **The operator wants to bootstrap a machine without Ansible at all.** Edge case; not a current scenario. If it appears, write a different script for that case rather than expanding this one.
* **The control node grows to need things that genuinely can't be done via Ansible.** Hard to imagine; Ansible can do almost anything. If we hit a real wall, reconsider.

### Cross-references

* `scripts/bootstrap-control-node.sh` — the implementation (when written)
* `roles/control_node/` — what the script explicitly does NOT do; lives in Ansible (when written)
* `playbooks/control-node.yml` — the bootstrap-the-bootstrap step's playbook (when written)
* `decisions/0002-toolkit-container-as-runtime.md` — sibling: why the toolkit container is the runtime
* `decisions/0005-no-docker-group-modification.md` — sibling: extends this ADR's prohibition into group-membership space
* `kb/meta/2026-05-10-tooling-vs-declarative-state.md` — the framing that situates this script as tooling (Docker + container install) and everything else as declarative state (Ansible)
