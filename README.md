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

## Installation

Make sure you have root access before doing this installation.

Get Dependencies

```bash
sudo wget https://raw.githubusercontent.com/gvoze32/codecli/master/scripts/install.sh && sudo chmod +x install.sh && sudo ./install.sh
```

Install

```bash
sudo wget https://raw.githubusercontent.com/gvoze32/codecli/master/codecli.sh -O /usr/local/bin/codecli && sudo chmod +x /usr/local/bin/codecli
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

- Debian-based systems (Ubuntu 20.04, 22.04, 24.04)

## Backup

codecli supports backing up workspaces to various cloud storage providers using Rclone.

To set up a backup, use the `codecli backup` command and follow the prompts.

## Updating

To update codecli to the latest version, run:

```bash
codecli update
```

## License

This project is licensed under the MIT License.

## Information

If you have any problem in using codecli, please open a new issue.
