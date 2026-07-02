# Proxmox Admin Tools Inventory Design

## Goal

Compare what the former root account can use with what the new admin account can use on the Proxmox host, focused on apt-installed packages and Proxmox/LXC/VM management tools. The output should help choose selective follow-up actions without installing packages or changing permissions during the inventory pass.

## Scope

The inventory covers:

- Apt packages installed on the host that relate to Proxmox, LXC, QEMU/KVM, VM/container backup, storage, clustering, networking, and management.
- Command-line tools commonly used to manage Proxmox nodes, LXC containers, and virtual machines, including tools such as `pct`, `qm`, `pvesh`, `pveum`, `pvecm`, `vzdump`, `pvesm`, `ha-manager`, `lxc-*`, `qemu-*`, and `virsh` if present.
- Root and admin account differences in `PATH`, group membership, sudo access, binary visibility, and executable permissions.

The inventory does not install packages, edit sudoers, alter group membership, change Proxmox permissions, or modify running containers or VMs.

## Approach

Use a read-only diagnostic script or command sequence that gathers the same facts from the admin account and, when available, from root through `sudo`. The comparison should distinguish between four cases:

1. The tool is installed and visible to both accounts.
2. The tool is installed but only root sees it, usually because `/usr/sbin` or `/sbin` is missing from the admin account `PATH`.
3. The tool is installed and visible but requires elevated privileges or Proxmox role configuration.
4. The tool is missing and may require an apt package, repository, or Proxmox component decision.

The report should avoid treating apt packages as per-user state. Apt installation is system-wide; account differences usually come from environment, permissions, or Proxmox authorization.

## Data Collection

Collect admin context:

- `whoami`, `id`, groups, shell, home directory, and `PATH`.
- `command -v` results for the target Proxmox/LXC/VM command list.
- Directory checks for `/usr/sbin`, `/sbin`, `/usr/bin`, and `/bin`.
- Optional sudo capability check that does not prompt indefinitely.

Collect root context when sudo is available:

- Root `PATH`.
- `command -v` results for the same target command list.
- Package ownership for discovered binaries using `dpkg -S`.
- Package metadata using `apt-cache show` or `dpkg-query` for installed relevant packages.

Collect package inventory:

- Installed packages matching relevant patterns such as `proxmox`, `pve`, `pve-*`, `lxc`, `qemu`, `libvirt`, `bridge`, `ifupdown`, `openvswitch`, `ceph`, `zfs`, `vzdump`, and related storage or backup tools.
- For each relevant package, include package name, version, short description, and installed status.

## Report Format

Produce a human-readable table grouped by action type:

- Already usable by admin.
- Installed but hidden from admin `PATH`.
- Installed but needs privilege or Proxmox permission.
- Missing package candidate.
- Present but not recommended for direct admin use.

Each row should include:

- Tool or package name.
- Description.
- Root availability.
- Admin availability.
- Owning package, when known.
- Suggested next action.

The final section should be a selectable checklist of possible follow-up actions, such as adding `/usr/sbin` to the admin shell environment, using `sudo pct`, adding a narrow sudoers rule, assigning Proxmox permissions with `pveum`, or installing a specific missing package.

## Error Handling

If root access is unavailable, the report should still include admin-visible tools and installed apt packages that do not require root to query. It should mark root comparison as unavailable rather than failing the whole run.

If an apt cache command is unavailable or a package has no description, the report should show the package name and mark the missing metadata explicitly.

If Proxmox commands are absent, the report should verify whether the host appears to be a Proxmox node before suggesting package installation.

## Verification

The inventory is verified by checking that:

- The report separates install state from account visibility.
- Every recommended install or permission action is backed by an observed missing command, missing package, PATH difference, or permission issue.
- No command in the inventory pass changes packages, users, groups, Proxmox resources, containers, VMs, or storage.
