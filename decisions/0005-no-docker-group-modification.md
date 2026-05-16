---
status: accepted
date: 2026-05-16
decision-makers: Andrew Krull (with chat-Claude as collaborator)
---

# `bootstrap-control-node.sh` Does Not Modify User Group Membership

## Context and Problem Statement

Standard Debian Docker installation produces a state in which `docker` commands require either root or membership in the `docker` group. The standard post-install recommendation is to add the operator's user account to the `docker` group so subsequent `docker` commands can run without `sudo`.

The bootstrap control node needs to run `docker` commands in two places:

1. Inside `scripts/bootstrap-control-node.sh` itself, during the build-or-pull-the-toolkit-container step (stage 1). This invocation already runs in an elevated context — the script needs root for the apt install portion regardless.
2. In the bootstrap-the-bootstrap manual step (stage 2), where the operator invokes `docker run ... ansible-playbook playbooks/control-node.yml --ask-become-pass`. This happens after the script finishes, in a regular operator shell.

The question is who handles the operator's `docker` group membership, and how stage 2's `docker run` invocation gets its required Docker access.

ADR-0003 explicitly prohibits the script from "creating any user accounts," but is silent on modifying existing accounts' group membership. So the strict letter of ADR-0003 leaves room for the script to add andrew to the docker group; the question is whether it should, given the broader principle ADR-0003 expresses (operator-environment configuration is Ansible's job, not the script's).

The 3am rule is the other relevant constraint: whichever pattern is chosen has to be debuggable and operable when the operator is tired. Patterns that require subtle shell-state gymnastics (group membership not taking effect until a new shell starts) score badly on this axis.

## Decision Drivers

* Honor ADR-0003's spirit (operator-environment configuration belongs in Ansible)
* No shell-state gymnastics for the operator between stage 1 and stage 2
* Minimize disruption to commander, which hosts Gitea and the kb (so reboot-as-recovery is heavy)
* Predictable runbook across re-runs (no "first time you need sudo, later times you don't" branching)
* Aligned with the 3am rule

## Considered Options

* No group modification; stage 2 uses `sudo docker run ...`
* Script adds andrew to docker group; runbook uses `newgrp docker` or new shell before stage 2
* Script adds andrew to docker group; runbook says reboot before stage 2
* Script adds andrew to docker group; runbook uses `sg docker -c '<command>'` to run stage 2 under the new group without refresh

## Decision Outcome

Chosen option: **"No group modification; stage 2 uses `sudo docker run ...`"**, because it produces zero shell-state gymnastics for the operator, aligns with ADR-0003's principle that operator-environment configuration is Ansible's job, and avoids disrupting commander's other services with a reboot.

Specifically:

* `scripts/bootstrap-control-node.sh` does NOT add andrew (or any user) to the `docker` group.
* Stage 2's bootstrap-the-bootstrap invocation uses `sudo docker run ...`. The script's "next steps" output prints the `sudo docker run ...` form, not the unprefixed form.
* When `roles/control_node/` runs later (as part of the bootstrap-the-bootstrap step or subsequent `site.yml` applications), it adds andrew to the docker group as part of broader operator-environment configuration. By the time that role runs, the operator is already in a transitional state (re-sourcing shell to pick up new aliases, opening new sessions to use the toolkit), so the "new shell required for group membership to take effect" moment lands where it's expected rather than where it's surprising.

This decision extends ADR-0003's "is NOT allowed to" list. The script's hard-prohibition list (in Scope 3 CLAUDE.md and reinforced in the script's own header comment) explicitly includes "add any user to the docker group" alongside ADR-0003's existing prohibitions.

### Consequences

* Good, because zero shell-state gymnastics in the runbook. The operator finishes stage 1, types `sudo docker run ...`, continues. No `newgrp docker`, no new shell, no reboot, no waiting for a session refresh.
* Good, because the script stays narrowly scoped per ADR-0003's spirit. Operator-environment configuration (groups, shell, aliases) remains entirely in Ansible's domain.
* Good, because the runbook is identical across re-runs. There's no "first time you need sudo, subsequent times you don't" branching that depends on which previous step the operator did or didn't complete.
* Good, because recoverable from a broken state without surprises. If `roles/control_node/` hasn't run yet — or has run but the operator is in a stale shell — `sudo docker` still works, so stage 2 still works.
* Bad, because stage 2 commands require typing `sudo`. Real annoyance for repeated invocations during development. Mitigation: stage 2 is genuinely one-time-per-control-node, not a daily-driver workflow.
* Bad, because operators who know the standard Docker post-install recommendation may expect the script to have set up group membership and be briefly confused. Mitigation: the script's next-steps output makes the `sudo docker run ...` form explicit; the operator follows the instruction rather than reaching for muscle memory.
* Bad, because the "no group membership configured yet" intermediate state must persist between script completion and `roles/control_node/` running. If anyone shells into the control node between those two stages expecting to use Docker without sudo, they'll be briefly confused. Mitigation: that gap is short in practice; the bootstrap-the-bootstrap step is the first thing the operator does after the script.
* Neutral, because this decision treats group membership as "operator environment configuration" rather than part of "make Docker runnable." Consistent with how the platform treats other shell-state configuration (zsh, aliases, completions): all Ansible's job, none of the script's.

### Confirmation

The script's own structural review (during draft) checks that no `usermod -aG docker ...` invocation is present. The script's header comment lists the prohibition explicitly. Code-Claude's structural review of the draft can be told to verify this as part of scope-conformance.

## Pros and Cons of the Options

### No group modification; stage 2 uses `sudo docker run ...`

See the Consequences section above.

### Script adds andrew to docker group; runbook uses `newgrp docker` or new shell before stage 2

* Good, because subsequent `docker` commands work without sudo after the refresh.
* Bad, because adds a "open a new shell" or "run newgrp docker" step to the runbook between stage 1 and stage 2.
* Bad, because the step is easy to forget. Forgetting produces a confusing "permission denied" error that the operator has to diagnose.
* Bad, because ADR-0003's spirit (operator-environment is Ansible's job) gets weakened — the script is now modifying operator-environment state, just in a different way than the explicitly-prohibited shell-rc-file modifications.

### Script adds andrew to docker group; runbook says reboot before stage 2

* Good, because reboot is a clean reset that the operator definitely understands.
* Bad, because commander hosts Gitea (push-primary for every scaffoldrack repo) and the kb. A reboot during platform work has real consequences — Gitea goes down, anything in flight gets killed, anyone using the kb or Gitea sees interruption.
* Bad, because builds reboot-as-recovery into the standard workflow, which is heavier than the problem warrants.
* Bad, because reboots can fail in surprising ways (boot loops, services not coming back, etc.). The 3am rule cuts against reboots in runbooks.
* Bad, because same ADR-0003-spirit violation as option 2.

### Script adds andrew to docker group; runbook uses `sg docker -c '<command>'`

* Good, because works without reboot or new shell.
* Bad, because `sg` wrapping is awkward and adds a "why is this command wrapped in `sg`?" moment to the runbook.
* Bad, because not 3am-friendly — operator has to know `sg` semantics.
* Bad, because same ADR-0003-spirit violation as options 2 and 3.

## More Information

### Trade-offs explicitly accepted

* **Stage 2 requires typing `sudo`.** Real annoyance, but the invocation happens once-per-control-node. The cost is one extra word, once, ever. Accepted as preferable to any of the alternatives' shell-state complications.
* **Brief operator confusion possible** if the operator expects standard Docker post-install behavior. Mitigated by explicit script output telling the operator what to type next.
* **The decision is asymmetric** between stage 1 (script invokes `docker` as root anyway during install) and stage 2 (operator types `sudo docker run`). That asymmetry is intentional: stage 1's script runs in elevated context for the apt install regardless, so it can use Docker without group membership; stage 2 runs as the operator and uses sudo. There's no "the script can but the operator can't" problem — the operator can always use sudo.

### When this is the wrong choice

* **The runbook proves to be 3am-hostile despite the design.** If operators repeatedly forget the `sudo` and produce confusing errors, the design is failing them. Revisit by either documenting harder, changing the script's "next steps" output to be more emphatic, or reconsidering the trade-off.
* **Stage 2 becomes interactive or repeated.** If, for some reason, stage 2 evolves into a workflow with multiple `docker` invocations the operator types repeatedly, the `sudo` cost grows. Reconsider in that scenario.
* **A different runtime model replaces the docker-run pattern.** If the toolkit moves to `docker exec` against a long-running container, or to a non-Docker runtime, this ADR retires with the underlying model.
* **Operator population changes.** If multiple operators are using the platform and the "no group, sudo always" pattern becomes friction at scale, revisit. The single-operator-homelab assumption is load-bearing here.

### Cross-references

* `decisions/0003-bootstrap-control-node-scope.md` — parent: defines the script's narrow scope; this ADR extends its prohibition list
* `decisions/0002-toolkit-container-as-runtime.md` — sibling: defines the runtime that consumes Docker
* `scripts/bootstrap-control-node.sh` — the implementation (when written)
* `roles/control_node/` — owns the subsequent group-membership configuration (when written)
* `CLAUDE.md` §"Repo-specific hard rules" — Scope 3 working agreement reinforces this prohibition
