#!/bin/bash
# codecli all-in installer: base packages, atd, rclone, Docker and the two
# compose workspace roots (codeusers / codeusersmemlimit). Safe to re-run.
set -o pipefail

DEFAULT_IMAGE="lscr.io/linuxserver/code-server:latest"
APT_LOCK_TIMEOUT=300

die() {
  echo "ERROR: $*" >&2
  exit 1
}

if [ "$(id -u)" -ne 0 ]; then
  die "The codecli installer must be run as root (use: curl ... | sudo bash)."
fi

[ -r /etc/os-release ] || die "Cannot read /etc/os-release."
# shellcheck disable=SC1091  # provides ID, VERSION_ID and VERSION_CODENAME
. /etc/os-release
ubuntu_version="${VERSION_ID:-}"

echo "Checking Ubuntu Version.."
echo "Ubuntu version is $ubuntu_version"
echo "Installing dependencies.."

# apt-get wrapper: non-interactive, keeps existing config files and waits for
# the dpkg/apt lock instead of failing when unattended-upgrades is running.
apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o DPkg::Lock::Timeout="$APT_LOCK_TIMEOUT" \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" "$@"
}

update_packages() {
  apt_get update || return 1
  apt_get upgrade || return 1
}

# NodeSource nodejs bundles npm and conflicts with the distro npm package;
# a conflict aborts the whole apt transaction, so only add what is missing.
install_packages() {
  local packages=(
    curl git build-essential python3 python3-pip zip unzip
    apt-transport-https ca-certificates gnupg software-properties-common quota at
  )
  command -v node >/dev/null 2>&1 || packages+=(nodejs)
  command -v npm >/dev/null 2>&1 || packages+=(npm)

  if ! apt_get install "${packages[@]}"; then
    echo "Failed to install dependencies: ${packages[*]}" >&2
    return 1
  fi
}

enable_atd() {
  echo "Enabling atd.service..."
  if ! systemctl enable --now atd.service; then
    echo "Failed to enable atd.service." >&2
    return 1
  fi
}

# fetch_and_run URL [interpreter]: download a vendor installer to a temp file and
# run it only after the download fully succeeded (no half-downloaded `curl | sh`).
fetch_and_run() {
  local url="$1" interpreter="${2:-bash}" tmp rc
  tmp="$(mktemp)" || return 1
  if ! curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$tmp"; then
    rm -f "$tmp"
    echo "Failed to download $url" >&2
    return 1
  fi
  "$interpreter" "$tmp"
  rc=$?
  rm -f "$tmp"
  return $rc
}

install_rclone() {
  if command -v rclone >/dev/null 2>&1; then
    echo "rclone is already installed."
    return 0
  fi
  fetch_and_run https://rclone.org/install.sh || true
  if ! command -v rclone >/dev/null 2>&1; then
    echo "Official rclone installer failed, falling back to the distro package..."
    apt_get install rclone || true
  fi
  command -v rclone >/dev/null 2>&1 || {
    echo "Failed to install rclone." >&2
    return 1
  }
}

# Ubuntu releases newer than Docker's repository have no dists/<codename> yet;
# fall back to the newest codename Docker is known to publish.
docker_codename() {
  local codename="${VERSION_CODENAME:-}" status
  status="$(curl -s -o /dev/null -I -w '%{http_code}' "https://download.docker.com/linux/ubuntu/dists/$codename/Release")"
  if [ "$status" = "404" ]; then
    echo "Docker has no repository for '$codename' yet, using 'noble'." >&2
    codename="noble"
  fi
  echo "$codename"
}

install_docker_app() {
  local codename
  codename="$(docker_codename)"
  install -m 0755 -d /etc/apt/keyrings || return 1
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || return 1
  chmod a+r /etc/apt/keyrings/docker.asc

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
    >/etc/apt/sources.list.d/docker.list
  apt_get update || return 1
  apt_get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# ensure_workspace_root NAME [limited]: host user + compose file for one workspace root.
ensure_workspace_root() {
  local name="$1" mode="${2:-}" dir="/home/$1" limits=""
  if ! id -u "$name" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$name" || return 1
  fi
  mkdir -p "$dir" || return 1

  if [ "$mode" = "limited" ]; then
    limits='    deploy:
      resources:
        limits:
          memory: ${MEMORY}
          cpus: ${CPU_LIMIT}
'
  fi

  cat >"$dir/docker-compose.yml" <<EOF
services:
  code-server:
    image: \${DOCKER_IMAGE:-$DEFAULT_IMAGE}
    container_name: code-\${NAMA_PELANGGAN}
    environment:
      - TZ=Asia/Jakarta
      - PASSWORD=\${PASSWORD_PELANGGAN}
      - SUDO_PASSWORD=\${PASSWORD_PELANGGAN}
    volumes:
      - $dir/\${NAMA_PELANGGAN}:/config
    ports:
      - \${PORT}:8443
    restart: always
${limits}
EOF

  # Legacy shared env file (workspaces created by older codecli versions).
  [ -e "$dir/.env" ] || : >"$dir/.env"
  chmod 600 "$dir/.env"
}

# Per-workspace compose settings are stored in $dir/.env.d (root only, 0700).
prepare_env_dirs() {
  install -d -m 700 /home/codeusers/.env.d /home/codeusersmemlimit/.env.d
}

custom_docker_size() {
  local daemon_json="/etc/docker/daemon.json"

  if [ -f "$daemon_json" ]; then
    if grep -q '"default-address-pools"' "$daemon_json"; then
      echo "Docker default address pools already configured."
    else
      echo "WARN: $daemon_json exists without default-address-pools; leaving it unchanged." >&2
    fi
    return 0
  fi

  echo "Creating $daemon_json file"
  echo "Setting custom Docker default address pools"
  mkdir -p /etc/docker
  cat >"$daemon_json" <<EOF
{
    "default-address-pools": [
        {
            "base": "10.10.0.0/16",
            "size": 24
        }
    ]
}
EOF
  systemctl restart docker || return 1
  echo "Docker default address pools set to 10.10.0.0/16 with size 24"
}

configure_needrestart() {
  local conf="/etc/needrestart/needrestart.conf"
  if [ -f "$conf" ]; then
    sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" "$conf"
    sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/g" "$conf"
  fi
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_SUSPEND=1
  export NEEDRESTART_MODE=l
}

case $ubuntu_version in
26.04 | 24.04 | 22.04)
  [ "${ID:-}" = "ubuntu" ] || die "Unsupported distribution '${ID:-unknown}'. Ubuntu 26.04, 24.04 and 22.04 are supported."

  configure_needrestart
  echo "Setting up Ubuntu $ubuntu_version.."

  update_packages || die "Failed to update packages."
  install_packages || die "Failed to install base packages."
  enable_atd || die "Failed to enable atd."
  install_rclone || die "Failed to install rclone."
  install_docker_app || die "Failed to install Docker."

  ensure_workspace_root codeusers || die "Failed to set up /home/codeusers."
  ensure_workspace_root codeusersmemlimit limited || die "Failed to set up /home/codeusersmemlimit."
  prepare_env_dirs || die "Failed to create the workspace settings directories."
  custom_docker_size || die "Failed to configure Docker."
  ;;
*)
  echo "Unsupported Ubuntu version. Ubuntu 26.04, 24.04 and 22.04 are supported."
  exit 1
  ;;
esac
