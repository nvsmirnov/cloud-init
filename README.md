# nvsmirnov/cloud-init-ansiblepull

Project for initial linux server set-up utilizing cloud-init and ansible.

Feel free to fork.

Full AI-generated documentation: [AI-docs/AI-readme.md](AI-docs/AI-readme.md).

## Sample use case:

Add this as a user-data of your VM:
```
#cloud-config
packages:
  - git
  - ansible-core
runcmd:
  - set -e
  - if command -v apk >/dev/null 2>&1; then ansible-galaxy collection install community.general; fi
  - ansible-pull --url=https://github.com/nvsmirnov/cloud-init-ansiblepull.git --checkout=main ansible/playbook.yml
```
Above, `#cloud-config` on first line is mandatory, `git` and `ansible-core` packages are required for `ansible-pull` to work.
Currently, this adds about 200MB+ of packages in ubuntu/debian.

Note: the line containing `if command -v apk` is only needed for Alpine Linux.
So if you know you use another distro, you can omit this line.

If you prefer to have more pre-installed tools (minimal adequate list, for author's taste),
or explicitly set which ansible roles must be run, add roles list to last line:
```
  - ansible-pull --url=https://github.com/nvsmirnov/cloud-init-ansiblepull.git --checkout=main -e "roles=base,extended" ansible/playbook.yml
```

Other samples are in [user-data](user-data) directory.

You can add your own commands into `runcmd` section, or add packages into `packages`, or edit this config as you want before applying.
It is a standard [cloud-init](https://docs.cloud-init.io/) config.

P.S. not using cloud-init's cc_ansible module mainly because it is absent in AWS AMI configuration.

## How to apply config existing machine

First, install curl and bash - it is platform-specific.

Then, run:
```
curl -sSf https://raw.githubusercontent.com/nvsmirnov/cloud-init-ansiblepull/main/scripts/manual.sh | bash
```
No cloud-init involved here - `manual.sh` runs `ansible-pull` directly. By default the `base,extended` roles are applied.
Set `ROLES` variable to override list of applied roles, i.e. `export ROLES=base,extended,nginx` (etc.).
See [AI-docs/AI-readme.md](AI-docs/AI-readme.md) for details.

## How to test changes

Docker required. After you changed something, run:
```
tests/test-all.sh
```
By default it tests on config `user-data/test-all.yaml`.

Note that if you're adding a role which manages services (enable, start/stop),
and want to test it under docker, test suite needs to be reworked, because by default
ansible can't manage service state under docker.

But, if you added a new role that doesn't manage a service, add it to `user-data/test-all.yaml`.

P.S. while reading cloud-init-output.log on real machines, you may notice ansible's warnings `Could not match supplied host pattern`.
That's standard ansible behaviour.
It can be fixed with `--limit localhost` argument to `ansible-pull` in `#cloud-config`, but I prefer to keep it minimalistic.

## Credits

Author: Nikita Smirnov.

Initially - a personal tool for pre-setting various VPS and cloud servers.

Generated with Claude Code to save time :)
