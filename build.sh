#!/bin/bash
# codecli bootstrap: installs dependencies (scripts/install.sh) and the codecli
# binary. Usage: curl -fsSL https://jayanode.com/api/mirror/codecli/build?raw=true | sudo bash
set -o pipefail

MIRROR_BASE="https://jayanode.com/api/mirror/codecli"

echo "
=================================================
            ____ ___  ____  _____ ____ _     ___               
          / ___/ _ \|  _ \| ____/ ___| |   |_ _|              
         | |  | | | | | | |  _|| |   | |    | |               
         | |__| |_| | |_| | |__| |___| |___ | |               
  ___ _   \____\___/|____/|_____\____|_____|___|___             
 |_ _| \ | / ___|_   _|/ \  | |   | |   | ____|  _ \ 
  | ||  \| \___ \ | | / _ \ | |   | |   |  _| | |_) |
  | || |\  |___) || |/ ___ \| |___| |___| |___|  _ < 
 |___|_| \_|____/ |_/_/   \_\_____|_____|_____|_| \_\
                                                     
==================================================
"

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  echo -e "\e[31mThis installer must be run as root.\e[0m" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp_dir"' EXIT

# Download first so a failed/partial download is never executed.
download() {
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 15 "$MIRROR_BASE/$1?raw=true" -o "$2"
}

if ! download install "$tmp_dir/install.sh" || [ ! -s "$tmp_dir/install.sh" ]; then
  echo -e "\e[31mFailed to download the installation script.\e[0m" >&2
  exit 1
fi

if ! "${SUDO[@]}" bash "$tmp_dir/install.sh"; then
  echo -e "\e[31mInstallation script failed.\e[0m" >&2
  exit 1
fi

if download codecli "$tmp_dir/codecli" && [ -s "$tmp_dir/codecli" ] && bash -n "$tmp_dir/codecli" &&
  "${SUDO[@]}" install -m 0755 "$tmp_dir/codecli" /usr/local/bin/codecli; then
  echo "codecli installation successful!"
  "${SUDO[@]}" codecli version
  echo "Type 'sudo codecli help' to see the available commands."
else
  echo -e "\e[31mcodecli installation failed.\e[0m" >&2
  exit 1
fi
