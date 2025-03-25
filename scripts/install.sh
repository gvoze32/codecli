#!/bin/bash

ubuntu_version=$(lsb_release -r | awk '{print $2}')
echo "Checking Ubuntu Version.."
echo "Ubuntu version is $ubuntu_version"
echo "Installing dependencies.."

#Variables
USER_HOME=$(eval echo ~$USER)

# Function for efficient package updating
update_packages() {
  sudo DEBIAN_FRONTEND=noninteractive apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
  sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
  sudo DEBIAN_FRONTEND=noninteractive apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
}

install_docker_app() {
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update

  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker() {
  sudo adduser --disabled-password --gecos "" codeusers
  sudo cat >/home/codeusers/docker-compose.yml <<EOF
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: code-\${NAMA_PELANGGAN}
    environment:
      - TZ=Asia/Jakarta
      - PASSWORD=\${PASSWORD_PELANGGAN}
      - SUDO_PASSWORD=\${PASSWORD_PELANGGAN}
    volumes:
      - /home/codeusers/\${NAMA_PELANGGAN}:/config
    ports:
      - \${PORT}:8443
    restart: always
EOF
}

install_docker_memlimit() {
  sudo adduser --disabled-password --gecos "" codeusersmemlimit
  sudo cat >/home/codeusersmemlimit/docker-compose.yml <<EOF
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: code-\${NAMA_PELANGGAN}
    environment:
      - TZ=Asia/Jakarta
      - PASSWORD=\${PASSWORD_PELANGGAN}
      - SUDO_PASSWORD=\${PASSWORD_PELANGGAN}
    volumes:
      - /home/codeusersmemlimit/\${NAMA_PELANGGAN}:/config
    ports:
      - \${PORT}:8443
    restart: always
    deploy:
      resources:
        limits:
          memory: \${MEMORY}
          cpus: \${CPU_LIMIT}
EOF
}

blank_env() {
  >/home/codeusers/.env
  >/home/codeusersmemlimit/.env
}

custom_docker_size() {
  echo "Creating /etc/docker/daemon.json file"
  echo "Setting custom Docker default address pools"
  sudo cat >/etc/docker/daemon.json <<EOF
{
    "default-address-pools": [
        {
            "base": "10.10.0.0/16",
            "size": 24
        }
    ]
}
EOF
  sudo service docker restart
  sudo docker network inspect bridge | grep Subnet
  echo "Docker default address pools set to 10.10.0.0/16 with size 24"
}

second_dep() {
  sudo apt install -y apt-transport-https ca-certificates gnupg-agent software-properties-common
}

case $ubuntu_version in
24.04)
  # Set NEEDRESTART frontend to avoid prompts
  sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
  sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/g" /etc/needrestart/needrestart.conf
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_SUSPEND=1
  export NEEDRESTART_MODE=l

  echo "Setting up Ubuntu $ubuntu_version.."

  # Update packages
  update_packages

  # Install dependencies
  sudo apt install -y nodejs curl at git npm build-essential python3 python3-pip zip unzip
  systemctl start atd

  # Install additional dependencies
  second_dep

  # Install rclone
  curl https://rclone.org/install.sh | sudo bash

  install_docker_app
  install_docker
  install_docker_memlimit
  blank_env
  custom_docker_size
  ;;
*)
  echo "Unsupported Ubuntu version. Only Ubuntu 24.04 is supported."
  exit 1
  ;;
esac
