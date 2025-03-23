#!/bin/bash
VERSION="2.10"

if [ "$(id -u)" != "0" ]; then
  echo "codecli must be run as root!" 1>&2
  exit 1
fi

ubuntu_version=$(lsb_release -r | awk '{print $2}')

check_update() {
  echo "Checking for available updates..."

  REPO_URL="https://hostingjaya.ninja/api/mirror/codecli?raw=true"
  max_attempts=3
  attempt=1

  while [ $attempt -le $max_attempts ]; do
    if latest_info=$(curl -s --connect-timeout 10 "$REPO_URL/codecli"); then
      latest_version=$(echo "$latest_info" | grep -o 'VERSION="[0-9]*\.[0-9]*"' | cut -d '"' -f 2)

      if [ -n "$latest_version" ]; then
        if [ "$latest_version" != "$VERSION" ]; then
          echo "New version available: v$latest_version (current: v$VERSION)"
          echo "Run 'codecli update' to update."
        else
          echo "You are using the latest version (v$VERSION)."
        fi
        return 0
      else
        echo "Failed to extract version information."
      fi
    else
      echo "Failed to connect to update server on attempt $attempt of $max_attempts."
    fi

    attempt=$((attempt + 1))
    [ $attempt -le $max_attempts ] && {
      echo "Retrying in 2 seconds..."
      sleep 2
    }
  done

  echo "Failed to check for updates after $max_attempts attempts."
  return 1
}

LAST_CHECK_FILE="/tmp/codecli_last_check"
CHECK_INTERVAL=86400

current_time=$(date +%s)

if [ -f "$LAST_CHECK_FILE" ]; then
  last_check=$(cat "$LAST_CHECK_FILE")
  time_diff=$((current_time - last_check))

  if [ $time_diff -gt $CHECK_INTERVAL ]; then
    check_update
    echo "$current_time" >"$LAST_CHECK_FILE"
  fi
else
  echo "$current_time" >"$LAST_CHECK_FILE"
  check_update
fi

# COMMANDS

banner() {
  echo "               _           _ _ "
  echo "              | |         | (_)"
  echo "  ___ ___   __| | ___  ___| |_ "
  echo " / __/ _ \ / _' |/ _ \/ __| | |"
  echo "| (_| (_) | (_| |  __/ (__| | |"
  echo " \___\___/ \__,_|\___|\___|_|_|"

  echo
  echo "====  CODE-SERVER CLI MANAGER  ===="
  echo
}
about() {
  echo "Name of File  : codecli.sh"
  echo "Version       : $VERSION"
  echo "Tested on     :"
  echo "    - Debian  : Ubuntu 20.04, 22.04, 24.04"
  echo
  echo "Built with love♡ by gvoze32"
}
# =========== DON'T CHANGE THE ORDER OF THIS FUNCTION =========== #

bantuan() {
  echo "How to use:"
  echo "codecli must be run as root"
  echo "codecli [command] [argument] [argument]"
  echo
  echo "Command Lists:"
  echo "quickcreate         : Quick create code server workspace in root"
  echo "  restart           : Restart quick created code server"
  echo "  fix               : Fix quick created code server installation"
  echo "create"
  echo "  systemd           : Create a new SystemD workspace"
  echo "  systemdlimit      : Create a new SystemD workspace with limited RAM"
  echo "  docker            : Create a new Docker container"
  echo "  dockerlimit       : Create a new Docker container with limited RAM"
  echo "manage"
  echo "  systemd"
  echo "    stop            : Stop workspace"
  echo "    start           : Start workspace"
  echo "    delete          : Delete workspace"
  echo "    status          : Show workspace status"
  echo "    restart         : Restart workspace"
  echo "    password        : Change user password"
  echo "    schedule        : Schedule workspace deletion"
  echo "    scheduled       : Show scheduled workspace deletion"
  echo "    convert         : Convert user to superuser"
  echo "  docker"
  echo "    stop            : Stop Docker container"
  echo "    start           : Start Docker container"
  echo "    delete          : Delete Docker container"
  echo "    status          : Show container status"
  echo "    restart         : Restart running containers"
  echo "    restartall      : Restart (all) running containers"
  echo "    reset           : Reset Docker container"
  echo "    password        : Change user password, port & update limited RAM for dockerlimit"
  echo "    schedule        : Schedule container deletion"
  echo "    scheduled       : Show scheduled container deletion"
  echo "    list            : Show Docker container lists"
  echo "    configure       : Stop, start or restart running container"
  echo "port                : Show used port lists"
  echo "backup              : Backup workspace data with Rclone (Docker only)"
  echo "update              : Update code server to the latest version"
  echo "help                : Show help"
  echo "version             : Show version"
  echo
  echo "Options:"
  echo "-u                  : Username"
  echo "-p                  : Password"
  echo "-o                  : Port number"
  echo "-l                  : Memory limit (e.g., 1024m)"
  echo "-c                  : CPU limit (e.g., 10% or 1.0)"
  echo "-i                  : Image (e.g., gvoze32/code-server:jammy)"
  echo "-t                  : Type (e.g., 1 for Docker, 2 for Docker Memory Limit)"
  echo "-n                  : Rclone remote name"
  echo "-h                  : Backup hour"
  echo "-f                  : Backup folder name"
  echo "-s                  : Backup service provider"
  echo
  echo "Copyright (c) 2024 codecli (under MIT License)"
  echo "Built with love♡ by gvoze32"
}

# CREATE SYSTEMD

createnewsystemd() {
  local user password port

  while getopts "u:p:o:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    p) password="$OPTARG" ;;
    o) port="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Username : " user
  fi
  if [[ -z "$password" ]]; then
    read -s -p "Password : " password
    echo
  fi
  if [[ -z "$port" ]]; then
    read -p "Port : " port
  fi

  apt-get update -y
  apt-get upgrade -y

  sudo adduser --disabled-password --gecos "" $user
  sudo echo -e "$password\n$password" | passwd $user

  sudo chown -R $user:$user /home/$user

  sudo -u $user -H sh -c "curl -fsSL https://code-server.dev/install.sh | sh"

  sudo chmod 700 /home/$user/ -R

  cat >/lib/systemd/system/code-$user.service <<EOF
[Unit]
Description=code-server for $user
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:$port --user-data-dir /var/lib/code-server --auth password
User=$user
Group=$user

UMask=0002
Restart=on-failure

WorkingDirectory=/home/$user/workspace
Environment=PASSWORD=$password

StandardOutput=journal
StandardError=journal
SyslogIdentifier=code-$user

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable code-$user.service
  systemctl restart code-$user.service
  sleep 10
  systemctl status code-$user.service
}

createnewsystemdlimit() {
  local user password port limit cpu_limit

  while getopts "u:p:o:l:c:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    p) password="$OPTARG" ;;
    o) port="$OPTARG" ;;
    l) limit="$OPTARG" ;;
    c) cpu_limit="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Username: " user
  fi
  if [[ -z "$password" ]]; then
    read -s -p "Password: " password
    echo
  fi
  if [[ -z "$port" ]]; then
    read -p "Port: " port
  fi
  if [[ -z "$limit" ]]; then
    read -p "Memory Limit (e.g., 1024m): " limit
  fi
  if [[ -z "$cpu_limit" ]]; then
    read -p "CPU Limit (e.g., 10%): " cpu_limit
  fi

  apt-get update -y
  apt-get upgrade -y

  sudo adduser --disabled-password --gecos "" $user
  sudo echo -e "$password\n$password" | passwd $user

  sudo chown -R $user:$user /home/$user

  sudo -u $user -H sh -c "curl -fsSL https://code-server.dev/install.sh | sh"

  sudo chmod 700 /home/$user/ -R

  cat >/lib/systemd/system/code-$user.service <<EOF
[Unit]
Description=code-server for $user
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:$port --user-data-dir /var/lib/code-server --auth password
User=$user
Group=$user

UMask=0002
MemoryMax=$limit
CPUQuota=$cpu_limit

Restart=on-failure

WorkingDirectory=/home/$user/workspace
Environment=PASSWORD=$password

StandardOutput=journal
StandardError=journal
SyslogIdentifier=code-$user

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable code-$user.service
  systemctl restart code-$user.service
  sleep 10
  systemctl status code-$user.service
}

# CREATE DOCKER

createnewdocker() {
  while getopts "u:p:o:i:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    p) password="$OPTARG" ;;
    o) port="$OPTARG" ;;
    i) image="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Username: " user
  fi
  if [[ -z "$password" ]]; then
    read -s -p "Password: " password
    echo
  fi
  if [[ -z "$port" ]]; then
    read -p "Port: " port
  fi
  if [[ -z "$image" ]]; then
    echo "Select image:"
    echo "1. Ubuntu 20.04"
    echo "2. Ubuntu 22.04"
    echo "3. Ubuntu 24.04"
    read -p "Enter image option (1-3): " image_choice
    if [ "$image_choice" == "1" ]; then
      image="gvoze32/code-server:focal"
    elif [ "$image_choice" == "2" ]; then
      image="gvoze32/code-server:jammy"
    elif [ "$image_choice" == "3" ]; then
      image="gvoze32/code-server:noble"
    else
      echo "Invalid option, using default image."
      image="gvoze32/code-server:jammy"
    fi
  else
    echo "Using provided image: $image"
  fi
  echo
  echo "Creating docker container:"
  echo "Username: $user"
  echo "Password: $password"
  echo "Port: $port"
  echo "Image: $image"

  cd /home/codeusers
  rm .env
  cat >/home/codeusers/.env <<EOF
PORT=$port
NAMA_PELANGGAN=$user
PASSWORD_PELANGGAN=$password
DOCKER_IMAGE=$image
EOF
  sudo docker compose -p $user up -d
  if [ -d "/home/codeusers/$user/config/workspace" ]; then
    cd /home/codeusers/$user/config/workspace

    ### Your custom default bundling files goes here, it's recommended to put it on resources directory
    ### START

    ### END

    cd
  else
    echo -e "\033[33mWARN! Workspace directory not found - Ignore this message if you are not adding default bundling files\033[0m"
  fi
}

# CREATE DOCKERLIMIT

createnewdockermemlimit() {
  while getopts "u:p:o:l:c:i:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    p) password="$OPTARG" ;;
    o) port="$OPTARG" ;;
    l) limit="$OPTARG" ;;
    c) cpu_limit="$OPTARG" ;;
    i) image="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Username: " user
  fi
  if [[ -z "$password" ]]; then
    read -s -p "Password: " password
    echo
  fi
  if [[ -z "$port" ]]; then
    read -p "Port: " port
  fi
  if [[ -z "$limit" ]]; then
    read -p "Memory Limit (e.g., 1024m): " limit
  fi
  if [[ -z "$cpu_limit" ]]; then
    read -p "CPU Limit (e.g., 1.0 for 1 core): " cpu_limit
  fi
  if [[ -z "$image" ]]; then
    echo "Select image:"
    echo "1. Ubuntu 20.04"
    echo "2. Ubuntu 22.04"
    echo "3. Ubuntu 24.04"
    read -p "Enter image option (1-3): " image_choice
    if [ "$image_choice" == "1" ]; then
      image="gvoze32/code-server:focal"
    elif [ "$image_choice" == "2" ]; then
      image="gvoze32/code-server:jammy"
    elif [ "$image_choice" == "3" ]; then
      image="gvoze32/code-server:noble"
    else
      echo "Invalid option, using default image."
      image="gvoze32/code-server:jammy"
    fi
  else
    echo "Using provided image: $image"
  fi
  echo
  echo "Creating docker container with memory limit:"
  echo "Username: $user"
  echo "Password: $password"
  echo "Port: $port"
  echo "Memory Limit: $limit"
  echo "CPU Limit: $cpu_limit"
  echo "Image: $image"

  cd /home/codeusersmemlimit
  rm .env
  cat >/home/codeusersmemlimit/.env <<EOF
PORT=$port
NAMA_PELANGGAN=$user
PASSWORD_PELANGGAN=$password
MEMORY=$limit
CPU_LIMIT=$cpu_limit
DOCKER_IMAGE=$image
EOF
  sudo docker compose -p $user up -d
  if [ -d "/home/codeusersmemlimit/$user/config/workspace" ]; then
    cd /home/codeusersmemlimit/$user/config/workspace

    ### Your custom default bundling files goes here, it's recommended to put it on resources directory
    ### START

    ### END

    cd
  else
    echo -e "\033[33mWARN! Workspace directory not found - Ignore this message if you are not adding default bundling files\033[0m"
  fi
}

# MANAGE SYSTEMD

stopsystemd() {
  while getopts "u:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  sleep 3
  systemctl stop code-$user.service
}

startsystemd() {
  while getopts "u:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  sleep 3
  systemctl start code-$user.service
}

deletesystemd() {
  while getopts "u:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  sleep 3
  systemctl stop code-$user.service
  sleep 3
  killall -u $user
  sleep 3
  userdel $user
  rm -rf /home/$user
}

statussystemd() {
  while getopts "u:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  systemctl status code-$user.service
}

restartsystemd() {
  while getopts "u:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  systemctl daemon-reload
  systemctl enable code-$user.service
  systemctl restart code-$user.service
  sleep 10
  systemctl status code-$user.service
}

changepasswordsystemd() {
  while getopts "u:p:o:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    p) password="$OPTARG" ;;
    o) port="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  if [[ -z "$password" ]]; then
    read -p "Input New Password: " password
  fi

  if [[ -z "$port" && -n "$OPTARG" ]]; then
    read -p "Input New Port: " port
  fi

  sed -i "s/^Environment=PASSWORD=.*/Environment=PASSWORD=$password/" /lib/systemd/system/code-$user.service

  if [[ -n "$port" ]]; then
    sed -i "s/--bind-addr 0.0.0.0:[0-9]*/--bind-addr 0.0.0.0:$port/" /lib/systemd/system/code-$user.service
  fi

  systemctl daemon-reload
  systemctl restart code-$user.service
  sleep 10
  systemctl status code-$user.service
}

schedulesystemd() {
  while getopts "u:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  echo " "
  echo "Format Example for Time: "
  echo " "
  echo "10:00 AM 6/22/2015"
  echo "10:00 AM July 25"
  echo "10:00 AM"
  echo "10:00 AM Sun"
  echo "10:00 AM next month"
  echo "10:00 AM tomorrow"
  echo "now + 1 hour"
  echo "now + 30 minutes"
  echo "now + 1 week"
  echo "now + 1 year"
  echo "midnight"
  echo " "
  read -p "Time: " waktu
  at $waktu <<END
sleep 3
systemctl stop code-$user.service
sleep 3
killall -u $user
sleep 3
userdel $user
END
}

scheduledatq() {
  atq
}

convertsystemd() {
  while getopts "u:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  echo "Input user password"
  passwd $user
  echo "Warning, code-server will be restart!"
  usermod -aG sudo $user
  systemctl daemon-reload
  systemctl enable code-$user.service
  systemctl restart code-$user.service
  sleep 10
  systemctl status code-$user.service
}

# MANAGE DOCKER

stopdocker() {
  while getopts "u:t:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    t) type="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  if [[ -z "$type" ]]; then
    echo "Are the file is using Docker or Docker Memory Limit?"
    echo "1. Docker"
    echo "2. Docker Memory Limit"
    read -r -p "Choose: " response
  else
    response="$type"
  fi

  case "$response" in
  1)
    cd /home/codeusers
    ;;
  *)
    cd /home/codeusersmemlimit
    ;;
  esac
  docker compose -p $user stop
}

startdocker() {
  while getopts "u:t:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    t) type="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  if [[ -z "$type" ]]; then
    echo "Are the file is using Docker or Docker Memory Limit?"
    echo "1. Docker"
    echo "2. Docker Memory Limit"
    read -r -p "Choose: " response
  else
    response="$type"
  fi

  case "$response" in
  1)
    cd /home/codeusers
    ;;
  *)
    cd /home/codeusersmemlimit
    ;;
  esac
  docker compose -p $user start
}

deletedocker() {
  while getopts "u:t:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    t) type="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  if [[ -z "$type" ]]; then
    echo "Are the file is using Docker or Docker Memory Limit?"
    echo "1. Docker"
    echo "2. Docker Memory Limit"
    read -r -p "Choose: " response
  else
    response="$type"
  fi

  case "$response" in
  1)
    cd /home/codeusers
    ;;
  *)
    cd /home/codeusersmemlimit
    ;;
  esac
  docker compose -p $user down
  rm -rf $user
}

listdocker() {
  docker ps
}

statusdocker() {
  docker stats
}

changepassworddocker() {
  while getopts "u:p:t:o:l:c:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    p) newpw="$OPTARG" ;;
    t) type="$OPTARG" ;;
    o) port="$OPTARG" ;;
    l) mem="$OPTARG" ;;
    c) cpu_limit="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input Username: " user
  fi

  if [[ -z "$newpw" ]]; then
    read -p "Input New Password: " newpw
  fi

  if [[ -z "$port" ]]; then
    read -p "Input Port: " port
  fi

  if [[ -z "$type" ]]; then
    echo "Is the user using Docker or Docker Memory Limit?"
    echo "1. Docker"
    echo "2. Docker Memory Limit"
    read -r -p "Choose: " response
  else
    response="$type"
  fi

  case "$response" in
  1)
    base_dir="/home/codeusers"
    mem=""
    cpu_limit=""
    ;;
  2)
    base_dir="/home/codeusersmemlimit"
    if [[ -z "$mem" ]]; then
      read -p "Memory Limit (e.g., 1024m): " mem
    fi
    if [[ -z "$cpu_limit" ]]; then
      read -p "CPU Limit (e.g., 1.0 for 1 core): " cpu_limit
    fi
    ;;
  *)
    echo "Invalid option"
    return
    ;;
  esac

  cd "$base_dir" || return

  cat >.env <<EOF
NAMA_PELANGGAN=$user
PASSWORD_PELANGGAN=$newpw
PORT=$port
EOF

  if [ "$response" = "2" ]; then
    cat >>.env <<EOF
MEMORY=$mem
CPU_LIMIT=$cpu_limit
DOCKER_IMAGE=gvoze32/code-server:jammy
EOF
  fi

  if [ -d "$base_dir/$user" ]; then
    cd "$base_dir/$user" || return
    cat >.env <<EOF
PORT=$port
NAMA_PELANGGAN=$user
PASSWORD_PELANGGAN=$newpw
EOF

    if [ "$response" = "2" ]; then
      cat >>.env <<EOF
MEMORY=$mem
CPU_LIMIT=$cpu_limit
EOF
    fi

    cd "$base_dir"
    echo "Password, port and .env updated for user $user"
    docker compose -p $user down
    docker compose -p $user up -d
    echo "Docker container recreated for user $user"
  else
    echo "User $user does not exist or workspace directory not found"
  fi
}

scheduledocker() {
  while getopts "u:t:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    t) type="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  if [[ -z "$type" ]]; then
    echo "Are the file is using docker or dockermemlimit?"
    read -r -p "Answer Y if you are using docker and answer N if you are using dockermemlimit [y/N] " response
  else
    case "$type" in
    1) response="y" ;;
    2) response="n" ;;
    esac
  fi

  echo " "
  echo "Format Example for Time: "
  echo " "
  echo "10:00 AM 6/22/2015"
  echo "10:00 AM July 25"
  echo "10:00 AM"
  echo "10:00 AM Sun"
  echo "10:00 AM next month"
  echo "10:00 AM tomorrow"
  echo "now + 1 hour"
  echo "now + 30 minutes"
  echo "now + 1 week"
  echo "now + 1 year"
  echo "midnight"
  echo " "
  read -p "Time: " waktu
  case "$response" in
  [yY][eE][sS] | [yY])
    at $waktu <<END
cd /home/codeusers
docker compose -p $user stop
# OPTIONAL: Remove user setup
# docker compose -p $user down
END
    ;;
  *)
    at $waktu <<END
cd /home/codeusersmemlimit
docker compose -p $user stop
# OPTIONAL: Remove user setup
# docker compose -p $user down
END
    ;;
  esac
}

configuredocker() {
  read -p "Input User: " user
  echo 1. Stop
  echo 2. Start
  echo 3. Restart
  read -r -p "Choose: " response
  case "$response" in
  1)
    echo Are the file is using Docker or Docker Memory Limit?
    echo 1. Docker
    echo 2. Docker Memory Limit
    read -r -p "Choose: " response
    case "$response" in
    1)
      cd /home/codeusers
      ;;
    *)
      cd /home/codeusersmemlimit
      ;;
    esac
    docker container stop $user
    # OPTIONAL: Remove user setup
    # docker compose -p $user down
    ;;
  2)
    echo Are the file is using Docker or Docker Memory Limit?
    echo 1. Docker
    echo 2. Docker Memory Limit
    read -r -p "Choose: " response
    case "$response" in
    1)
      cd /home/codeusers
      ;;
    *)
      cd /home/codeusersmemlimit
      ;;
    esac
    docker container start $user
    ;;
  *)
    echo Are the file is using Docker or Docker Memory Limit?
    echo 1. Docker
    echo 2. Docker Memory Limit
    read -r -p "Choose: " response
    case "$response" in
    1)
      cd /home/codeusers
      ;;
    *)
      cd /home/codeusersmemlimit
      ;;
    esac
    docker container stop $user
    docker container start $user
    # OPTIONAL: Remove user setup
    # docker compose -p $user down
    # docker compose -p $user up -d
    ;;
  esac
}

restartdocker() {
  while getopts "u:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  containers=$(docker ps --format "{{.Names}}")
  echo "Container lists:"
  echo "$containers" | sed 's/^code-//'

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  container_name="code-$user"

  if echo "$containers" | grep -qw "$container_name"; then
    docker restart "$container_name"

    if [ $? -eq 0 ]; then
      echo "Container '$container_name' restarted successfully."
    else
      echo "Container restart '$container_name' failed."
    fi
  else
    echo "Container name '$container_name' invalid. Make sure the name is correct."
  fi
}

restartdockerall() {
  docker restart $(docker ps -q)
}

resetdocker() {
  while getopts "u:t:" opt; do
    case $opt in
    u) user="$OPTARG" ;;
    t) type="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  if [[ -z "$user" ]]; then
    read -p "Input User: " user
  fi

  if [[ -z "$type" ]]; then
    echo "Are the file is using Docker or Docker Memory Limit?"
    echo "1. Docker"
    echo "2. Docker Memory Limit"
    read -r -p "Choose: " response
  else
    response="$type"
  fi

  case "$response" in
  1)
    cd /home/codeusers
    ;;
  *)
    cd /home/codeusersmemlimit
    ;;
  esac
  docker compose -p $user down
  docker compose -p $user up -d
}

backups() {
  while getopts "n:h:f:s:" opt; do
    case $opt in
    n) name="$OPTARG" ;;
    h) hour="$OPTARG" ;;
    f) cloud_folder="$OPTARG" ;;
    s) service="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ;;
    esac
  done

  echo "Scheduled Backup - WARNING: This script currently only supports backup for codeusers and codeusersmemlimit docker containers"
  echo "Make sure you have set up an rclone config file using command: rclone config"
  echo "If your storage is bucket type, then name the rclone config name same as your bucket name"
  echo ""
  if [[ -z "$name" ]]; then
    read -p "If all has been set up correctly, then input your rclone remote name: " name
  fi
  if [[ -z "$hour" ]]; then
    read -p "Enter the time for backup (hour 0-23): " hour
  fi
  if [[ -z "$cloud_folder" ]]; then
    read -p "Define the backup folder name on the cloud: " cloud_folder
  fi
  if [[ -z "$service" ]]; then
    echo ""
    echo "Choose the backup service provider"
    echo "1. Google Drive"
    echo "2. Storj"
    echo "3. Backblaze B2"
    echo "4. pCloud"
    echo "5. Jottacloud"
    read -r -p "Choose: " response
  else
    response="$service"
  fi
  case "$response" in
  1)
    backup_path="$cloud_folder"
    list_path="$cloud_folder"
    use_purge=false
    ;;
  2)
    backup_path="$cloud_folder"
    list_path="$cloud_folder"
    use_purge=true
    ;;
  3)
    backup_path="$cloud_folder"
    list_path="$cloud_folder"
    use_purge=true
    ;;
  4)
    backup_path="$cloud_folder"
    list_path="$cloud_folder"
    use_purge=false
    ;;
  5)
    backup_path="$cloud_folder"
    list_path="$cloud_folder"
    use_purge=false
    ;;
  *)
    echo "Invalid option"
    exit 1
    ;;
  esac

  cat >/home/backup-$name.sh <<EOF
#!/bin/bash
date=\$(date +%Y%m%d)
log_file="/home/backup-$name.log"

log_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$log_file"
}

verify_backup() {
    local folder="\$1"
    local user="\$2"
    local new_file="\$folder-\$user-\$date.zip"
    local retry_count=3
    local retry_delay=5
    
    for ((i=1; i<=retry_count; i++)); do
        log_message "Verification attempt \$i of \$retry_count for \$new_file"
        
        if rclone lsf "$name:$backup_path/\$new_file" &>/dev/null; then
            log_message "File \$new_file verified in remote"
            return 0
        fi
        
        log_message "WARNING: \$new_file not found in remote"
        if [ \$i -lt \$retry_count ]; then
            log_message "Retrying in \$retry_delay seconds..."
            sleep \$retry_delay
        fi
    done
    
    return 1
}

cleanup_old_backup() {
    local folder="\$1"
    local user="\$2"
    
    log_message "Checking for old backup files for \$folder-\$user"
    
    backup_files=\$(rclone lsf "$name:$backup_path" --include "\$folder-\$user-*.zip" | sort -r)
    
    backup_count=\$(echo "\$backup_files" | wc -l)
    
    if [ "\$backup_count" -gt 2 ]; then
        log_message "Keeping last 2 backups for \$folder-\$user"
        files_to_delete=\$(echo "\$backup_files" | tail -n +3)
        
        while IFS= read -r file; do
            if [ ! -z "\$file" ]; then
                log_message "Deleting old backup: \$file"
                rclone delete "$name:$backup_path/\$file" >> "\$log_file" 2>&1
            fi
        done <<< "\$files_to_delete"
    else
        log_message "Less than or equal to 2 backups found for \$folder-\$user, no cleanup needed"
    fi
}

log_message "Starting backup process"

cd /home
mkdir -p /home/backup

for folder in codeusers codeusersmemlimit; do
    if [ -d "\$folder" ]; then
        log_message "Processing \$folder"
        cd "\$folder"
        for user_folder in */; do
            user=\${user_folder%/}
            log_message "Backing up \$user from \$folder"
            
            if ! zip -r "/home/backup/\$folder-\$user-\$date.zip" "\$user_folder" -x "*/workspace/.vscode-server/*" >> "\$log_file" 2>&1; then
                log_message "ERROR: Failed to create zip for \$user in \$folder"
                continue
            fi

            log_message "Uploading backup for \$folder-\$user"
            max_retries=3
            retry_count=0
            upload_success=false

            while [ \$retry_count -lt \$max_retries ]; do
                log_message "Upload attempt \$((retry_count + 1)) of \$max_retries"
                
                if rclone copy "/home/backup/\$folder-\$user-\$date.zip" "$name:$backup_path/" >> "\$log_file" 2>&1; then
                    if verify_backup "\$folder" "\$user"; then
                        upload_success=true
                        break
                    fi
                fi
                
                retry_count=\$((retry_count + 1))
                if [ \$retry_count -lt \$max_retries ]; then
                    log_message "Retry in 30 seconds..."
                    sleep 30
                fi
            done

            if [ "\$upload_success" = true ]; then
                log_message "Backup successfully uploaded for \$folder-\$user"
                cleanup_old_backup "\$folder" "\$user"
            else
                log_message "ERROR: Backup failed for \$folder-\$user after \$max_retries attempts"
            fi

            log_message "Removing local backup file for \$folder-\$user"
            rm -f "/home/backup/\$folder-\$user-\$date.zip"
        done
        cd /home
    else
        log_message "Folder \$folder not found, skipping"
    fi
done

log_message "Removing local backup directory"
rm -rf /home/backup >> "\$log_file" 2>&1

log_message "Backup process completed"
EOF

  chmod +x /home/backup-$name.sh
  echo ""
  echo "Backup command created"

  crontab -l >current_cron
  echo "0 $hour * * * /home/backup-$name.sh > /home/backup-$name.log 2>&1" >>current_cron
  crontab current_cron
  rm current_cron

  echo ""
  echo "Cron job created"
  echo ""
  echo "Make sure it's included in your cron list:"
  crontab -l
  echo "Backup rule successfully added"
}

portlist() {
  lsof -i -P -n | grep LISTEN
}

updates() {
  echo "Checking for updates..."

  REPO_URL="https://hostingjaya.ninja/api/mirror/codecli?raw=true"
  max_attempts=3
  attempt=1

  while [ $attempt -le $max_attempts ]; do
    if latest_info=$(curl -s --connect-timeout 10 "$REPO_URL/codecli"); then
      latest_version=$(echo "$latest_info" | grep -o 'VERSION="[0-9]*\.[0-9]*"' | cut -d '"' -f 2)

      if [ -n "$latest_version" ]; then
        if [ "$latest_version" != "$VERSION" ]; then
          echo "Updating to version $latest_version..."

          # Create temporary file
          temp_file=$(mktemp)

          # Download to temporary file first
          if curl -fsSL "$REPO_URL/codecli" -o "$temp_file"; then
            # Verify file was downloaded correctly
            if [ -s "$temp_file" ] && grep -q "VERSION=\"$latest_version\"" "$temp_file"; then
              # Move temporary file to final location
              if sudo mv "$temp_file" /usr/local/bin/codecli && sudo chmod +x /usr/local/bin/codecli; then
                echo "Successfully updated to version $latest_version!"
                echo "Please restart your shell or run 'source /usr/local/bin/codecli' to use the new version."
                return 0
              else
                echo "Failed to install the update. Please check permissions and try again."
              fi
            else
              echo "Downloaded file appears to be invalid. Update aborted."
            fi
          else
            echo "Failed to download update. Please check your internet connection."
          fi

          # Clean up temporary file if it exists
          [ -f "$temp_file" ] && rm -f "$temp_file"
        else
          echo "You are already using the latest version ($VERSION)."
          return 0
        fi
      fi
    fi

    attempt=$((attempt + 1))
    [ $attempt -le $max_attempts ] && sleep 2
  done

  echo "Failed to check for updates after $max_attempts attempts."
  return 1
}

quickcreatecode() {
  echo -e "Starting Quick Code-Server Installation..."

  ipvpsmu=$(curl -s ifconfig.me)
  echo "Server IP: $ipvpsmu"

  WORKSPACE_DIR="/root/workspace"
  mkdir -p "$WORKSPACE_DIR"

  echo "Installing Code-Server..."
  curl -fsSL https://code-server.dev/install.sh | sh

  echo "Starting Code-Server..."
  echo "Access Code-Server IDE at: http://$ipvpsmu:8080"
  PASSWORD="password" code-server --bind-addr 0.0.0.0:8080 --user-data-dir /var/lib/code-server --auth password --without-connection-token "$WORKSPACE_DIR" &

  echo -e "Quick Code-Server Installation Complete!"
  echo -e "Access Code-Server IDE at: http://$ipvpsmu:8080"
  echo -e "Default password: password"
}

restartquickcreate() {
  echo -e "Restarting Code-Server..."

  echo "Stopping existing Code-Server..."
  pkill -f "code-server"
  sleep 3

  ipvpsmu=$(curl -s ifconfig.me)
  echo "Server IP: $ipvpsmu"

  echo "Starting Code-Server..."
  PASSWORD="password" code-server --bind-addr 0.0.0.0:8080 --user-data-dir /var/lib/code-server --auth password --without-connection-token "/root/workspace" &

  echo -e "Code-Server Successfully Restarted!"
  echo -e "Access Code-Server IDE at: http://$ipvpsmu:8080"
  echo -e "Default password: password"
}

fixquickcreate() {
  echo "Fixing Code-Server..."

  echo "Stopping existing Code-Server..."
  pkill -f "code-server"
  sleep 3

  echo "Reinstalling Code-Server..."
  curl -fsSL https://code-server.dev/install.sh | sh

  ipvpsmu=$(curl -s ifconfig.me)

  echo "Starting Code-Server..."
  PASSWORD="password" code-server --bind-addr 0.0.0.0:8080 --user-data-dir /var/lib/code-server --auth password --without-connection-token "/root/workspace" &

  echo -e "Code-Server Fix Complete!"
  echo -e "Access Code-Server IDE at: http://$ipvpsmu:8080"
  echo -e "Default password: password"
}

# BASIC MENUS

helps() {
  banner
  bantuan
}

versions() {
  banner
  about
}

# MENU

case $1 in
quickcreate)
  case $2 in
  restart)
    restartquickcreate
    ;;
  fix)
    fixquickcreate
    ;;
  "")
    quickcreatecode
    ;;
  *)
    echo "Command not found, type codecli help for help"
    ;;
  esac
  ;;

create)
  case $2 in
  systemd)
    createnewsystemd "${@:3}"
    ;;
  systemdlimit)
    createnewsystemdlimit "${@:3}"
    ;;
  docker)
    createnewdocker "${@:3}"
    ;;
  dockerlimit)
    createnewdockermemlimit "${@:3}"
    ;;
  *)
    echo "Command not found, type codecli help for help"
    ;;
  esac
  ;;

manage)
  case $2 in
  systemd)
    case $3 in
    stop)
      stopsystemd "${@:4}"
      ;;
    start)
      startsystemd "${@:4}"
      ;;
    delete)
      deletesystemd "${@:4}"
      ;;
    status)
      statussystemd "${@:4}"
      ;;
    restart)
      restartsystemd "${@:4}"
      ;;
    password)
      changepasswordsystemd "${@:4}"
      ;;
    schedule)
      schedulesystemd "${@:4}"
      ;;
    scheduled)
      scheduledatq
      ;;
    convert)
      convertsystemd "${@:4}"
      ;;
    *)
      echo "Command not found, type codecli help for help"
      ;;
    esac
    ;;

  docker)
    case $3 in
    stop)
      stopdocker "${@:4}"
      ;;
    start)
      startdocker "${@:4}"
      ;;
    delete)
      deletedocker "${@:4}"
      ;;
    list)
      listdocker
      ;;
    status)
      statusdocker
      ;;
    restart)
      restartdocker "${@:4}"
      ;;
    restartall)
      restartdockerall
      ;;
    reset)
      resetdocker "${@:4}"
      ;;
    password)
      changepassworddocker "${@:4}"
      ;;
    schedule)
      scheduledocker "${@:4}"
      ;;
    scheduled)
      scheduledatq
      ;;
    configure)
      configuredocker
      ;;
    *)
      echo "Command not found, type codecli help for help"
      ;;
    esac
    ;;
  *)
    echo "Command not found, type codecli help for help"
    ;;
  esac
  ;;

port)
  portlist
  ;;

backup)
  backups "${@:2}"
  ;;

update)
  updates
  ;;

help)
  helps
  ;;

version)
  versions
  ;;

*)
  echo "Command not found, type codecli help for help"
  ;;
esac
