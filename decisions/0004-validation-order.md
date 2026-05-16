---
status: accepted
date: 2026-05-09
decision-makers: Andrew Krull (with chat-Claude as collaborator)
---

# Validate Changes in Order: commander → ai → pve2 → pve1 → parity

## Context and Problem Statement

The bootstrap repo eventually applies changes to all four scaffoldrack hosts: commander, ai, pve1, pve2. Each change needs to be validated before being applied broadly, because mistakes during bootstrap (especially around SSH and sudo) can lock the operator out of a host.

Without a defined validation order, the natural temptation is to apply changes everywhere at once and hope. That approach is fine when changes are well-tested, but bootstrap itself is the testing; nothing is well-tested until it's been validated against a real host.

The order in which hosts get exposed to changes determines the recovery surface when something goes wrong. The order matters.

## Decision Drivers

* Predictable blast-radius progression — each step's failure mode is known and recoverable before the next step's stakes go up
* Easy to remember and apply without runtime judgment
* Each host's role in the platform suggests its position in the order
* Recovery on the lower-stakes hosts is cheaper than on the higher-stakes ones

## Considered Options

* Sequential: commander → ai → pve2 → pve1 → parity
* All four hosts in parallel
* pve1 first (lower-numbered hypervisor as "obvious first")
* A throwaway VM as the first validation target
* ai first, commander second
* pve1 and pve2 in parallel after ai

## Decision Outcome

Chosen option: **"Sequential: commander → ai → pve2 → pve1 → parity"**, because it produces predictable blast-radius progression with each step's failure recoverable before the next step's stakes increase.

The validation order for any change to a role, playbook, or script:

1. **commander** — first. For control-node-specific things (`bootstrap-control-node.sh`, `control-node.yml`, anything that touches the toolkit aliases). commander is the easiest to recover because Andrew has direct access (it's on his desk), and because commander is the control node — if commander is broken, NO automation runs anywhere, which is recoverable but limiting. Validating against commander first means catching control-node-specific bugs before they affect anything else.

2. **ai** — second. For managed-host changes (anything that runs against a remote host via SSH-as-bob). ai is a real host but not a hypervisor; it's running the AI stack (Ollama, Open WebUI). Mistakes on ai are recoverable: at worst we re-bootstrap ai. The applications running on ai can tolerate brief downtime.

3. **pve2** — third. The first hypervisor to be touched. Validates that bootstrap.yml (and downstream playbooks) work on Debian 13 Trixie (which pve2 is). pve2 was chosen as "first hypervisor" for the simple reason that pve1's name suggests primacy — operators have a tendency to call the lower-numbered host "the production one." pve2 going first means pve1 is undisturbed while pve2 is being figured out.

4. **pve1** — fourth. The second hypervisor, validated against the now-proven bootstrap pattern. By this point, bootstrap.yml has been applied to ai then pve2; there's high confidence the playbook works.

5. **parity** — finally. After all four hosts have been individually bootstrapped and validated, future changes (via `site.yml`, `roles/hardening/`, etc.) get applied uniformly to all four. The order at this stage matters less; per-host validation has already happened.

This order is a discipline, not a hard technical constraint. A purely cosmetic change (e.g., a typo fix in a comment) doesn't need to crawl through the order. But anything that affects host state (a new role, a new playbook, a non-trivial change to an existing playbook) gets the full validation treatment.

The order applies to bootstrap operations specifically. Once a host is bootstrapped, regular `site.yml` runs typically apply to all hosts at once — but `site.yml` is composed of well-validated roles, so per-host risk is much lower at that point.

### Consequences

* Good, because clear blast-radius progression. Each step has a known-recoverable target before the next step's stakes go up.
* Good, because commander first means a control-node-specific bug doesn't spread to managed hosts before being caught.
* Good, because ai second is low-stakes managed-host validation; if something is wrong with bootstrap.yml, ai can be re-imaged without serious cost.
* Good, because pve2 before pve1 means the more critical hypervisor (pve1, by operator naming convention if nothing else) stays untouched until the playbook is validated against pve2.
* Good, because easy to remember. Four hosts, fixed order, no decision required at runtime.
* Bad, because slower iteration — validating against four hosts in series is slower than running against all four at once. Accepted because the cost of an undetected bug propagating to all four is much higher than the cost of slower iteration.
* Bad, because discipline-not-enforcement. Nothing technically prevents an operator from skipping the order. Documented but not enforced.
* Neutral, because the order assumes the operator is sequencing changes one at a time. Multiple unrelated changes get the validation order independently.

### Confirmation

For any change to a role, playbook, or script: bootstrap CONTEXT.md §7 (Phase plan) and CLAUDE.md (this Scope 3 file) reference this validation order; session summaries note adherence or deliberate deviation.

## Pros and Cons of the Options

### Sequential: commander → ai → pve2 → pve1 → parity

See the Consequences section above.

### All four hosts in parallel

* Bad, because bugs affecting SSH or sudo can lock out all four hosts simultaneously. Recovery from "all four unreachable" is much worse than "ai unreachable, others fine."
* Bad, because no meaningful blast-radius control. The first run is the production run.
* Neutral, because acceptable for very-well-tested changes; this *is* the eventual model for `site.yml` runs against well-tested roles. Not the model for the bootstrap path.

### pve1 first (lower-numbered hypervisor as "obvious first")

* Bad, because operators (including Andrew) have a tendency to think of pve1 as "the primary" or "production" hypervisor. That mental model makes pve1 the worst place to test changes.
* Bad, because if something goes wrong on pve1 first, the "primary" hypervisor is the one being recovered, which feels worse even if the technical cost is similar.
* Neutral, because after pve2 is proven, applying to pve1 is low-risk — the order acknowledges this by putting pve1 last.

### A throwaway VM as the first validation target

* Good, because end-to-end script testing on a genuinely fresh VM is useful for the bootstrap script specifically.
* Bad, because adds a host to manage. The four real hosts ARE the validation surface; adding a fifth fictional one is overhead.
* Bad, because the throwaway VM may not match the real hosts' configurations (different OS version, package versions, network topology). False confidence is worse than no confidence.
* Neutral, because may add throwaway-VM validation to the workflow later for end-to-end script testing as a backlog item; not the primary validation pattern.

### ai first, commander second

* Bad, because many changes are control-node-specific (anything that touches `roles/control_node/`, `bootstrap-control-node.sh`, the toolkit aliases). For those, commander IS the validation target; ai doesn't help.
* Bad, because running a control-node-specific change against ai first would either fail (wrong target) or apply changes to ai that don't belong there.
* Neutral, because for managed-host changes, the effective order is commander (skipped — doesn't apply) → ai → pve2 → pve1.

### pve1 and pve2 in parallel after ai

* Bad, because hypervisor changes are higher-stakes than ai changes (more services depend on hypervisors). Sequential validation gives a larger recovery window.
* Bad, because marginal speedup (one playbook run saved) doesn't justify increased blast radius.
* Neutral, because after both pve1 and pve2 have been individually validated, future changes via `site.yml` run them in parallel. The sequential order is only for the per-change validation phase.

## More Information

### Trade-offs explicitly accepted

* **Iteration speed for blast-radius control.** Validating four hosts in series is slower than parallel application. Accepted because bootstrap-phase mistakes are severe (lockout, manual recovery). Once playbooks are well-validated and going via `site.yml`, parallel application is fine.
* **Convention-not-enforcement.** Nothing prevents operators from skipping the order. Documented, repeated in CONTEXT.md and CLAUDE.md, called out in this ADR — but it's discipline, not a technical constraint. Acceptable because the operator population is small (Andrew), and the cost of breaking the order is borne by the breaker.
* **Specific host names baked in.** The order references commander, ai, pve1, pve2 by name. If the host inventory changes (e.g., a new managed host is added), the order needs updating — either appending at the end or re-deriving based on similar reasoning. Acceptable because host inventory changes are rare and worth a deliberate ADR amendment.

### When this is the wrong choice

* **Hosts are short-lived and provisioned/deprovisioned frequently.** If the platform moves to a pattern where hosts are ephemeral (e.g., Talos cluster nodes that get reprovisioned regularly), the per-host validation order becomes meaningless. The bootstrap path then targets node templates rather than individual long-lived hosts.
* **A new managed host is added that has different stakes.** If, say, a database host with high-availability requirements joins the inventory, it should probably go *last* (after the lower-stakes hosts have validated the change). The order becomes more granular than the current four-host list.
* **A change is so invasive that no individual-host validation makes sense.** Some platform-wide changes (e.g., switching from one user model to another) need coordinated cutover; the validation order may not be the right pattern.
* **An incident forces re-bootstrapping multiple hosts simultaneously.** Recovery scenarios may need to skip the validation order in favor of restoring service quickly. Accepted: incident recovery is its own playbook (literal or metaphorical) and may not follow normal validation patterns.

### Cross-references

* `playbooks/bootstrap.yml` — the playbook this validation order primarily applies to (when written)
* `playbooks/site.yml` — the eventual all-hosts playbook; runs in parallel after individual hosts are bootstrapped (when written)
* `decisions/0001-automation-user-bob.md` — sibling: the andrew→bob model that bootstrap.yml implements
* `decisions/0003-bootstrap-control-node-scope.md` — sibling: why the bootstrap script is narrow (validates against commander first)
* `kb/projects/scaffoldrack/CLAUDE.md` §3 — Scope 2 statement of host inventory at the org level
