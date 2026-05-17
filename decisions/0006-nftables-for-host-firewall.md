---
status: accepted
date: 2026-05-17
decision-makers: Andrew Krull (with chat-Claude as collaborator)
---

# Use nftables (not UFW) for Host Firewall on Debian Hosts

## Context and Problem Statement

The `roles/hardening/` role (Phase 5) will configure a host firewall on every managed scaffoldrack host: commander, ai, pve1, pve2. The choice of firewall tool affects the role's templates, its task structure, and how it interacts with other systems that program the kernel firewall — specifically Docker (on `ai`) and the Proxmox host firewall (on pve1/pve2). Eventually it also intersects with Kubernetes via `kube-proxy` on Talos VMs, though Talos manages its own firewall and is out of scope for Ansible.

The two realistic options on Debian are **UFW** and **nftables**. Both program the same kernel netfilter machinery; they're userspace tools, not separate firewall implementations. The question is which userspace tool the `hardening` role drives.

The default answer for a homelab is usually UFW — it has friendly syntax, gentle defaults, and is well-documented. But Docker on `ai` is a known footgun for UFW: Docker programs its own iptables rules in the `DOCKER` chain when it starts, and **container-published ports bypass UFW's `INPUT` rules entirely**. Mitigation patterns exist (`ufw-docker`, the `DOCKER-USER` chain) but they add a moving part to the firewall story.

The broader trajectory also matters. Talos Linux on the future k8s nodes does not use UFW; it has its own machine-config firewall model. Familiarity with nftables-style ruleset thinking carries over more cleanly than UFW's `allow from X to any port Y` profile thinking.

## Decision Drivers

* One firewall syntax across all Debian-managed hosts (commander, ai, pve1, pve2)
* Clean integration with Docker's own iptables rule generation, not a parallel/conflicting one
* Alignment with Debian's own direction — `iptables` on Debian 12+ is `iptables-nft` under the hood; nftables is the modern netfilter wrapper
* Conceptual continuity with Talos's firewall model when Talos VMs come online
* Ruleset-as-code legibility — the firewall should be readable as a single file, not reconstructed from a sequence of CLI invocations
* 3am rule — the firewall configuration must be debuggable on a tired night

## Considered Options

* nftables, managed as a single Jinja-templated `/etc/nftables.conf` per host
* UFW with `ufw-docker` script or `DOCKER-USER` chain pattern on `ai`
* UFW everywhere, accept the Docker footgun as documented behavior
* `firewalld` (Red Hat's tool, available on Debian)
* No host firewall — rely on perimeter (UDM Pro) only
* Per-host strategy: UFW on commander, nftables on `ai`, PVE's built-in firewall on hypervisors

## Decision Outcome

Chosen option: **"nftables, managed as a single Jinja-templated `/etc/nftables.conf` per host"**, because it produces one firewall syntax across the fleet, integrates cleanly with Docker via a `DOCKER-USER` chain section inside the same ruleset, aligns with Debian's modern netfilter direction, and gives `roles/hardening/` a single template to maintain rather than two.

Specifically:

* `roles/hardening/tasks/nftables.yml` installs `nftables`, drops a templated `/etc/nftables.conf`, enables and starts the `nftables.service`, and validates the ruleset (`nft -c -f /etc/nftables.conf`) before activation.
* The template uses a base ruleset with a `DOCKER-USER` chain stanza so that on `ai`, Docker's auto-generated rules append into the structured ruleset rather than running parallel to it.
* Per-host variables drive what's allowed in (SSH from management subnet, PVE web UI 8006 on hypervisors, Proxmox cluster ports between hypervisors, etc.). The variables live in `inventory/group_vars/<group>/main.yml` and `inventory/host_vars/<host>.yml` when those files exist (Phase 2+).
* The role is tagged `nftables` and `hardening` so `--tags nftables` is a valid targeted re-run.
* PVE's own built-in datacenter/host firewall is a **separate concern** — it operates at the guest/cluster layer and doesn't conflict with the host-level nftables ruleset. If we adopt PVE firewall later, it lives in `roles/proxmox/`, not `roles/hardening/`.

### Consequences

* Good, because one firewall mental model across every Debian host. `roles/hardening/` has one template.
* Good, because Docker's `DOCKER-USER` chain pattern is a first-class part of nftables; the integration is documented and stable.
* Good, because nftables is the modern netfilter direction on Debian. Investment compounds; UFW would be a comfort choice with a shorter shelf life.
* Good, because reading `/etc/nftables.conf` shows the entire ruleset in one file — better for 3am debugging than tracing a chain of `ufw` profile invocations.
* Good, because conceptual adjacency to Talos's firewall model. When Talos VMs land, the mental jump is smaller.
* Bad, because nftables syntax has a learning curve. Anyone coming from iptables/UFW pays a one-time cost to read the templates.
* Bad, because UFW's `ufw status` is a friendlier "what is on this host doing?" output than `nft list ruleset`. Operational ergonomics are slightly worse on day one.
* Bad, because the Ansible community has more UFW role examples than nftables role examples. We write a bit more from scratch.
* Neutral, because both tools program the same kernel structures. The choice is about authoring ergonomics and integration story, not about underlying capability.

### Confirmation

When `roles/hardening/` is built, the implementation confirms this ADR if:

* `roles/hardening/tasks/nftables.yml` exists and uses `ansible.builtin.template` to render `/etc/nftables.conf` from a Jinja template.
* `roles/hardening/templates/nftables.conf.j2` includes a `DOCKER-USER` chain section.
* The role validates the ruleset with `nft -c -f /etc/nftables.conf` before activating it.
* No `community.general.ufw` tasks appear anywhere in `roles/hardening/`.
* On `ai`, after the role runs, `docker run --rm -p 18080:80 nginx` produces a container whose port is reachable only from networks the nftables ruleset allows.

## Pros and Cons of the Options

### nftables, managed as a single Jinja-templated `/etc/nftables.conf`

* Good, because one syntax across all hosts (no per-host tooling difference).
* Good, because Docker integration via `DOCKER-USER` chain is clean and documented.
* Good, because the modern netfilter direction on Debian; investment compounds.
* Good, because ruleset-as-code is grep-able and reviewable in one file.
* Good, because conceptually close to Talos's machine-config firewall, easing future cognitive load.
* Bad, because syntax learning curve compared to UFW.
* Bad, because operational ergonomics on day one are slightly worse (`nft list ruleset` vs `ufw status`).

### UFW with `ufw-docker` script or `DOCKER-USER` chain pattern on `ai`

* Good, because UFW is widely known and well-documented in the Ansible ecosystem.
* Good, because day-one ergonomics (`ufw status numbered`) are excellent.
* Bad, because we end up with two firewall stories: UFW on commander/pve1/pve2, UFW+`ufw-docker` on `ai`. The role's complexity grows.
* Bad, because UFW is a wrapper over the same nftables/iptables underneath — we'd be reading UFW's translation layer instead of the actual ruleset.
* Bad, because `ufw-docker` is a community script with its own maintenance trajectory; depending on it adds a moving part.

### UFW everywhere, accept the Docker footgun as documented behavior

* Good, because absolute simplicity.
* Bad, because Docker container ports are *silently* unfiltered by UFW on `ai`. "Silently" is the dangerous word — a casual reading of `ufw status` would suggest the host is locked down when it isn't.
* Bad, because the failure mode contradicts the 3am rule (the misalignment between what the operator thinks the firewall is doing and what it's actually doing is exactly the kind of trap a tired operator falls into).

### `firewalld`

* Good, because integrates with NetworkManager and zone-based models common on Red Hat systems.
* Bad, because Debian doesn't standardize on firewalld; the wider Debian ecosystem assumes UFW or direct nftables. We'd be off the beaten path.
* Bad, because not aligned with anything else in the stack — no zonal model is needed for our shape of hosts.

### No host firewall — rely on perimeter only

* Good, because zero local complexity.
* Bad, because perimeter-only is wrong for a homelab where managed hosts also serve cluster-internal traffic. Lateral movement protection is real.
* Bad, because the moment any one host gets a public-facing service (eventually: Mailu, Caddy ingress), perimeter-only stops being adequate.

### Per-host strategy: UFW on commander, nftables on `ai`, PVE's built-in on hypervisors

* Good, because each host uses the tool best fit for its specific situation.
* Bad, because three different mental models for the same concern in `roles/hardening/`.
* Bad, because the role's complexity multiplies: three templates, three task files, three sets of variables.
* Bad, because operationally, when something goes wrong, the first question is "which firewall on this host?" rather than "what does the firewall ruleset say?"

## More Information

### Status of this ADR relative to actual work

This ADR is written **before `roles/hardening/` exists**. It is forward-looking — capturing the Phase 5 firewall direction while the reasoning is fresh, so that when the hardening role is implemented, the choice is already made and doesn't have to be re-derived from scratch.

The ADR is `accepted` rather than `proposed` because the reasoning held up under examination in the originating session, but the future reader should scrutinize it harder than a post-implementation ADR. If implementation surfaces something that contradicts the reasoning here, supersede this ADR with a new one rather than editing it.

### Trade-offs explicitly accepted

* **The nftables learning curve.** Operators coming from iptables/UFW pay a one-time cognitive cost to read and modify the templates. Accepted because the cost is one-time and the consistency benefit is permanent.
* **Slightly worse day-one ergonomics for `nft list ruleset` vs `ufw status`.** Accepted because the readability win of a single ruleset file outweighs the friendliness of UFW's status output. Wrapper scripts or aliases can close the ergonomics gap if it becomes a real pain.
* **Less off-the-shelf Ansible role content.** The hardening role's nftables tasks will be written largely from scratch rather than borrowed. Accepted because the role is one of the most security-relevant pieces of the platform and we want to read every line anyway.

### When this is the wrong choice

* **If a future operator strongly prefers UFW** and the firewall ruleset complexity stays low. The decision optimizes for one syntax across hosts and clean Docker integration; if those drivers weaken (e.g., Docker disappears from `ai`, hosts shrink to a single homogeneous group), UFW becomes a reasonable reconsideration.
* **If the platform standardizes on a different firewall management tool** (e.g., adopting Cilium network policies as the primary firewall once k8s is real, and the host firewall shrinks to "only allow SSH"). At that point, the host-level firewall is trivial and the tool choice matters less.
* **If a compliance regime mandates a specific tool.** FedRAMP and similar don't currently mandate a firewall tool, but if a future requirement names UFW or firewalld explicitly, this ADR retires.

### Docker exposure model is a separate decision

This ADR governs **the host firewall on Debian hosts**. It does not decide how Docker containers on `ai` are exposed to the network. The current practice (containers binding to specific host ports, no reverse proxy yet) is intentionally out of scope here. A future ADR — likely "Docker exposure model on `ai`" — will address whether containers bind to `0.0.0.0` with `DOCKER-USER` filtering, or to `127.0.0.1` only with a reverse proxy in front. That ADR is downstream of this one.

### Cross-references

* `roles/hardening/tasks/nftables.yml` — to be written in Phase 5
* `roles/hardening/templates/nftables.conf.j2` — to be written in Phase 5
* `decisions/0007-debops-as-reference-only.md` — sibling ADR from the same session, governing how `roles/hardening/` is sourced
* `kb/projects/scaffoldrack/decisions/010-os-standardization-debian-trixie.md` — the OS standardization that makes a single firewall tool across hosts feasible
* Debian's nftables documentation: https://wiki.debian.org/nftables
* `DOCKER-USER` chain reference: https://docs.docker.com/network/packet-filtering-firewalls/
