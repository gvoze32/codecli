#!/bin/bash
VERSION="2.15"

# ============================== CONSTANTS ==============================

CODE_USERS_DIR="/home/codeusers"
CODE_USERS_MEMLIMIT_DIR="/home/codeusersmemlimit"
DEFAULT_IMAGE="lscr.io/linuxserver/code-server:latest"
SYSTEMD_UNIT_DIR="/lib/systemd/system"
STATE_DIR="/var/lib/codecli"
MIRROR_URL="https://jayanode.com/api/mirror/codecli/codecli?raw=true"
CODE_SERVER_INSTALL_URL="https://code-server.dev/install.sh"
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"

# ============================== HELPERS ==============================

err() { printf '%s\n' "$*" >&2; }
warn() { printf '\033[33mWARN! %s\033[0m\n' "$*" >&2; }

# parse_opts "x:var y:var2" "$@"
# Parses getopts-style options into the caller's (local) variables. Unknown
# options, missing option arguments and stray positional arguments are errors.
parse_opts() {
  local _po_spec="$1" _po_optstring=":" _po_opt _po_item
  local -a _po_items
  shift
  read -ra _po_items <<<"$_po_spec"
  for _po_item in "${_po_items[@]}"; do
    _po_optstring+="${_po_item%%:*}:"
  done

  OPTIND=1
  while getopts "$_po_optstring" _po_opt "$@"; do
    case $_po_opt in
    :)
      err "Option -$OPTARG requires an argument"
      return 1
      ;;
    \?)
      err "Invalid option: -$OPTARG"
      return 1
      ;;
    *)
      for _po_item in "${_po_items[@]}"; do
        if [[ "${_po_item%%:*}" == "$_po_opt" ]]; then
          printf -v "${_po_item#*:}" '%s' "$OPTARG"
        fi
      done
      ;;
    esac
  done

  if ((OPTIND <= $#)); then
    err "Unexpected argument: ${!OPTIND}"
    return 1
  fi
  return 0
}

# ask VAR "Label" [secret]: prompt only when VAR is empty; fail if still empty.
ask() {
  local _ask_var="$1" _ask_label="$2" _ask_secret="${3:-}" _ask_value
  [[ -n "${!_ask_var}" ]] && return 0
  if [[ -n "$_ask_secret" ]]; then
    read -rsp "$_ask_label: " _ask_value || _ask_value=""
    echo >&2
  else
    read -rp "$_ask_label: " _ask_value || _ask_value=""
  fi
  if [[ -z "$_ask_value" ]]; then
    err "$_ask_label is required"
    return 1
  fi
  printf -v "$_ask_var" '%s' "$_ask_value"
}

# ask_optional VAR "Label": prompt only when VAR is empty; empty answer/EOF is fine.
ask_optional() {
  local _ask_var="$1" _ask_value
  [[ -n "${!_ask_var}" ]] && return 0
  read -rp "$2: " _ask_value || _ask_value=""
  printf -v "$_ask_var" '%s' "$_ask_value"
}

valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
valid_memory() { [[ "$1" =~ ^[0-9]+[bBkKmMgG]?$ ]]; }
valid_cpus() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ "$1" =~ [1-9] ]]; }
valid_image() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._/:@-]*$ ]]; }
valid_hour() { [[ "$1" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; }
valid_remote_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; }
# Passwords may hold any printable character except line breaks and the
# single quote (values are single-quoted in the compose env file).
valid_password() { [[ -n "$1" && "$1" != *$'\n'* && "$1" != *$'\r'* ]]; }
valid_docker_password() { valid_password "$1" && [[ "$1" != *"'"* ]]; }

# require_valid CHECK_FN VALUE "description"
require_valid() {
  if ! "$1" "$2"; then
    err "Invalid $3: '$2'"
    return 1
  fi
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    err "Docker is not installed. Run the codecli installer first."
    return 1
  fi
}

server_ip() { curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true; }

# ============================== STORAGE QUOTA ==============================

# Convert 10G / 500M / 0 into 1K blocks (0 = unlimited).
parse_quota_limit() {
  local raw="${1// /}"

  if [[ "$raw" == "0" ]]; then
    echo "0"
    return 0
  fi

  if [[ "$raw" =~ ^([0-9]+)([MmGg])$ ]]; then
    local num=$((10#${BASH_REMATCH[1]}))
    case "${BASH_REMATCH[2]}" in
    M | m) echo $((num * 1024)) ;;
    *) echo $((num * 1024 * 1024)) ;;
    esac
    return 0
  fi

  return 1
}

# ensure_ext4_usrquota_ready MOUNTPOINT PATH
ensure_ext4_usrquota_ready() {
  local mountpoint="$1" target_path="$2" fstype options

  if ! command -v quotacheck >/dev/null 2>&1 || ! command -v quotaon >/dev/null 2>&1 || ! command -v setquota >/dev/null 2>&1; then
    warn "quota tools not found (quotacheck/quotaon/setquota). Install 'quota' package to enable storage limits."
    return 1
  fi

  fstype="$(findmnt -n -o FSTYPE -T "$target_path" 2>/dev/null)"
  if [[ "$fstype" != "ext4" ]]; then
    warn "Filesystem for $target_path is '$fstype' (not ext4). Storage limit skipped."
    return 1
  fi

  options="$(findmnt -n -o OPTIONS -T "$target_path" 2>/dev/null)"
  if [[ ! ",$options," =~ ,(usrquota|usrjquota=[^,]*), ]]; then
    warn "usrquota is not enabled on mount point '$mountpoint'."
    err "      Enable it in /etc/fstab (add 'usrquota') then reboot, or remount with usrquota."
    err "      Storage limit skipped."
    return 1
  fi

  if [[ ! -f "$mountpoint/aquota.user" ]]; then
    echo "Initializing quota files on $mountpoint ..."
    quotacheck -cum "$mountpoint" >/dev/null 2>&1 || true
  fi

  quotaon -u "$mountpoint" >/dev/null 2>&1 || true
  return 0
}

# set_user_storage_quota_for_path HOST_USER LIMIT PATH
set_user_storage_quota_for_path() {
  local q_user="$1" limit_str="$2" ws_path="$3" kb mountpoint

  if [[ -z "$q_user" || -z "$limit_str" || -z "$ws_path" ]]; then
    warn "Missing args for storage limit; skipped."
    return 1
  fi

  if ! kb="$(parse_quota_limit "$limit_str")"; then
    warn "Invalid storage limit '$limit_str' (use e.g. 10G, 500M, 0). Skipped."
    return 1
  fi

  mountpoint="$(findmnt -n -o TARGET -T "$ws_path" 2>/dev/null)"
  if [[ -z "$mountpoint" ]]; then
    warn "Unable to determine mount point for $ws_path. Storage limit skipped."
    return 1
  fi

  ensure_ext4_usrquota_ready "$mountpoint" "$ws_path" || return 1

  if ! id -u "$q_user" >/dev/null 2>&1; then
    warn "No host user '$q_user' exists, so an ext4 user quota cannot be applied. Storage limit skipped."
    return 1
  fi

  if [[ "$kb" == "0" ]]; then
    echo "Setting storage limit: unlimited (quota cleared) for user '$q_user' on $mountpoint"
    setquota -u "$q_user" 0 0 0 0 "$mountpoint" || warn "setquota failed for '$q_user'."
    return 0
  fi

  echo "Setting storage limit: $limit_str for user '$q_user' on $mountpoint"
  setquota -u "$q_user" "$kb" "$kb" 0 0 "$mountpoint" || warn "setquota failed for '$q_user'."
  return 0
}

# ============================== UPDATES ==============================

# remote_version: latest version string published on the mirror (empty on failure).
remote_version() {
  curl -fsS --connect-timeout 10 --max-time 20 "$MIRROR_URL" 2>/dev/null |
    grep -o -m1 'VERSION="[0-9]*\.[0-9]*"' | cut -d '"' -f 2
}

check_update() {
  local latest_version
  echo "Checking for available updates..."
  latest_version="$(remote_version)"
  if [[ -z "$latest_version" ]]; then
    echo "Failed to check for updates."
    return 1
  fi
  if [[ "$latest_version" != "$VERSION" ]]; then
    echo "New version available: v$latest_version (current: v$VERSION)"
    echo "Run 'codecli update' to update."
  else
    echo "You are using the latest version (v$VERSION)."
  fi
}

# Daily update notice, only for interactive use so provisioning stays silent and fast.
maybe_check_update() {
  local now last=0 stamp="$STATE_DIR/last_check"
  [[ -t 1 ]] || return 0
  [[ "$1" == "update" ]] && return 0
  mkdir -p "$STATE_DIR" 2>/dev/null && chmod 755 "$STATE_DIR" 2>/dev/null || return 0

  now="$(date +%s)"
  [[ -f "$stamp" ]] && last="$(cat "$stamp" 2>/dev/null)"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  if ((now - last > 86400)); then
    echo "$now" >"$stamp" 2>/dev/null
    check_update || true
  fi
}

updates() {
  local attempt max_attempts=3 tmp latest_version

  echo "Checking for updates..."
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    tmp="$(mktemp)" || return 1

    if curl -fsSL --connect-timeout 10 --max-time 60 "$MIRROR_URL" -o "$tmp" && [[ -s "$tmp" ]]; then
      latest_version="$(grep -o -m1 'VERSION="[0-9]*\.[0-9]*"' "$tmp" | cut -d '"' -f 2)"
      if [[ -z "$latest_version" ]] || ! bash -n "$tmp" 2>/dev/null; then
        echo "Downloaded file appears to be invalid. Update aborted."
      elif [[ "$latest_version" == "$VERSION" ]]; then
        rm -f "$tmp"
        echo "You are already using the latest version ($VERSION)."
        return 0
      else
        echo "Updating to version $latest_version..."
        if install -m 0755 "$tmp" /usr/local/bin/codecli; then
          rm -f "$tmp"
          echo "Successfully updated to version $latest_version!"
          return 0
        fi
        echo "Failed to install the update. Please check permissions and try again."
      fi
    else
      echo "Failed to download update (attempt $attempt of $max_attempts)."
    fi

    rm -f "$tmp"
    ((attempt < max_attempts)) && sleep 2
  done

  echo "Failed to update after $max_attempts attempts."
  return 1
}

# ============================== INFO ==============================

banner() {
  cat <<'EOF'
               _           _ _ 
              | |         | (_)
  ___ ___   __| | ___  ___| |_ 
 / __/ _ \ / _' |/ _ \/ __| | |
| (_| (_) | (_| |  __/ (__| | |
 \___\___/ \__,_|\___|\___|_|_|

====  CODE-SERVER CLI MANAGER  ====

EOF
}

about() {
  cat <<EOF
Name of File  : codecli.sh
Version       : $VERSION
Tested on     :
    - Ubuntu  : 22.04, 24.04, 26.04

Built with love♡ by gvoze32
EOF
}

bantuan() {
  cat <<'EOF'
How to use:
codecli must be run as root
codecli [command] [argument] [argument]

Command Lists:
quickcreate         : Quick create code server workspace in root
  restart           : Restart quick created code server
  fix               : Fix quick created code server installation
  status            : Check status of quick created code server
  stop              : Stop quick created code server
create
  systemd           : Create a new SystemD workspace
  systemdlimit      : Create a new SystemD workspace with limited RAM
  docker            : Create a new Docker container
  dockerlimit       : Create a new Docker container with limited RAM
manage
  systemd
    stop            : Stop workspace
    start           : Start workspace
    delete          : Delete workspace
    status          : Show workspace status
    restart         : Restart workspace
    password        : Change user password
    schedule        : Schedule workspace deletion
    scheduled       : Show scheduled workspace deletion
    convert         : Convert user to superuser
  docker
    stop            : Stop Docker container
    start           : Start Docker container
    delete          : Delete Docker container
    status          : Show container status
    restart         : Restart running containers
    restartall      : Restart (all) running containers
    reset           : Reset Docker container
    password        : Change user password, port & update limited RAM for dockerlimit
    schedule        : Schedule container stop
    scheduled       : Show scheduled container jobs
    list            : Show Docker container lists
    configure       : Stop, start or restart running container
port                : Show used port lists
backup              : Backup workspace data with Rclone (Docker only)
update              : Update code server to the latest version
help                : Show help
version             : Show version

Options:
-u                  : Username
-p                  : Password
-o                  : Port number
-l                  : Memory limit (e.g., 1024m)
-c                  : CPU limit (e.g., 10% for systemd or 1.0 for Docker)
-i                  : Image (e.g., lscr.io/linuxserver/code-server:latest)
-t                  : Type (e.g., 1 for Docker, 2 for Docker Memory Limit)
-q                  : Storage limit for workspace (ext4 quota, e.g., 10G / 500M; 0=unlimited)
-n                  : Rclone remote name
-h                  : Backup hour
-f                  : Backup folder name
-s                  : Backup service provider
-a                  : Additional folder/file (repeatable)

Copyright (c) 2024 codecli (under MIT License)
Built with love♡ by gvoze32
EOF
}

helps() {
  banner
  bantuan
}

versions() {
  banner
  about
}

# ============================== SYSTEMD ==============================

unit_file() { echo "$SYSTEMD_UNIT_DIR/code-$1.service"; }

# Escape a value for use inside a double-quoted systemd Environment= assignment.
systemd_escape_value() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  v="${v//%/%%}"
  printf '%s' "$v"
}

# Validate USER and make sure it is a codecli systemd workspace.
require_systemd_workspace() {
  require_valid valid_name "$1" "username" || return 1
  if [[ ! -f "$(unit_file "$1")" ]]; then
    err "No codecli systemd workspace found for user '$1'"
    return 1
  fi
}

restart_systemd_unit() {
  systemctl daemon-reload
  systemctl enable "code-$1.service"
  systemctl restart "code-$1.service"
  sleep 10
  systemctl status --no-pager "code-$1.service"
}

install_code_server() {
  local tmp rc
  tmp="$(mktemp)" || return 1
  if ! curl -fsSL --proto '=https' --tlsv1.2 "$CODE_SERVER_INSTALL_URL" -o "$tmp"; then
    rm -f "$tmp"
    err "Failed to download the code-server installer."
    return 1
  fi
  sh "$tmp"
  rc=$?
  rm -f "$tmp"
  return $rc
}

# write_systemd_unit USER PASSWORD PORT [MEMORY CPU]
write_systemd_unit() {
  local user="$1" password="$2" port="$3" limits="" unit
  unit="$(unit_file "$user")"
  if [[ -n "${4:-}" ]]; then
    limits=$'MemoryMax='"$4"$'\nCPUQuota='"$5"$'\n'
  fi

  (
    umask 077
    cat >"$unit" <<EOF
[Unit]
Description=code-server for $user
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:$port --user-data-dir /home/$user/.local/share/code-server --auth password
User=$user
Group=$user

UMask=0002
${limits}Restart=on-failure

WorkingDirectory=/home/$user/workspace
Environment="PASSWORD=$(systemd_escape_value "$password")"

StandardOutput=journal
StandardError=journal
SyslogIdentifier=code-$user

[Install]
WantedBy=multi-user.target
EOF
  )
}

# create_systemd plain|limit args...
create_systemd() {
  local mode="$1" user="" password="" port="" limit="" cpu_limit="" spec="u:user p:password o:port" cpu_value
  shift
  [[ "$mode" == "limit" ]] && spec+=" l:limit c:cpu_limit"
  parse_opts "$spec" "$@" || return 1

  ask user "Username" || return 1
  ask password "Password" secret || return 1
  ask port "Port" || return 1
  require_valid valid_name "$user" "username" || return 1
  require_valid valid_password "$password" "password" || return 1
  require_valid valid_port "$port" "port" || return 1
  if [[ "$mode" == "limit" ]]; then
    ask limit "Memory Limit (e.g., 1024m)" || return 1
    ask cpu_limit "CPU Limit (e.g., 10%)" || return 1
    require_valid valid_memory "$limit" "memory limit" || return 1
    limit="${limit^^}"
    limit="${limit%B}"
    if [[ "$cpu_limit" =~ ^[0-9]+(\.[0-9]+)?%$ ]]; then
      cpu_value="$cpu_limit"
    elif valid_cpus "$cpu_limit"; then
      cpu_value="$(awk -v c="$cpu_limit" 'BEGIN { printf "%d%%", c * 100 }')"
    else
      err "Invalid CPU limit: '$cpu_limit'"
      return 1
    fi
  fi

  if id -u "$user" >/dev/null 2>&1; then
    err "User '$user' already exists"
    return 1
  fi

  adduser --disabled-password --gecos "" "$user" || return 1
  printf '%s:%s\n' "$user" "$password" | chpasswd || return 1
  chmod 700 "/home/$user"
  install -d -o "$user" -g "$user" -m 700 "/home/$user/workspace"

  if ! command -v code-server >/dev/null 2>&1; then
    install_code_server || return 1
  fi

  if [[ "$mode" == "limit" ]]; then
    write_systemd_unit "$user" "$password" "$port" "$limit" "$cpu_value"
  else
    write_systemd_unit "$user" "$password" "$port"
  fi

  restart_systemd_unit "$user"
}

createnewsystemd() { create_systemd plain "$@"; }
createnewsystemdlimit() { create_systemd limit "$@"; }

# systemd_user_action ACTION args... (ACTION: stop|start|status|restart|convert|delete)
systemd_user_action() {
  local action="$1" user=""
  shift
  parse_opts "u:user" "$@" || return 1
  ask user "Input User" || return 1
  require_systemd_workspace "$user" || return 1

  case "$action" in
  stop | start) systemctl "$action" "code-$user.service" ;;
  status) systemctl status --no-pager "code-$user.service" ;;
  restart) restart_systemd_unit "$user" ;;
  convert)
    echo "Input user password"
    passwd "$user" || return 1
    echo "Warning, code-server will be restart!"
    usermod -aG sudo "$user" || return 1
    restart_systemd_unit "$user"
    ;;
  delete)
    systemctl stop "code-$user.service"
    systemctl disable "code-$user.service" >/dev/null 2>&1
    pkill -KILL -u "$user"
    sleep 3
    if ! userdel "$user"; then
      err "Failed to remove user '$user'; workspace files were kept."
      return 1
    fi
    rm -rf -- "/home/${user:?}"
    rm -f -- "$(unit_file "$user")"
    systemctl daemon-reload
    ;;
  esac
}

stopsystemd() { systemd_user_action stop "$@"; }
startsystemd() { systemd_user_action start "$@"; }
deletesystemd() { systemd_user_action delete "$@"; }
statussystemd() { systemd_user_action status "$@"; }
restartsystemd() { systemd_user_action restart "$@"; }
convertsystemd() { systemd_user_action convert "$@"; }

# replace_line_prefix FILE PREFIX NEWLINE: rewrite the lines starting with PREFIX.
replace_line_prefix() {
  local file="$1" prefix="$2" replacement="$3" tmp line
  tmp="$(mktemp "$file.XXXXXX")" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$prefix"* ]]; then
      printf '%s\n' "$replacement"
    else
      printf '%s\n' "$line"
    fi
  done <"$file" >"$tmp"
  chmod --reference="$file" "$tmp" 2>/dev/null
  mv -f "$tmp" "$file"
}

changepasswordsystemd() {
  local user="" password="" port="" unit line
  parse_opts "u:user p:password o:port" "$@" || return 1

  ask user "Input User" || return 1
  require_systemd_workspace "$user" || return 1
  ask password "Input New Password" secret || return 1
  ask_optional port "Input New Port"
  require_valid valid_password "$password" "password" || return 1
  [[ -z "$port" ]] || require_valid valid_port "$port" "port" || return 1

  unit="$(unit_file "$user")"
  replace_line_prefix "$unit" "Environment=" "Environment=\"PASSWORD=$(systemd_escape_value "$password")\"" || return 1

  if [[ -n "$port" ]]; then
    line="$(grep -m1 '^ExecStart=' "$unit")"
    replace_line_prefix "$unit" "ExecStart=" "$(sed "s/--bind-addr 0\.0\.0\.0:[0-9]*/--bind-addr 0.0.0.0:$port/" <<<"$line")" || return 1
  fi

  systemctl daemon-reload
  systemctl restart "code-$user.service"
  sleep 10
  systemctl status --no-pager "code-$user.service"
}

# ============================== SCHEDULING ==============================

# ask_schedule_time VAR: show the `at` time examples and read the time into VAR.
ask_schedule_time() {
  cat <<'EOF'
 
Format Example for Time: 
 
10:00 AM 6/22/2015
10:00 AM July 25
10:00 AM
10:00 AM Sun
10:00 AM next month
10:00 AM tomorrow
now + 1 hour
now + 30 minutes
now + 1 week
now + 1 year
midnight
 
EOF
  ask "$1" "Time"
}

# schedule_job WHEN args...: run "codecli args..." through at(1).
schedule_job() {
  local when="$1"
  shift
  if ! command -v at >/dev/null 2>&1; then
    err "The 'at' package is not installed."
    return 1
  fi
  printf '%q ' "$SELF" "$@" | at "$when"
}

schedulesystemd() {
  local user="" waktu=""
  parse_opts "u:user" "$@" || return 1
  ask user "Input User" || return 1
  require_systemd_workspace "$user" || return 1
  ask_schedule_time waktu || return 1
  schedule_job "$waktu" manage systemd delete -u "$user"
}

scheduledatq() {
  atq
}

# ============================== DOCKER ==============================

# resolve_docker_type: sets caller's dtype (1|2) and base_dir from dtype or a prompt.
# Callers declare `local dtype base_dir`; assignments here use bash dynamic scoping.
# shellcheck disable=SC2154
resolve_docker_type() {
  if [[ -z "$dtype" ]]; then
    {
      echo "Is this workspace using Docker or Docker Memory Limit?"
      echo "1. Docker"
      echo "2. Docker Memory Limit"
    } >&2
    read -r -p "Choose: " dtype || dtype=""
  fi

  case "$dtype" in
  1) base_dir="$CODE_USERS_DIR" ;;
  2) base_dir="$CODE_USERS_MEMLIMIT_DIR" ;;
  *)
    err "Invalid option"
    return 1
    ;;
  esac

  if [[ ! -f "$base_dir/docker-compose.yml" ]]; then
    err "$base_dir/docker-compose.yml not found. Run the codecli installer first."
    return 1
  fi
}

# Per-workspace compose settings live in a private root-only directory so each
# workspace keeps its own port/password/limits and secrets are never world readable.
workspace_env_file() { echo "$1/.env.d/$2.env"; }

# env_file_value FILE KEY
env_file_value() {
  local v
  v="$(sed -n "s/^$2=//p" "$1" 2>/dev/null | sed -n '1p')"
  v="${v#\'}"
  v="${v%\'}"
  printf '%s' "$v"
}

# write_workspace_env BASE USER PORT PASSWORD IMAGE [MEMORY CPU]
write_workspace_env() {
  local base="$1" user="$2" envd="$1/.env.d" tmp
  install -d -m 700 "$envd" || return 1
  tmp="$(mktemp "$envd/.tmp.XXXXXX")" || return 1
  {
    printf 'PORT=%s\n' "$3"
    printf 'NAMA_PELANGGAN=%s\n' "$user"
    printf "PASSWORD_PELANGGAN='%s'\n" "$4"
    printf 'DOCKER_IMAGE=%s\n' "$5"
    if [[ -n "${6:-}" ]]; then
      printf 'MEMORY=%s\n' "$6"
      printf 'CPU_LIMIT=%s\n' "$7"
    fi
  } >"$tmp"
  mv -f "$tmp" "$(workspace_env_file "$base" "$user")"
}

# compose_run BASE USER compose-args...: run compose for one workspace.
# Falls back to the legacy shared BASE/.env for workspaces created by older versions.
compose_run() {
  local base="$1" user="$2" envf
  shift 2
  envf="$(workspace_env_file "$base" "$user")"
  [[ -f "$envf" ]] || envf="$base/.env"
  if [[ -f "$envf" ]]; then
    (cd "$base" && docker compose -p "$user" --env-file "$envf" "$@")
  else
    (cd "$base" && docker compose -p "$user" "$@")
  fi
}

# Your custom default bundling files go here (cwd is the workspace directory,
# $1 is the username). It's recommended to put assets in the resources directory.
bundle_default_files() {
  ### START

  ### END
  :
}

# post_create_workspace BASE USER STORAGE_LIMIT
post_create_workspace() {
  local base="$1" user="$2" storage_limit="$3" workspace_path

  if [[ ! -d "$base/$user" ]]; then
    warn "Workspace directory not found - Ignore this message if you are not adding default bundling files"
    return 0
  fi

  if [[ -n "$storage_limit" ]]; then
    set_user_storage_quota_for_path "$user" "$storage_limit" "$base/$user" || true
  fi

  workspace_path="$base/$user/workspace"
  [[ -d "$workspace_path" ]] || workspace_path="$base/$user/config/workspace"

  if [[ -d "$workspace_path" ]]; then
    (cd "$workspace_path" && bundle_default_files "$user")
  else
    warn "Default workspace directory not found - skipping custom bundling files"
  fi
}

# create_docker plain|limit args...
create_docker() {
  local mode="$1" user="" password="" port="" image="" storage_limit="" limit="" cpu_limit=""
  local base_dir="$CODE_USERS_DIR" spec="u:user p:password o:port i:image q:storage_limit" rc
  shift
  if [[ "$mode" == "limit" ]]; then
    base_dir="$CODE_USERS_MEMLIMIT_DIR"
    spec+=" l:limit c:cpu_limit"
  fi
  parse_opts "$spec" "$@" || return 1

  ask user "Username" || return 1
  ask password "Password" secret || return 1
  ask port "Port" || return 1
  if [[ "$mode" == "limit" ]]; then
    ask limit "Memory Limit (e.g., 1024m)" || return 1
    ask cpu_limit "CPU Limit (e.g., 1.0 for 1 core)" || return 1
  fi
  if [[ -z "$image" ]]; then
    echo "Using default image"
    image="$DEFAULT_IMAGE"
  else
    echo "Using provided image: $image"
  fi
  ask_optional storage_limit "Storage Limit (ext4 quota, e.g., 10G; 0=unlimited, blank=skip)"

  require_valid valid_name "$user" "username" || return 1
  require_valid valid_docker_password "$password" "password (must not contain ' or line breaks)" || return 1
  require_valid valid_port "$port" "port" || return 1
  require_valid valid_image "$image" "image" || return 1
  if [[ "$mode" == "limit" ]]; then
    require_valid valid_memory "$limit" "memory limit" || return 1
    require_valid valid_cpus "$cpu_limit" "CPU limit" || return 1
  fi
  if [[ -n "$storage_limit" ]]; then
    parse_quota_limit "$storage_limit" >/dev/null || {
      err "Invalid storage limit: '$storage_limit' (use e.g. 10G, 500M, 0)"
      return 1
    }
  fi
  require_docker || return 1
  if [[ ! -f "$base_dir/docker-compose.yml" ]]; then
    err "$base_dir/docker-compose.yml not found. Run the codecli installer first."
    return 1
  fi

  echo
  if [[ "$mode" == "limit" ]]; then
    echo "Creating docker container with memory limit:"
  else
    echo "Creating docker container:"
  fi
  echo "Username: $user"
  echo "Port: $port"
  [[ "$mode" == "limit" ]] && {
    echo "Memory Limit: $limit"
    echo "CPU Limit: $cpu_limit"
  }
  echo "Image: $image"
  [[ -n "$storage_limit" ]] && echo "Storage Limit: $storage_limit"

  if [[ "$mode" == "limit" ]]; then
    write_workspace_env "$base_dir" "$user" "$port" "$password" "$image" "$limit" "$cpu_limit" || return 1
  else
    write_workspace_env "$base_dir" "$user" "$port" "$password" "$image" || return 1
  fi

  compose_run "$base_dir" "$user" up -d
  rc=$?
  if ((rc != 0)); then
    err "docker compose up failed for '$user' (exit $rc)"
    return $rc
  fi

  post_create_workspace "$base_dir" "$user" "$storage_limit"
}

createnewdocker() { create_docker plain "$@"; }
createnewdockermemlimit() { create_docker limit "$@"; }

# docker_user_action ACTION args... (ACTION: stop|start|delete|reset)
docker_user_action() {
  local action="$1" user="" dtype="" base_dir=""
  shift
  parse_opts "u:user t:dtype" "$@" || return 1

  ask user "Input User" || return 1
  require_valid valid_name "$user" "username" || return 1
  require_docker || return 1
  resolve_docker_type || return 1

  case "$action" in
  stop | start)
    compose_run "$base_dir" "$user" "$action"
    ;;
  delete)
    if ! compose_run "$base_dir" "$user" down; then
      warn "docker compose down failed; removing container code-$user directly"
      docker rm -f "code-$user" >/dev/null 2>&1
      if docker container inspect "code-$user" >/dev/null 2>&1; then
        err "Container code-$user could not be removed; workspace files were kept."
        return 1
      fi
    fi
    rm -f -- "$(workspace_env_file "$base_dir" "$user")"
    rm -rf -- "${base_dir:?}/$user"
    ;;
  reset)
    if [[ ! -f "$(workspace_env_file "$base_dir" "$user")" ]] &&
      ! grep -qxF "NAMA_PELANGGAN=$user" "$base_dir/.env" 2>/dev/null; then
      err "No saved settings found for '$user'. Run 'codecli manage docker password -u $user' to regenerate them."
      return 1
    fi
    compose_run "$base_dir" "$user" down || return 1
    compose_run "$base_dir" "$user" up -d
    ;;
  esac
}

stopdocker() { docker_user_action stop "$@"; }
startdocker() { docker_user_action start "$@"; }
deletedocker() { docker_user_action delete "$@"; }
resetdocker() { docker_user_action reset "$@"; }

listdocker() {
  docker ps
}

statusdocker() {
  docker stats
}

changepassworddocker() {
  local user="" newpw="" dtype="" port="" mem="" cpu_limit="" image="" base_dir="" envf

  parse_opts "u:user p:newpw t:dtype o:port l:mem c:cpu_limit i:image" "$@" || return 1

  ask user "Input Username" || return 1
  require_valid valid_name "$user" "username" || return 1
  ask newpw "Input New Password" secret || return 1
  require_docker || return 1
  resolve_docker_type || return 1
  require_valid valid_docker_password "$newpw" "password (must not contain ' or line breaks)" || return 1

  if [[ ! -d "$base_dir/$user" ]]; then
    err "User $user does not exist or workspace directory not found"
    return 1
  fi

  envf="$(workspace_env_file "$base_dir" "$user")"
  if [[ -f "$envf" ]]; then
    [[ -n "$port" ]] || port="$(env_file_value "$envf" PORT)"
    [[ -n "$image" ]] || image="$(env_file_value "$envf" DOCKER_IMAGE)"
    if [[ "$dtype" == "2" ]]; then
      [[ -n "$mem" ]] || mem="$(env_file_value "$envf" MEMORY)"
      [[ -n "$cpu_limit" ]] || cpu_limit="$(env_file_value "$envf" CPU_LIMIT)"
    fi
  fi
  [[ -n "$image" ]] || image="$(docker inspect --format '{{.Config.Image}}' "code-$user" 2>/dev/null)"
  [[ -n "$image" ]] || image="$DEFAULT_IMAGE"

  ask port "Input Port" || return 1
  require_valid valid_port "$port" "port" || return 1
  require_valid valid_image "$image" "image" || return 1

  if [[ "$dtype" == "2" ]]; then
    ask mem "Memory Limit (e.g., 1024m)" || return 1
    ask cpu_limit "CPU Limit (e.g., 1.0 for 1 core)" || return 1
    require_valid valid_memory "$mem" "memory limit" || return 1
    require_valid valid_cpus "$cpu_limit" "CPU limit" || return 1
    write_workspace_env "$base_dir" "$user" "$port" "$newpw" "$image" "$mem" "$cpu_limit" || return 1
  else
    write_workspace_env "$base_dir" "$user" "$port" "$newpw" "$image" || return 1
  fi

  echo "Password, port and .env updated for user $user"
  compose_run "$base_dir" "$user" down || return 1
  compose_run "$base_dir" "$user" up -d || return 1
  echo "Docker container recreated for user $user"
}

scheduledocker() {
  local user="" dtype="" base_dir="" waktu=""
  parse_opts "u:user t:dtype" "$@" || return 1

  ask user "Input User" || return 1
  require_valid valid_name "$user" "username" || return 1
  resolve_docker_type || return 1
  ask_schedule_time waktu || return 1
  schedule_job "$waktu" manage docker stop -u "$user" -t "$dtype"
}

configuredocker() {
  local user="" action=""
  read -rp "Input User: " user
  require_valid valid_name "$user" "username" || return 1
  require_docker || return 1
  if ! docker container inspect "code-$user" >/dev/null 2>&1; then
    err "Container code-$user not found"
    return 1
  fi

  echo "1. Stop"
  echo "2. Start"
  echo "3. Restart"
  read -r -p "Choose: " action
  case "$action" in
  1) docker container stop "code-$user" ;;
  2) docker container start "code-$user" ;;
  *) docker container restart "code-$user" ;;
  esac
}

restartdocker() {
  local user="" dtype="" containers
  # -t is accepted (and ignored) so every "manage docker <action>" call can pass it.
  parse_opts "u:user t:dtype" "$@" || return 1
  require_docker || return 1

  if [[ -z "$user" ]]; then
    containers="$(docker ps --format '{{.Names}}')"
    echo "Container lists:"
    sed 's/^code-//' <<<"$containers"
    ask user "Input User" || return 1
  fi
  require_valid valid_name "$user" "username" || return 1

  if ! docker container inspect "code-$user" >/dev/null 2>&1; then
    err "Container name 'code-$user' invalid. Make sure the name is correct."
    return 1
  fi

  if docker restart "code-$user"; then
    echo "Container 'code-$user' restarted successfully."
  else
    err "Container restart 'code-$user' failed."
    return 1
  fi
}

restartdockerall() {
  local -a running
  mapfile -t running < <(docker ps -q)
  if ((${#running[@]} > 0)); then
    docker restart "${running[@]}"
  else
    echo "No running containers to restart."
  fi
}

# ============================== BACKUP ==============================

# Body of the generated backup script (the header defines remote_path,
# log_file, lock_file and additional_paths).
backup_script_body() {
  cat <<'EOF'

date=$(date +%Y%m%d)
umask 077

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$log_file"
}

exec 9>"$lock_file"
if ! flock -n 9; then
    log_message "Another backup is still running, exiting"
    exit 0
fi

resolve_additional_path() {
    local configured_path="$1"
    configured_path="${configured_path//\{folder\}/$folder}"
    configured_path="${configured_path//\{user\}/$user}"
    printf '%s' "$configured_path"
}

should_skip_additional_folder() {
    local candidate="$1"
    local configured_path=""
    local additional_pattern=""

    for configured_path in "${additional_paths[@]}"; do
        additional_pattern="${configured_path//\{folder\}/*}"
        additional_pattern="${additional_pattern//\{user\}/*}"
        # shellcheck disable=SC2053  # the configured path is intentionally a glob pattern
        if [[ "$candidate" == $additional_pattern || "$candidate" == ${additional_pattern}/ ]]; then
            return 0
        fi
    done

    return 1
}

verify_backup() {
    local folder="$1"
    local user="$2"
    local new_file="$folder-$user-$date.zip"
    local retry_count=3
    local retry_delay=5
    local i

    for ((i=1; i<=retry_count; i++)); do
        log_message "Verification attempt $i of $retry_count for $new_file"

        if rclone lsf "$remote_path/$new_file" &>/dev/null; then
            log_message "File $new_file verified in remote"
            return 0
        fi

        log_message "WARNING: $new_file not found in remote"
        if [ "$i" -lt "$retry_count" ]; then
            log_message "Retrying in $retry_delay seconds..."
            sleep "$retry_delay"
        fi
    done

    return 1
}

cleanup_old_backup() {
    local folder="$1"
    local user="$2"
    local backup_files files_to_delete backup_count file

    log_message "Checking for old backup files for $folder-$user"

    backup_files=$(rclone lsf "$remote_path" --include "$folder-$user-*.zip" | sort -r)
    backup_count=$(printf '%s\n' "$backup_files" | sed '/^$/d' | wc -l)

    if [ "$backup_count" -gt 2 ]; then
        log_message "Keeping last 2 backups for $folder-$user"
        files_to_delete=$(printf '%s\n' "$backup_files" | tail -n +3)

        while IFS= read -r file; do
            if [ -n "$file" ]; then
                log_message "Deleting old backup: $file"
                rclone delete "$remote_path/$file" >> "$log_file" 2>&1
            fi
        done <<< "$files_to_delete"
    else
        log_message "Less than or equal to 2 backups found for $folder-$user, no cleanup needed"
    fi
}

log_message "Starting backup process"

mkdir -p /home/backup
chmod 700 /home/backup
trap 'rm -rf /home/backup' EXIT

for folder in codeusers codeusersmemlimit; do
    if [ ! -d "/home/$folder" ]; then
        log_message "Folder $folder not found, skipping"
        continue
    fi

    log_message "Processing $folder"
    cd "/home/$folder" || continue
    for user_folder in */; do
        if [ ! -d "$user_folder" ]; then
            continue
        fi
        if should_skip_additional_folder "$user_folder"; then
            log_message "Skipping additional folder $user_folder"
            continue
        fi

        user=${user_folder%/}
        archive="/home/backup/$folder-$user-$date.zip"
        log_message "Backing up $user from $folder"

        zip_sources=("$user_folder")
        for additional_path in "${additional_paths[@]}"; do
            resolved_path="$(resolve_additional_path "$additional_path")"
            if [ -e "$resolved_path" ]; then
                zip_sources+=("$resolved_path")
                log_message "Including additional path $resolved_path"
            else
                log_message "WARNING: Additional path $resolved_path not found"
            fi
        done

        if ! zip -r "$archive" "${zip_sources[@]}" -x "*/workspace/.vscode-server/*" -x "*/node_modules/*" >> "$log_file" 2>&1; then
            log_message "ERROR: Failed to create zip for $user in $folder"
            rm -f "$archive"
            continue
        fi

        log_message "Uploading backup for $folder-$user"
        max_retries=3
        retry_count=0
        upload_success=false

        while [ "$retry_count" -lt "$max_retries" ]; do
            log_message "Upload attempt $((retry_count + 1)) of $max_retries"

            if rclone copy "$archive" "$remote_path/" >> "$log_file" 2>&1; then
                if verify_backup "$folder" "$user"; then
                    upload_success=true
                    break
                fi
            fi

            retry_count=$((retry_count + 1))
            if [ "$retry_count" -lt "$max_retries" ]; then
                log_message "Retry in 30 seconds..."
                sleep 30
            fi
        done

        if [ "$upload_success" = true ]; then
            log_message "Backup successfully uploaded for $folder-$user"
            cleanup_old_backup "$folder" "$user"
        else
            log_message "ERROR: Backup failed for $folder-$user after $max_retries attempts"
        fi

        log_message "Removing local backup file for $folder-$user"
        rm -f "$archive"
    done
done

log_message "Removing local backup directory"
rm -rf /home/backup >> "$log_file" 2>&1

log_message "Backup process completed"
EOF
}

# install_cron_entry LINE MARKER: add LINE to root's crontab, replacing earlier lines containing MARKER.
install_cron_entry() {
  local tmp
  tmp="$(mktemp)" || return 1
  { crontab -l 2>/dev/null || true; } | grep -vF -- "$2" >"$tmp" || true
  printf '%s\n' "$1" >>"$tmp"
  if crontab "$tmp"; then
    rm -f "$tmp"
  else
    rm -f "$tmp"
    return 1
  fi
}

backups() {
  local name="" hour="" cloud_folder="" service="" opt
  local -a additional_paths=()

  OPTIND=1
  while getopts ":n:h:f:s:a:" opt; do
    case $opt in
    n) name="$OPTARG" ;;
    h) hour="$OPTARG" ;;
    f) cloud_folder="$OPTARG" ;;
    s) service="$OPTARG" ;;
    a)
      if [[ -z "$OPTARG" || "$OPTARG" == -* ]]; then
        err "Invalid additional folder/file path"
        return 1
      fi
      additional_paths+=("$OPTARG")
      ;;
    :)
      err "Option -$OPTARG requires an argument"
      return 1
      ;;
    *)
      err "Invalid option: -$OPTARG"
      return 1
      ;;
    esac
  done

  echo "Scheduled Backup - WARNING: This script currently only supports backup for codeusers and codeusersmemlimit docker containers"
  echo "Make sure you have set up an rclone config file using command: rclone config"
  echo "If your storage is bucket type, then name the rclone config name same as your bucket name"
  echo ""
  ask name "If all has been set up correctly, then input your rclone remote name" || return 1
  ask hour "Enter the time for backup (hour 0-23)" || return 1
  ask cloud_folder "Define the backup folder name on the cloud" || return 1
  if [[ -z "$service" ]]; then
    echo ""
    echo "Choose the backup service provider"
    echo "1. Google Drive"
    echo "2. Storj"
    echo "3. Backblaze B2"
    echo "4. pCloud"
    echo "5. Jottacloud"
    read -r -p "Choose: " service || service=""
  fi
  case "$service" in
  1 | 2 | 3 | 4 | 5) ;;
  *)
    err "Invalid option"
    return 1
    ;;
  esac
  require_valid valid_remote_name "$name" "rclone remote name" || return 1
  require_valid valid_hour "$hour" "backup hour" || return 1

  local script="/home/backup-$name-cs.sh"
  local log_file="/home/backup-$name-cs.log"
  local additional_path

  {
    echo "#!/bin/bash"
    printf 'remote_path=%q\n' "$name:$cloud_folder"
    printf 'log_file=%q\n' "$log_file"
    printf 'lock_file=%q\n' "/var/lock/codecli-backup-$name.lock"
    echo "additional_paths=("
    for additional_path in "${additional_paths[@]}"; do
      printf '  %q\n' "$additional_path"
    done
    echo ")"
    backup_script_body
  } >"$script"
  chmod 700 "$script"

  echo ""
  echo "Backup command created"

  install_cron_entry "0 $hour * * * $script >> $log_file 2>&1" "$script" || return 1

  echo ""
  echo "Cron job created"
  echo ""
  echo "Make sure it's included in your cron list:"
  crontab -l
  echo "Backup rule successfully added"
}

# ============================== PORTS ==============================

portlist() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -i -P -n | grep LISTEN
  else
    ss -Hltnup
  fi
}

# ============================== QUICKCREATE ==============================

QUICKCREATE_CONF="/root/.codecli/quickcreate.conf"
QUICKCREATE_CONFIG_YAML="/root/.config/code-server/config.yaml"
QUICKCREATE_WORKSPACE="/root/workspace"

# yaml_single_quote VALUE: YAML single-quoted scalar.
yaml_single_quote() {
  local q="'" v
  v="${1//$q/$q$q}"
  printf "'%s'" "$v"
}

show_access_url() {
  echo -e "Access Code-Server IDE at: http://$(server_ip):8080"
}

# require_quickcreate_conf: load the saved password into the caller's `password`.
require_quickcreate_conf() {
  if [[ ! -f "$QUICKCREATE_CONF" ]]; then
    err "Configuration file not found. Please run 'codecli quickcreate' first."
    return 1
  fi
  password="$(sed -n 's/^PASSWORD=//p' "$QUICKCREATE_CONF" | sed -n '1p')"
}

write_quickcreate_config() {
  mkdir -p "$(dirname "$QUICKCREATE_CONFIG_YAML")"
  (
    umask 077
    cat >"$QUICKCREATE_CONFIG_YAML" <<EOF
bind-addr: 0.0.0.0:8080
auth: password
password: $(yaml_single_quote "$1")
cert: false
user-data-dir: /var/lib/code-server
EOF
  )
}

quickcreatecode() {
  local password=""
  echo -e "Starting Quick Code-Server Installation..."
  echo "Server IP: $(server_ip)"

  mkdir -p "$QUICKCREATE_WORKSPACE"

  ask password "Enter password for Code-Server" secret || return 1
  require_valid valid_password "$password" "password" || return 1

  mkdir -p "$(dirname "$QUICKCREATE_CONF")"
  chmod 700 "$(dirname "$QUICKCREATE_CONF")"
  (
    umask 077
    printf 'PASSWORD=%s\n' "$password" >"$QUICKCREATE_CONF"
  )

  echo "Installing Code-Server..."
  install_code_server || return 1
  write_quickcreate_config "$password"

  echo "Starting Code-Server using systemd..."
  systemctl enable --now code-server@root || return 1

  echo -e "Quick Code-Server Installation Complete!"
  show_access_url
}

restartquickcreate() {
  local password=""
  echo -e "Restarting Code-Server..."
  echo "Server IP: $(server_ip)"
  require_quickcreate_conf || return 1

  echo "Restarting Code-Server using systemd..."
  systemctl restart code-server@root || return 1

  echo -e "Code-Server Successfully Restarted!"
  show_access_url
}

fixquickcreate() {
  local password=""
  echo "Fixing Code-Server..."
  require_quickcreate_conf || return 1

  echo "Stopping Code-Server..."
  systemctl stop code-server@root

  echo "Reinstalling Code-Server..."
  install_code_server || return 1
  write_quickcreate_config "$password"

  echo "Restarting Code-Server using systemd..."
  systemctl enable --now code-server@root || return 1

  echo -e "Code-Server Fix Complete!"
  show_access_url
}

statusquickcreate() {
  local password=""
  echo -e "Checking Code-Server Status..."
  echo "Server IP: $(server_ip)"
  require_quickcreate_conf || return 1

  echo "Checking Code-Server status using systemd..."
  systemctl status --no-pager code-server@root

  echo
  show_access_url
}

stopquickcreate() {
  local password=""
  echo -e "Stopping Code-Server..."
  echo "Server IP: $(server_ip)"
  require_quickcreate_conf || return 1

  echo "Stopping Code-Server using systemd..."
  systemctl stop code-server@root || return 1

  echo -e "Code-Server Successfully Stopped!"
}

# ============================== MENU ==============================

not_found() {
  err "Command not found, type codecli help for help"
  return 1
}

main() {
  case "${1:-}" in
  help | version | "") ;;
  *)
    if [[ "$(id -u)" != "0" ]]; then
      err "codecli must be run as root!"
      return 1
    fi
    ;;
  esac

  maybe_check_update "${1:-}"

  case "${1:-}" in
  quickcreate)
    case "${2:-}" in
    restart) restartquickcreate ;;
    fix) fixquickcreate ;;
    status) statusquickcreate ;;
    stop) stopquickcreate ;;
    "") quickcreatecode ;;
    *) not_found ;;
    esac
    ;;

  create)
    case "${2:-}" in
    systemd) createnewsystemd "${@:3}" ;;
    systemdlimit) createnewsystemdlimit "${@:3}" ;;
    docker) createnewdocker "${@:3}" ;;
    dockerlimit) createnewdockermemlimit "${@:3}" ;;
    *) not_found ;;
    esac
    ;;

  manage)
    case "${2:-}" in
    systemd)
      case "${3:-}" in
      stop) stopsystemd "${@:4}" ;;
      start) startsystemd "${@:4}" ;;
      delete) deletesystemd "${@:4}" ;;
      status) statussystemd "${@:4}" ;;
      restart) restartsystemd "${@:4}" ;;
      password) changepasswordsystemd "${@:4}" ;;
      schedule) schedulesystemd "${@:4}" ;;
      scheduled) scheduledatq ;;
      convert) convertsystemd "${@:4}" ;;
      *) not_found ;;
      esac
      ;;

    docker)
      case "${3:-}" in
      stop) stopdocker "${@:4}" ;;
      start) startdocker "${@:4}" ;;
      delete) deletedocker "${@:4}" ;;
      list) listdocker ;;
      status) statusdocker ;;
      restart) restartdocker "${@:4}" ;;
      restartall) restartdockerall ;;
      reset) resetdocker "${@:4}" ;;
      password) changepassworddocker "${@:4}" ;;
      schedule) scheduledocker "${@:4}" ;;
      scheduled) scheduledatq ;;
      configure) configuredocker ;;
      *) not_found ;;
      esac
      ;;
    *) not_found ;;
    esac
    ;;

  port) portlist ;;
  backup) backups "${@:2}" ;;
  update) updates ;;
  help | "") helps ;;
  version) versions ;;
  *) not_found ;;
  esac
}

main "$@"
exit $?
