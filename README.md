# codecli

codecli is a command-line interface tool for creating and managing secure code-server IDE private users using SystemD and Docker services.

## Features

- Quick create code-server workspace in root
- Create and manage SystemD workspaces
- Create and manage Docker containers
- Limit RAM and CPU usage for workspaces
- Manage user accounts and passwords
- Schedule workspace deletions
- Backup workspaces to cloud storage
- Monitor port usage and container status
- Set optional memory, CPU, and ext4 user-quota limits for Docker workspaces
- Select a custom Docker image with `-i`

## Installation

Make sure you have root access before doing this installation.

```bash
sudo curl -fsSL https://jayanode.com/api/mirror/codecli/build?raw=true | sudo bash
```

## Usage

codecli must be run as root. The general syntax is:

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

## Supported Environments

- Debian-based systems (Ubuntu 22.04, 24.04, 26.04)
- Docker workspaces use the LinuxServer Code-Server image by default; custom images are supported.

## Backup

codecli supports backing up workspaces to various cloud storage providers using Rclone.

To set up a backup, use the `codecli backup` command and follow the prompts.

Additional folders or files can be included in every archive with the repeatable `-a` option. Paths are resolved from each Docker root directory (`/home/codeusers` or `/home/codeusersmemlimit`) and may use `{folder}` and `{user}` placeholders:

```bash
codecli backup -n drive -h 2 -f backups -s 1 -a 'additional/{user}/data'
```

Storage limits require an ext4 filesystem mounted with `usrquota`. Use `-q 10G`, `-q 500M`, or `-q 0` (unlimited) when creating a Docker workspace.

## Updating

To update codecli to the latest version, run:

```bash
codecli update
```

## License

This project is licensed under the MIT License.

## Information

If you have any problem in using codecli, please open a new issue.
