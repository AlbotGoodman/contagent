# feat-hardening.md — Contagent hardening tracker

Living document. Updated as recon findings, mitigations, and decisions evolve.
Last updated: 2026-10-16 (session: host-information-leak audit).

## 1. Purpose & scope

Tracks everything learned about what the containerised agent can observe about the
host, what is already defended, and what mitigations are planned or rejected.
Companion to the "Host information disclosure" subsection in `README.md`.

## 2. Verified recon inventory

All probes run live inside the `opencode` container (opencode 1.19.0 image,
kernel 7.0.0-38-generic host, Ryzen 5 5600X / 12 threads / ~32 GB RAM host).

| Probe | Observed | Classification |
| --- | --- | --- |
| `nproc` | 12 (compose limits opencode to 8 CPUs; affinity mask is 0-11) | **LEAK** — host thread count |
| `/proc/meminfo` MemTotal | 32,806,660 kB (~31.3 GiB; container limit is 4G) | **LEAK** — host RAM |
| `/proc/meminfo` SwapTotal | 2,097,148 kB | **LEAK** — host swap |
| `/proc/cpuinfo` | 12 processors, `model name: AMD Ryzen 5 5600X 6-Core Processor` | **LEAK** — host CPU model |
| `/proc/loadavg` | host load (e.g. `0.28 0.26 0.26`) | **LEAK** — host load |
| `/proc/uptime` | ~9000 s (host uptime, not container) | **LEAK** — host uptime |
| `/proc/modules` | 146 host kernel modules (wireguard, nf_conntrack, veth, …) | **LEAK** — host software fingerprint |
| `/proc/partitions` / `/proc/diskstats` | `nvme1n1`, 2,000,398,680 blocks; loop devices | **LEAK** — host disks |
| `/sys/class/dmi/id/` | `product_name: B550I AORUS PRO AX`, `sys_vendor: Gigabyte`, BIOS version/date | **LEAK** — motherboard fingerprint |
| `/sys/devices/system/cpu/vulnerabilities/*` | full spectre/meltdown/etc. mitigation status | **LEAK** — CPU generation |
| `/proc/crypto` | host crypto drivers (aes-avx2 → CPU features) | **LEAK** — CPU features |
| `/proc/version` | full kernel build string incl. Ubuntu 24.04 toolchain | **LEAK** — kernel build |
| `/proc/cmdline` | `BOOT_IMAGE=/boot/vmlinuz-7.0.0-38-generic root=UUID=…` | **LEAK** — boot args + root UUID |
| `/proc/self/mountinfo` | `/var/lib/containerd/.../snapshots/NNNN/fs` upperdir paths | **LEAK** — host paths + image layers |
| `df -h /` | overlay 1.9T, 85% used | **LEAK** — host disk size/usage |
| `/proc/net/arp` | `172.18.0.1` (host bridge) + peer MACs | topology info (low severity) |
| `/sys/fs/cgroup/memory.max` | 4294967296 (matches compose 4G) | **ok** — container-scoped |
| `/sys/fs/cgroup/cpu.max` | `800000 100000` (matches compose 8 CPUs) | **ok** — container-scoped |
| `/proc/kcore`, `timer_list`, `keys`, `latency_stats`, `sched_debug` | empty (masked to /dev/null by Docker) | **ok** — masked |
| `/sys`, `/proc/sys` | mounted read-only | **ok** |
| Capabilities (`CapEff`) | `0000000000000000` (all dropped) | **ok** |
| `/dev` | no GPU devices, no /dev/kvm, no docker socket | **ok** |
| `uname -r` | `7.0.0-38-generic` (host kernel) | accepted residual (not hideable in runc) |

## 3. Already-hardened surface (do not re-litigate)

From `docker-compose.yml`: non-root user, `read_only` rootfs + tmpfs,
`cap_drop: ALL`, `no-new-privileges`, resource limits, Ollama bound to
loopback only, no docker socket, GPU devices only in the ollama service.

## 4. Mitigation tiers

| Tier | Mitigation | Status | Notes |
| --- | --- | --- | --- |
| 1 | `cpuset: "0-7"` (opencode) / `"0-1"` (ollama) | **backlog** | Verified mechanism: restricting affinity to 0-7 makes `nproc` report 8. Does **not** hide `/proc/cpuinfo` (still lists 12 + model name). |
| 1 | `pids_limit` on both services | **backlog** | DoS protection (fork bombs); no info-leak value. Already on the TODO list. |
| 2 | Sanitized bind-mounts over `/proc/meminfo`, `/proc/cpuinfo`, DMI id files | **backlog** | Static files under e.g. `config/hardening/`. Requires a throwaway-container test first (runc may block mounts onto `/proc`). Must be regenerated if compose limits change. |
| 3 | gVisor (`runtime: runsc`) on the **opencode** service | **in evaluation** | See section 5. Wiring via `docker-compose.gvisor.yml` override; manual host install documented. |
| 3 | Kata Containers | **rejected** | See section 5. VM-per-container overhead and I/O cost are wrong for a coding agent; no practical GPU path for ollama. |
| 4 | This document + README threat model + `make audit` | **done** | `make audit` runs the recon set inside the container and flags LEAK/ok per probe. |

Known residuals that **no** tier can hide under plain runc: `uname`/kernel version,
`/proc/cmdline`, mountinfo host paths, host disk size via `df`. gVisor hides these
too (sandbox kernel reports itself).

## 5. Deep dive: gVisor vs Kata Containers

| Argument | gVisor (`runsc`) | Kata Containers |
| --- | --- | --- |
| Mechanism | User-space kernel (Go "Sentry") intercepts all app syscalls; strict seccomp allowlist (~60 syscalls) on the host side | Lightweight VM per container (QEMU / Cloud Hypervisor / Firecracker / Dragonball) with its own guest kernel via KVM |
| Boundary strength | Syscall-level; host kernel still involved for a vetted set. "Seccomp on steroids" | Hardware virtualization; strongest boundary, host kernel CVEs irrelevant |
| Effect on our leaks | `/proc` and `/sys` synthesized by gVisor: meminfo sandbox-scoped, cpuinfo synthesized, `uname` reports gVisor, no `/proc/modules`, no DMI, no host cmdline, mountinfo shows gofer mounts | Guest kernel reports its own uname/modules/meminfo/DMI |
| Startup / RAM overhead | ~200–300 ms, +10–50 MB/container | ~0.6–1.9 s, +130–340 MB/container |
| Runtime performance | 10–30% slower on syscall-heavy workloads; filesystem I/O mostly native | ~5–15% overhead; 4K random I/O can collapse (~99% in published measurements) via virtio-fs — hurts `pip`/`npm`/compiles |
| App compatibility | Partial (unimplemented syscalls fail); bun/node/opencode generally OK — must be tested | Full Linux kernel; complete |
| GPU (RTX 4090) | Supported via `nvproxy` (allowlisted NVIDIA ioctl passthrough); RTX 4090 (Ada) documented as "will likely work"; host driver version must match runsc's supported-ABI list; enable with `runsc --nvproxy` + nvidia runtime/CDI | VFIO passthrough only, QEMU only, needs IOMMU isolation; single-GPU desktop would lose the GPU — impractical here |
| Docker Compose | `runtime: runsc` per service | `runtime: kata` per service |
| Install location | **Host only**: gvisor apt repo → `sudo runsc install` → `/etc/docker/daemon.json` → restart dockerd | **Host only**: kata-manager/package + daemon.json; needs `/dev/kvm` |
| Installable inside the project? | No — an OCI runtime must be registered with the host dockerd. Nesting dockerd-in-docker to obtain it would sacrifice the isolation being bought | No — same, plus host KVM |

**Decision (logged):** run gVisor on the **opencode service only**. That is where
arbitrary model-generated commands execute, and it needs no GPU. The ollama
service stays on runc: it needs the GPU, benefits from native I/O, and never
executes agent code. Industry direction agrees — e.g. METR's 2026 evaluation
concluded "gVisor first; revisit Kata only when gVisor hits a demonstrated
compatibility wall."

**Revisit triggers:** a demonstrated gVisor escape; an opencode/bun syscall
incompatibility that cannot be worked around; a future need for mutually
untrusted tenants (then reconsider Kata).

### Moving forward with gVisor (manual host steps)

Runsc must live on the host. One-time, manual (deliberately not automated in the
Makefile yet — see decision log):

```bash
# 1. Add the gVisor apt repository and install (Debian/Ubuntu)
#    Follow the current instructions at https://gvisor.dev/docs/user_guide/install/
#    (keyring + repo + apt install runsc)

# 2. Register the runtime with dockerd
sudo runsc install
sudo systemctl restart docker

# 3. Smoke test
docker run --runtime=runsc --rm hello-world

# 4. Optional GPU check (only needed if later testing ollama under gVisor)
runsc nvproxy list-supported-drivers
```

Then enable it for contagent via the override file (base compose stays portable):

```bash
docker compose -f docker-compose.yml -f docker-compose.gvisor.yml up -d
make audit          # expect the leak table to collapse to sandbox values
make contagent      # functional smoke test: TUI, bash tool, plugin installs
```

**If a Makefile target is wanted later**, the shape is:

```make
install-gvisor:                            # One-time host install (sudo, mutates host)
	@command -v runsc >/dev/null 2>&1 || { \
		echo "runsc not found. See feat-hardening.md for manual install steps."; exit 1; }
	@sudo runsc install && sudo systemctl restart docker && \
	 docker run --runtime=runsc --rm hello-world
```

…preferrably guarded by a check so it never runs unattended, plus a matching
`downgrade` note (remove the runtime entry from `/etc/docker/daemon.json`).

## 6. Decision log

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-10-16 | Information leaks documented rather than fully mitigated in base compose | Base stack must stay portable; mitigations layer on top |
| 2026-10-16 | gVisor chosen for opencode; ollama stays on runc | No GPU needed in the agent container; strongest practical isolation per effort |
| 2026-10-16 | Kata rejected | VM overhead + virtio-fs I/O penalty wrong for a coding agent; no practical GPU path |
| 2026-10-16 | gVisor host install kept manual (docs only) | Host mutation should be a deliberate human action; Makefile target shape documented for later |
| 2026-10-16 | Override file (`docker-compose.gvisor.yml`) instead of inline `runtime: runsc` | Base `docker compose up` keeps working on hosts without runsc |

## 7. Appendix — audit commands

Run via `make audit` (inside the opencode container), or manually with
`docker compose exec opencode bash /workspace/scripts/audit-recon.sh`:

```bash
nproc
grep -m1 'model name' /proc/cpuinfo
grep -E 'MemTotal|SwapTotal' /proc/meminfo
cat /proc/loadavg; cat /proc/uptime
wc -l /proc/modules
head -3 /proc/partitions
cat /sys/class/dmi/id/product_name 2>/dev/null
uname -r; cat /proc/cmdline
grep -c containerd /proc/self/mountinfo
df -h / | tail -1
cat /sys/fs/cgroup/memory.max; cat /sys/fs/cgroup/cpu.max
```

## 8. Out of scope / future ideas

- lxcfs (FUSE-based cgroup-aware /proc virtualization) — only worth revisiting if
  gVisor fails compatibility testing.
- Custom AppArmor profile denying reads of specific /proc files — fragile; tools
  may need them at startup.
- seccomp customization — default Docker profile already active; blocking `uname`
  would break bun/node.
- User namespace remap — does not address any leak in section 2.
