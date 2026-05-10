# ADR-004 — Validation Order: commander → ai → pve2 → pve1 → parity

**Status:** Accepted
**Date:** 2026-05-09 (decision made), 2026-05-10 (formalized as ADR)
**Decision-makers:** Andrew Krull, with chat-Claude as collaborator

## Context

The bootstrap repo eventually applies changes to all four scaffoldrack hosts: commander, ai, pve1, pve2. Each change needs to be validated before being applied broadly, because mistakes during bootstrap (especially around SSH and sudo) can lock the operator out of a host.

Without a defined validation order, the natural temptation is to apply changes everywhere at once and hope. That approach is fine when the changes are well-tested, but bootstrap itself is the testing; nothing is well-tested until it's been validated against a real host.

The order in which hosts get exposed to changes determines the recovery surface when something goes wrong. The order matters.

## Decision

The validation order for any change to a role, playbook, or script is:

1. **commander** — first. For control-node-specific things (`bootstrap-control-node.sh`, `control-node.yml`, anything that touches the toolkit aliases). commander is the easiest to recover because Andrew has direct access (it's on his desk), and because commander is the control node — if commander is broken, NO automation runs anywhere, which is recoverable but limiting. Validating against commander first means catching control-node-specific bugs before they affect anything else.

2. **ai** — second. For managed-host changes (anything that runs against a remote host via SSH-as-bob). ai is a real host but not a hypervisor; it's running the AI stack (Ollama, Open WebUI). Mistakes on ai are recoverable: at worst we have to manually re-bootstrap ai. The applications running on ai (Ollama, Open WebUI) can tolerate brief downtime.

3. **pve2** — third. The first hypervisor to be touched. Validates that bootstrap.yml (and downstream playbooks) work on Debian 13 Trixie (which pve2 is). pve2 was chosen as "first hypervisor" for the simple reason that pve1's name suggests primacy — operators have a tendency to call the lower-numbered host "the production one." pve2 going first means pve1 is undisturbed while pve2 is being figured out.

4. **pve1** — fourth. The second hypervisor, validated against the now-proven bootstrap pattern. By this point, bootstrap.yml has been applied to ai, then pve2; there's high confidence the playbook works.

5. **parity** — finally. After all four hosts have been individually bootstrapped and validated, future changes (via `site.yml`, `roles/hardening/`, etc.) get applied uniformly to all four. The order at this stage matters less; the per-host validation has already happened.

This order is a discipline, not a hard technical constraint. A change that's purely cosmetic (e.g., a typo fix in a comment) doesn't need to crawl through the order. But anything that affects the host's actual state (a new role, a new playbook, a non-trivial change to an existing playbook) gets the full validation treatment.

The order applies to bootstrap operations specifically. Once a host is bootstrapped, regular `site.yml` runs typically apply to all hosts at once — but `site.yml` is composed of well-validated roles, so the per-host risk is much lower at that point.

## Consequences

**Positive:**
- Clear blast-radius progression. Each step has a known-recoverable target before the next step's stakes go up.
- commander first means a control-node-specific bug doesn't spread to managed hosts before being caught.
- ai second is a low-stakes managed-host validation; if something is wrong with bootstrap.yml, ai can be re-imaged without serious cost.
- pve2 before pve1 means the more critical hypervisor (pve1, by operator naming convention if nothing else) stays untouched until the playbook is validated against pve2.
- Easy to remember. Four hosts, fixed order, no decision required at runtime.

**Negative:**
- **Slower iteration.** Validating against four hosts in series is slower than running against all four at once. We accept this because the cost of an undetected bug propagating to all four is much higher than the cost of slower iteration.
- **Discipline-not-enforcement.** Nothing technically prevents an operator from skipping the order (e.g., running `site.yml` against pve1 first because they're feeling adventurous). The order is a convention, documented but not enforced.

**Neutral:**
- The order assumes the operator is sequencing changes one at a time. If multiple unrelated changes are queued, each one gets the validation order independently.

## Alternatives Considered

### Alternative 1: All four hosts in parallel

Run every playbook against all four hosts at once.

**Why not chosen:**
- Bugs that affect SSH or sudo can lock out all four hosts simultaneously. Recovery from "all four hosts unreachable" is much worse than recovery from "ai unreachable, others fine."
- No meaningful blast-radius control. The first run is the production run.
- Acceptable for very-well-tested changes; not acceptable for bootstrap-level changes that haven't been validated yet.

This *is* the eventual model for `site.yml` runs against well-tested roles. It's not the model for the bootstrap path.

### Alternative 2: pve1 first

The lower-numbered hypervisor is the obvious "first" to touch.

**Why not chosen:**
- Operators (including Andrew) have a tendency to think of pve1 as "the primary" or "production" hypervisor. That mental model makes pve1 the worst place to test changes.
- pve2 going first means pve1 stays in a known-working state while pve2 is being validated. If something goes wrong on pve2, pve1 is unaffected; recovery is straightforward.
- After pve2 is proven, applying to pve1 is low-risk because the playbook is already known to work on Trixie hypervisors.

### Alternative 3: A throwaway VM as the first validation target

Create a dedicated VM for bootstrap validation, separate from the four real hosts.

**Why not chosen:**
- Adds a host to manage. The four real hosts ARE the validation surface; adding a fifth fictional one is overhead.
- The throwaway VM may not match the real hosts' configurations (different OS version, different package versions, different network topology). False confidence is worse than no confidence.
- For specific validations (like end-to-end `bootstrap-control-node.sh` testing), a fresh VM is genuinely useful — but as a backlog item, not as the primary validation pattern.

We may add throwaway-VM validation to the workflow later, especially for end-to-end script testing. But the per-change validation order against real hosts is the primary pattern.

### Alternative 4: ai first, commander second

Argue that ai is the lowest-stakes host and should always be first.

**Why not chosen:**
- Many changes are control-node-specific (anything that touches `roles/control_node/`, `bootstrap-control-node.sh`, the toolkit aliases). For those, commander IS the validation target; ai doesn't help.
- Running a control-node-specific change against ai first would either fail (wrong target) or apply changes to ai that don't belong there.
- For managed-host changes, the order is commander (control node, doesn't apply to it) → ai (first managed host) → pve2 → pve1. The "commander first" position for control-node-specific changes is necessary; for managed-host changes, commander is implicitly skipped because the change doesn't apply.

### Alternative 5: pve1 and pve2 in parallel after ai

Speed up by validating both hypervisors at once after ai succeeds.

**Why not chosen:**
- Hypervisor changes are higher-stakes than ai changes (more services depend on hypervisors). Sequential validation gives a larger recovery window.
- Marginal speedup (one playbook run saved) doesn't justify the increased blast radius.
- After both pve1 and pve2 have been individually validated, future changes via `site.yml` run them in parallel. The sequential order is only for the per-change validation phase.

## Trade-offs Accepted

**Iteration speed for blast-radius control.** Validating four hosts in series is slower than parallel application. We accept this because bootstrap-phase mistakes are severe (lockout, manual recovery). Once playbooks are well-validated and going via `site.yml`, parallel application is fine and that's what `site.yml` does.

**Convention-not-enforcement.** Nothing prevents operators from skipping the order. The order is documented, repeated in CONTEXT.md and CLAUDE.md, and called out in this ADR — but it's discipline, not a technical constraint. Acceptable because: the operator population is small (Andrew), and the cost of breaking the order is borne by the breaker.

**Specific host names baked in.** The order references commander, ai, pve1, pve2 by name. If the host inventory changes (e.g., a new managed host is added), the order needs to be updated — either by appending the new host at the end, or by re-deriving the order based on similar reasoning. Acceptable because host inventory changes are rare and worth a deliberate ADR amendment.

## When This Is the Wrong Choice

This decision could be wrong in scenarios where:

- **Hosts are short-lived and provisioned/deprovisioned frequently.** If the platform moves to a pattern where hosts are ephemeral (e.g., Talos cluster nodes that get reprovisioned regularly), the per-host validation order becomes meaningless. The bootstrap path then targets node templates rather than individual long-lived hosts.
- **A new managed host is added that has different stakes.** If, say, a database host with high availability requirements joins the inventory, it should probably go *last* (after the lower-stakes hosts have validated the change). The order becomes more granular than the current four-host list.
- **A change is so invasive that no individual-host validation makes sense.** Some platform-wide changes (e.g., switching from one user model to another) need coordinated cutover; the validation order may not be the right pattern.
- **An incident forces re-bootstrapping multiple hosts simultaneously.** Recovery scenarios may need to skip the validation order in favor of restoring service quickly. We accept that incident recovery is its own playbook (literal or metaphorical) and may not follow normal validation patterns.

## Cross-references

- `playbooks/bootstrap.yml` — the playbook this validation order primarily applies to (when written)
- `playbooks/site.yml` — the eventual all-hosts playbook; runs in parallel after individual hosts are bootstrapped (when written)
- `decisions/001-automation-user-bob.md` — sibling: the andrew→bob model that bootstrap.yml implements
- `decisions/003-bootstrap-control-node-scope.md` — sibling: why the bootstrap script is narrow (validates against commander first)
- `kb/projects/scaffoldrack/CLAUDE.md` §3 — Scope 2 statement of host inventory at the org level
