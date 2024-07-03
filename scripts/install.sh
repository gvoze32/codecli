#!/bin/bash

ubuntu_version=$(lsb_release -r | awk '{print $2}')
echo "Checking Ubuntu Version.."
echo "Ubuntu version is $ubuntu_version"
echo "Installing dependencies.."

#Variables
USER_HOME=$(eval echo ~$USER)

#Functions
install_fnm() {
        curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "./.fnm" --skip-shell
        source $USER_HOME/.bashrc
        source /root/.bashrc
        export PATH="/root/.local/share/fnm:$PATH"
        source ~/.bashrc
        eval "$(fnm env)"
        fnm use --install-if-missing 8
        node -v
        npm -v
}

install_docker() {
        sudo adduser --disabled-password --gecos "" codeusers
        sudo cat > /home/codeusers/docker-compose.yml << EOF
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: code-server
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Jakarta
      - PASSWORD=\${PASSWORD_PELANGGAN}
      - SUDO_PASSWORD=\${PASSWORD_PELANGGAN}
      - DEFAULT_WORKSPACE=/home/c9users/\${NAMA_PELANGGAN}:/workspace
    volumes:
      - /home/c9users/\${NAMA_PELANGGAN}:/workspace
    ports:
      - \${PORT}:\${PORT}
    restart: unless-stopped
EOF
}

install_docker_memlimit() {
        sudo adduser --disabled-password --gecos "" codeusersmemlimit
        sudo cat > /home/codeusersmemlimit/docker-compose.yml << EOF
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: code-server
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Jakarta
      - PASSWORD=\${PASSWORD_PELANGGAN}
      - SUDO_PASSWORD=\${PASSWORD_PELANGGAN}
      - DEFAULT_WORKSPACE=/home/codeusersmemlimit/\${NAMA_PELANGGAN}:/workspace
    volumes:
      - /home/codeusersmemlimit/\${NAMA_PELANGGAN}:/workspace
    ports:
      - \${PORT}:\${PORT}
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: \${MEMORY}
EOF
}

blank_env() {
        > /home/codeusers/.env
        > /home/codeusersmemlimit/.env
}

custom_docker_size(){
        read -p "Increase docker network limit to more than 30 containers? [y/N] (Default = n): " choice
        if [[ $choice == [yY] || $choice == [yY][eE][sS] ]]; then
            echo "Setting docker daemon service rule.."
            sudo cat > /etc/docker/daemon.json << EOF
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
            echo "Done."
        else
            echo ""
            echo "==============================="
            echo " Default docker version is set "
            echo "==============================="
            echo ""
            echo ""
        fi
}

install_ioncube(){
        curl -O https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz
        tar -xvzf ioncube_loaders_lin_x86-64.tar.gz
        rm ioncube_loaders_lin_x86-64.tar.gz
        cd ioncube
        php_ext_dir="$(command php -i | grep extension_dir 2>'/dev/null' \
            | command head -n 1 \
            | command cut --characters=31-38)"
        php_version="$(command php --version 2>'/dev/null' \
            | command head -n 1 \
            | command cut --characters=5-7)"
        cp ioncube_loader_lin_${php_version}.so /usr/lib/php/${php_ext_dir}
        cd ..
        rm -rf ioncube
        cat > /etc/php/${php_version}/cli/conf.d/00-ioncube-loader.ini << EOF
zend_extension=ioncube_loader_lin_${php_version}.so
EOF
        php -v
}

case $ubuntu_version in
    22.04)
        # Set NEEDRESTART frontend to avoid prompts
        sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
        sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/g" /etc/needrestart/needrestart.conf
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_SUSPEND=1
        export NEEDRESTART_MODE=l

        echo "Setting up Ubuntu $ubuntu_version.."

        # Update packages
        sudo apt update -y
        sudo apt upgrade -y
        sudo apt update -y

        # Install fnm
        install_fnm

        # Install dependencies
        sudo apt install -y at git npm build-essential php php8.1-common php-gd php-mbstring php-curl php8.1-mysql php-json php8.1-xml php-fpm python2 python3 python3-pip zip unzip dos2unix docker docker.io docker-compose
        curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
        sudo python2 get-pip.py
        pip3 install requests selenium colorama bs4 wget pyfiglet
        pip2 install requests selenium colorama bs4 wget pyfiglet
        systemctl start atd
        sudo apt install -y pythonpy apt-transport-https ca-certificates gnupg-agent software-properties-common

        # Install rclone
        curl https://rclone.org/install.sh | sudo bash

        install_docker
        install_docker_memlimit
        blank_env
        custom_docker_size
        
        # Install ioncube
        install_ioncube

        #Cleanup
        rm get-pip.py install.sh
        ;;
    20.04)
        # Set NEEDRESTART frontend to avoid prompts
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_SUSPEND=1
        export NEEDRESTART_MODE=l

        echo "Setting up Ubuntu $ubuntu_version.."

        # Update packages
        sudo apt update -y
        sudo apt upgrade -y
        sudo apt update -y

        # Install fnm
        install_fnm

        # Install dependencies
        sudo apt install -y at git npm build-essential php7.4-cli php-gd php-mbstring php-curl php-mysqli php-json php-dom php-fpm python2 python3 python3-pip zip unzip dos2unix docker docker.io docker-compose
        curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
        sudo python2 get-pip.py
        python3 -m pip install requests selenium colorama bs4 wget pyfiglet chardet urllib3
        pip2 install requests selenium colorama bs4 wget pyfiglet
        systemctl start atd
        sudo apt install -y pythonpy apt-transport-https ca-certificates gnupg-agent software-properties-common

        # Install rclone
        curl https://rclone.org/install.sh | sudo bash

        install_docker
        install_docker_memlimit
        blank_env
        custom_docker_size
        
        # Install ioncube
        install_ioncube

        #Cleanup
        rm get-pip.py install.sh
        ;;
    18.04)
        echo "Setting up Ubuntu $ubuntu_version.."

        # Update packages
        sudo apt update -y
        sudo apt upgrade -y
        sudo apt update -y
        
        # Install fnm
        install_fnm

        # Install dependencies
        sudo apt install -y curl at git npm build-essential php php7.2-common php-gd php-mbstring php-curl php7.2-mysql php-json php7.2-xml php-fpm python python2.7 python3-pip zip unzip dos2unix docker docker.io docker-compose
        curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
        sudo python2 get-pip.py
        pip3 install requests selenium colorama bs4 wget pyfiglet
        pip2 install requests selenium colorama bs4 wget pyfiglet
        systemctl start atd
        sudo apt install -y pythonpy apt-transport-https ca-certificates gnupg-agent software-properties-common

        # Install rclone
        curl https://rclone.org/install.sh | sudo bash

        install_docker
        install_docker_memlimit
        blank_env
        custom_docker_size
        
        # Install ioncube
        install_ioncube

        #Cleanup
        rm get-pip.py install.sh
        ;;
    24.04)
        # Set NEEDRESTART frontend to avoid prompts
        sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
        sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/g" /etc/needrestart/needrestart.conf
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_SUSPEND=1
        export NEEDRESTART_MODE=l

        echo "Setting up Ubuntu $ubuntu_version.."

        # Update packages
        sudo apt update -y
        sudo apt upgrade -y
        sudo apt update -y

        # Install fnm
        install_fnm

        # Install dependencies
        sudo apt install -y at git npm build-essential php8.3 libapache2-mod-php php8.3-common php8.3-cli php8.3-mbstring php8.3-bcmath php8.3-fpm php8.3-mysql php8.3-zip php8.3-gd php8.3-curl php8.3-xml python3 python3-pip zip unzip dos2unix checkinstall libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev docker docker.io docker-compose
        wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz
        tar -xvf Python-2.7.18.tgz
        cd Python-2.7.18
        ./configure --enable-optimizations
        make
        sudo make install
        python -V
        curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip.py
        sudo python2.7 get-pip.py
        pip2.7 --version
        pip3 install requests selenium colorama bs4 wget pyfiglet
        pip2 install requests selenium colorama bs4 wget pyfiglet
        systemctl start atd
        sudo apt install -y pythonpy apt-transport-https ca-certificates gnupg-agent software-properties-common

        # Install rclone
        curl https://rclone.org/install.sh | sudo bash

        install_docker
        install_docker_memlimit
        blank_env
        custom_docker_size
        
        # Install ioncube
        install_ioncube

        #Cleanup
        cd
        rm get-pip.py install.sh Python-2.7.18.tgz
        rm -rf Python-2.7.18
        ;;
    *)
        echo "Versi Ubuntu tidak didukung"
        ;;
esac