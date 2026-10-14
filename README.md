# codecli

codecli is a command-line interface tool for creating and managing secure code-server IDE private users using SystemD and Docker services.

## Features

- Quick create code-server workspace in root
- Create and manage SystemD workspaces
- Create and manage Docker containers
- Limit RAM and CPU usage for workspaces
- Manage user accounts and passwords
- Schedule workspace stops and deletions
- Backup workspaces to cloud storage
- Monitor port usage and container status
- Set optional memory, CPU, and ext4 user-quota limits for Docker workspaces
- Select a custom Docker image with `-i`

## Installation

Make sure you have root access before doing this installation.

```bash
curl -fsSL https://jayanode.com/api/mirror/codecli/build?raw=true | sudo bash
```

The installer (`build.sh` → `scripts/install.sh`) installs the base packages, `at`, rclone, Docker, the `codeusers` and `codeusersmemlimit` host users with their compose files, and then `/usr/local/bin/codecli`. It is safe to re-run: it does not overwrite an existing `/etc/docker/daemon.json`, host users, or rclone.

## Usage

codecli must be run as root (except `help` and `version`). The general syntax is:

```bash
codecli [command] [argument] [argument]
```

To see all available commands:

```bash
codecli help
```

To quickly create a code-server workspace in root:

```bash
codecli quickcreate
```

Options may be passed as flags (`-u`, `-p`, `-o`, `-l`, `-c`, `-i`, `-q`, `-t`, ...); anything missing is asked interactively. Unknown flags and unexpected arguments are rejected with a non-zero exit status.

Example (Docker workspace with limits):

```bash
codecli create dockerlimit -u alice -p 'S3cret!pass' -o 20001 -l 1024m -c 0.5 -q 10G -i linuxserver/code-server:latest
codecli manage docker stop -u alice -t 2
codecli manage docker start -u alice -t 2
codecli manage docker delete -u alice -t 2
```

`-t 1` selects the plain Docker root (`/home/codeusers`) and `-t 2` the limited root (`/home/codeusersmemlimit`).

### Notes on workspace settings and passwords

- Each Docker workspace stores its compose settings (port, password, image, limits) in a private file `/home/codeusers[memlimit]/.env.d/<user>.env` (mode 0600, directory 0700). Older workspaces keep working through the legacy shared `.env`; run `codecli manage docker password -u <user>` once to migrate one.
- Passwords are stored single-quoted so characters such as `$` and `#` reach the container unchanged. A Docker workspace password may not contain a single quote or a line break.
- Passwords are never echoed. Note that passing `-p` on the command line is visible to other local users through `ps`; omit it to be prompted instead.
- Usernames must match `[A-Za-z0-9][A-Za-z0-9_-]*` (max 64 characters).
- `-c` takes a CPU count (for example `0.5`) for Docker workspaces and a percentage (for example `50%`) or CPU count for SystemD workspaces.
- The daily update notice is only shown for interactive terminals.

## Supported Environments

- Ubuntu 22.04, 24.04 and 26.04 (the all-in installer).
- Docker workspaces use the LinuxServer Code-Server image by default; custom images are supported.

## Backup

codecli supports backing up workspaces to various cloud storage providers using Rclone.

To set up a backup, use the `codecli backup` command and follow the prompts.

Additional folders or files can be included in every archive with the repeatable `-a` option. Paths are resolved from each Docker root directory (`/home/codeusers` or `/home/codeusersmemlimit`) and may use `{folder}` and `{user}` placeholders:

```bash
codecli backup -n drive -h 2 -f backups -s 1 -a 'additional/{user}/data'
```

Re-running the command for the same remote replaces its cron entry, and overlapping runs are prevented with a lock.

Storage limits require an ext4 filesystem mounted with `usrquota` (or `usrjquota`) and a host user with the same name as the workspace. Use `-q 10G`, `-q 500M`, or `-q 0` (unlimited) when creating a Docker workspace; when the quota cannot be applied a warning is printed and creation continues.

## Updating

To update codecli to the latest version, run:

```bash
codecli update
```

## License

This project is licensed under the MIT License.

## Information

If you have any problem in using codecli, please open a new issue.
