# cloud-init-ansiblepull

Bootstrap a fresh VPS using cloud-init plus Ansible in pull mode, or preconfigure an
already-installed Linux machine (for example a new laptop) the same way minus cloud-init.

There is no persistent agent, no push-mode Ansible, no separate bootstrap script. For a VPS,
cloud-init installs Ansible on the target machine using the distribution's own package manager
(via the standard `packages:` cloud-config key), then runs `ansible-pull` against this repository
once (via `runcmd:`), which applies `ansible/playbook.yml` and exits. This deliberately avoids
cloud-init's dedicated `ansible` module - some cloud images (a real AWS Amazon Linux image,
specifically) ship a customized module list that leaves it out entirely, in which case it would
silently do nothing. `packages:` and `runcmd:` are much older, more universal cloud-init
primitives, far less likely to be missing from any provider's image. For an already-installed
machine, `scripts/manual.sh` skips cloud-init entirely and just runs `ansible-pull` directly - see
below.

Ansible ends up being whatever version the target distribution packages (not necessarily the
latest release), so this project sticks to simple, portable Ansible features rather than relying
on the newest ones.

## Requirements

- Target machine: currently implemented and tested against Ubuntu 26.04 LTS. The project intends
  to support a broader minimal set - recent Ubuntu, Debian, RHEL-family, Amazon Linux, Alpine -
  but only Ubuntu 26.04 is built and verified so far.
- For a VPS: a provider that lets you supply cloud-init user-data at creation time.
- For an already-installed machine: root access and a way to run a few commands once by hand.

## Using it on a new VPS

- When creating the VPS, paste the contents of one of the templates below into the provider's
  "user data" / "cloud-init" field:
  - `user-data/base.yaml` - tracks the `main` branch of this repo. Use this for a normal
    machine.
  - `user-data/base-dev.yaml` - tracks the `dev` branch. Use this while testing changes to
    the playbook/roles themselves.
  - `user-data/base-extended.yaml` - `base` plus the `extended` role (editors, shell
    niceties) - a reasonable choice for a VPS you'll be logging into and working on directly.
  - `user-data/alpine.yaml` - the Alpine example: same roles as above, plus the
    `ansible-galaxy collection install community.general` line Alpine needs (see below).
  - `user-data/test-all.yaml` - the config the Docker smoke test runs by default. Keep it
    limited to roles that don't manage services, see "Testing changes locally" below.
- On first boot, cloud-init installs Ansible via the distro package manager, then runs
  `ansible-pull` against this repo's `ansible/playbook.yml`. No manual steps are needed after that.
- With no `-e "roles=..."` flag at all, only the `base` role runs (baseline packages, no
  extras) - that's what `base.yaml`/`base-dev.yaml` do. To enable other roles, copy the
  template and add a `-e "roles=..."` flag to the `ansible-pull` line in `runcmd:`, for example:
  ```yaml
  runcmd:
    - set -e
    - ansible-pull --url=https://github.com/nvsmirnov/cloud-init-ansiblepull.git --checkout=main -e "roles=base,web,db" ansible/playbook.yml
  ```
  `roles=...` is a full replacement list, not an addition to the baseline: once you set it
  explicitly, `base` runs only if you list it yourself alongside the others. Role names must match
  a directory under `ansible/roles/` in this repo - an unknown role name makes the whole run fail
  loudly, so a typo is caught immediately instead of silently leaving the machine half-configured.
- You can also append your own extra commands after the `ansible-pull` line to run additional
  setup once the bootstrap completes - `runcmd:` is just a plain list executed top to bottom as
  one script, so anything listed after our line runs after the playbook has finished. Keep the
  leading `- set -e` line intact - without it, a failing command anywhere in `runcmd:` (including
  our own `ansible-pull` line) is silently swallowed: the rest of the script keeps running and
  `cloud-init status` reports success even though something actually failed.

## Using it on an already-installed Linux machine

The same repo and playbook work without a cloud provider or cloud-init at all:
`scripts/manual.sh` installs `ansible-core`/`git` if needed and runs `ansible-pull` directly. Run
as root:

```bash
curl -sSf --retry 3 -o manual.sh \
  https://raw.githubusercontent.com/nvsmirnov/cloud-init-ansiblepull/main/scripts/manual.sh \
  && bash manual.sh
```

No command-line arguments. With no `ROLES` set, `base,extended` roles run by default (unlike
`ansible/playbook.yml` itself, whose own default with no `roles=...` at all is just `base` - see
above; `scripts/manual.sh` picks a richer default since it's typically bootstrapping a machine
you'll work on directly). To use different roles, track the `dev` branch instead of `main`, or
point at a different repo, override the environment variables the script reads (same
`${VAR:-default}` pattern throughout):

```bash
REPO_CHECKOUT=dev \
ROLES=base,extended \
bash manual.sh
```

This is a one-time operation, not a persistent install: `scripts/manual.sh` installs `git` and
`ansible-core` only if they are not already present, and removes exactly the ones it installed
once the playbook has run - anything that was already on the machine (including these same
packages, or whatever the playbook's roles installed) is left alone.

`ansible-core` normally pulls in a large set of Recommends it doesn't need (the full `ansible`
collections metapackage plus WinRM/Kerberos/SELinux plugins, ~224 MB on apt-based systems).
`scripts/manual.sh` cleans these up too via autoremove, but only if there were zero orphaned
packages on the machine before it started - if there already were, it leaves autoremove alone
entirely rather than guess which orphans are its own. The package manager's cache is always
cleared at the end.

`scripts/manual.sh` supports apt-based (Debian/Ubuntu), dnf-based (RHEL-family: RHEL, Rocky, Alma,
Fedora, Amazon Linux 2023), and apk-based (Alpine) systems, detected from `/etc/os-release`. Any
other distro fails immediately with a clear "not supported" message rather than guessing.

## Adding a role to this repo

- Put role tasks under `ansible/roles/<name>/tasks/main.yml` (standard Ansible role layout).
- Reference `roles=<name>` via the `ansible-pull -e "roles=..."` flag in a user-data template's
  `runcmd:` to enable it on a given machine.
- `ansible/roles/base/` is the default role (applied when `roles=...` isn't set at all) and is a
  good place to look at for a minimal example.

## Testing changes locally before deploying

`tests/test-all.sh` is the usual entry point: it runs the smoke test across every supported base
image (`amazonlinux`, `alpine`, `debian`, `ubuntu`, `fedora`, all `:latest`) and prints a
pass/fail summary at the end. It stops at the first failing image by default; set
`NO_STOP_ON_FIRST_FAIL=1` to run the whole matrix regardless.

Underneath it, `tests/run.sh [user-data/template.yaml]` tests a single image: it runs the real
`cloud-init` binary against a chosen template (default `user-data/test-all.yaml`) inside a
disposable Docker container (no VM, no systemd, no `--privileged`), pointed at a throwaway
snapshot of your current working tree instead of GitHub - no commit needed, uncommitted and
untracked changes are picked up as-is. Requires Docker. Passes when cloud-init reports no hard
error, the bootstrap marker file `/var/lib/cloud-init-ansiblepull/all-done` is present, and a
second `ansible-pull` run reports no changes.

Roles that manage services can't be exercised here: a container has no real init process as PID 1,
so `ansible.builtin.service` fails regardless of base image (confirmed the same way under
Alpine/OpenRC and Fedora/systemd). That's why `user-data/test-all.yaml` sticks to roles that don't
touch services, and why the `nginx` sample role isn't wired into any template. It's a
container-testing-environment limitation, not a portability bug in the role.

The Docker base image defaults to `ubuntu:latest`; override with `BASE_IMAGE=fedora:latest
tests/run.sh ...` (any apt-, dnf- or apk-based image/tag works) to test against something else.
