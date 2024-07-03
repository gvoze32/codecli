#!/bin/bash

# COMMANDS

banner() {
    echo "               _           _ _ "
    echo "              | |         | (_)"
    echo "  ___ ___   __| | ___  ___| |_ "
    echo " / __/ _ \ / _` |/ _ \/ __| | |"
    echo "| (_| (_) | (_| |  __/ (__| | |"
    echo " \___\___/ \__,_|\___|\___|_|_|"
                                          
                               
    echo
    echo "====  CODE-SERVER CLI MANAGER  ===="
    echo
}
about() {
    echo "Name of File  : codecli.sh"
    echo "Version       : v1.0 [Budi - Kecekluk] Linux Version"
    echo "Built         : 1.0 [Kecirit]"
    echo "Tested on     :"
    echo "    - Debian  : Ubuntu 24.04"
    echo
    echo "Built with love♡ by gvoze32"
}
# =========== DON'T CHANGE THE ORDER OF THIS FUNCTION =========== #

bantuan() {
    echo "How to use:"
    echo "Please use sudo!"
    echo "codecli [command] [argument] [argument]"
    echo
    echo "Commands List:"
    echo "create"
    echo "  systemd     : Create a new systemctl workspace"
    echo "  systemdlimit: Create a new systemctl workspace with limited RAM"
    echo "  docker      : Create a new docker container"
    echo "  dockerlimit : Create a new docker container with limited RAM and CPU"
    echo "manage"
    echo "  systemctl"
    echo "    delete    : Delete workspace"
    echo "    status    : Show workspace status"
    echo "    restart   : Restart workspace"
    echo "    password  : Change user password"
    echo "    schedule  : Schedule workspace deletion"
    echo "    scheduled : Show scheduled workspace deletion"
    echo "    convert   : Convert user to superuser"
    echo "  docker"
    echo "    delete    : Delete docker container"
    echo "    status    : Show container status"
    echo "    restart   : Restart (all) running containers"
    echo "    password  : Change user password, port & update limited RAM and CPU for dockerlimit"
    echo "    schedule  : Schedule container deletion"
    echo "    scheduled : Show scheduled container deletion"
    echo "    list      : Show docker container lists"
    echo "    configure : Stop, start or restart running container"
    echo "    start     : Start docker daemon service"
    echo "port          : Show used port lists"
    echo "backup        : Backup workspace data with rclone in one archive"
    echo "help          : Show help"
    echo "version       : Show version"
    echo
    echo "Copyright (c) 2024 codecli (under MIT License)"
    echo "Built with love♡ by gvoze32"
}

# CREATE SYSTEMD

createnewsystemd(){
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    return 1
fi

read -p "Username : " user
read -s -p "Password : " password
echo
read -p "Port : " port

apt-get update -y
apt-get upgrade -y

adduser --disabled-password --gecos "" $user
echo "$user:$password" | chpasswd

mkdir -p /home/$user/my-projects
chown -R $user:$user /home/$user

sudo -u $user -H sh -c "curl -fsSL https://code-server.dev/install.sh | sh"

chmod 700 /home/$user

cat > /lib/systemd/system/code-$user.service << EOF
[Unit]
Description=code-server for $user
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:$port --user-data-dir /home/$user/my-projects --auth password
User=$user
Group=$user

UMask=0002
Restart=on-failure

# WorkingDirectory=/home/$user/coder
# Environment="PATH=/home/$user/coder"
# Environment="PASSWORD=$password"
Environment=PASSWORD=your_password

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

createnewsystemdlimit(){
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    return 1
fi

read -p "Username : " user
read -s -p "Password : " password
echo
read -p "Memory Limit (Example = 1G) : " mem
read -p "Port : " port

apt-get update -y
apt-get upgrade -y

adduser --disabled-password --gecos "" $user
echo "$user:$password" | chpasswd

mkdir -p /home/$user/my-projects
chown -R $user:$user /home/$user

sudo -u $user -H sh -c "curl -fsSL https://code-server.dev/install.sh | sh"

chmod 700 /home/$user

cat > /lib/systemd/system/code-$user.service << EOF
[Unit]
Description=code-server for $user
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:$port --user-data-dir /home/$user/my-projects --auth password
User=$user
Group=$user

UMask=0002
MemoryMax=$mem

Restart=on-failure

# WorkingDirectory=/home/$user/coder
# Environment="PATH=/home/$user/coder"
# Environment="PASSWORD=$password"
Environment=PASSWORD=your_password

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

createnewdocker(){
read -p "Username : " user
read -p "Password : " pw
read -p "Port : " port
cd /home/c9users
rm .env
sudo cat > /home/c9users/.env << EOF
PORT=$port
NAMA_PELANGGAN=$user
PASSWORD_PELANGGAN=$pw
EOF
sudo docker-compose -p $user up -d
if [ -d "/home/c9users/$user" ]; then
cd /home/c9users/$user

### Your custom default bundling files goes here, it's recommended to put it on resources directory
### START

### END

cd
else
echo "Workspace directory not found"
fi
}

# CREATE DOCKERLIMIT

createnewdockermemlimit(){
read -p "Username : " user
read -p "Password : " pw
read -p "Port : " portenv
read -p "CPU Limit (Example = 1) : " cpu
read -p "Memory Limit (Example = 1024m) : " mem
cd /home/c9usersmemlimit
rm .env
sudo cat > /home/c9usersmemlimit/.env << EOF
PORT=$portenv
NAMA_PELANGGAN=$user
PASSWORD_PELANGGAN=$pw
MEMORY=$mem
CPUS=1
EOF
sed -i '$ d' /home/c9usersmemlimit/docker-compose.yml
sed -i '$ d' /home/c9usersmemlimit/docker-compose.yml
echo "    mem_limit: $mem" >> /home/c9usersmemlimit/docker-compose.yml
echo "    cpus: $cpu" >> /home/c9usersmemlimit/docker-compose.yml
sudo docker-compose -p $user up -d
if [ -d "/home/c9usersmemlimit/$user" ]; then
cd /home/c9usersmemlimit/$user

### Your custom default bundling files goes here, it's recommended to put it on resources directory
### START

### END

cd
else
echo "Workspace directory not found"
fi
}

# MANAGE SYSTEMCTL

deletesystemctl(){
read -p "Input User : " user
sleep 3
sudo systemctl stop c9-$user.service
sleep 3
sudo killall -u $user
sleep 3
sudo userdel $user
rm -rf /home/$user
}

statussystemctl(){
read -p "Input User : " user
sudo systemctl status c9-$user.service
}

restartsystemctl(){
read -p "Input User : " user
sudo systemctl daemon-reload
sudo systemctl enable c9-$user.service
sudo systemctl restart c9-$user.service
sleep 10
sudo systemctl status c9-$user.service
}

changepasswordsystemctl() {
read -p "Input User :" user
read -p "Input New Password :" password

sudo sed -i "s/-a $user:.*/-a $user:$password/" /lib/systemd/system/c9-$user.service
sudo systemctl daemon-reload
sudo systemctl restart c9-$user.service
sleep 10
sudo systemctl status c9-$user.service
}

schedulesystemctl(){
read -p "Input User : " user
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
sudo systemctl stop c9-$user.service
sleep 3
sudo killall -u $user
sleep 3
sudo userdel $user
END
}

scheduledatq(){
sudo atq
}

convertsystemctl(){
read -p "Input User : " user
echo "Input user password"
passwd $user
echo "Warning, C9 will be restart!"
usermod -aG sudo $user
sudo systemctl daemon-reload
sudo systemctl enable c9-$user.service
sudo systemctl restart c9-$user.service
sleep 10
sudo systemctl status c9-$user.service
}

# MANAGE DOCKER

deletedocker(){
read -p "Input User : " user
echo Are the file is using Docker or Docker Memory Limit?
echo 1. Docker
echo 2. Docker Memory Limit
read -r -p "Choose: " response
case "$response" in
    1) 
cd /home/c9users
        ;;
    *)
cd /home/c9usersmemlimit
        ;;
esac
sudo docker-compose -p $user down
rm -rf $user
}

listdocker(){
docker ps
}

statusdocker(){
docker stats
}

changepassworddocker() {
  read -p "Username : " user
  read -p "New Password : " newpw
  read -p "Port: " port
  read -p "Answer 1 if user are using docker and answer 2 if user using dockermemlimit [1/2] : " option
  
  case $option in
    1)
      base_dir="/home/c9users"
      ;;
    2)
      base_dir="/home/c9usersmemlimit"
      read -p "Memory Limit (Example = 1024m): " mem
      read -p "CPU Limit (Example = 1) : " cpu
      ;;
    *)
      echo "Invalid option"
      return
      ;;
  esac
  
  cd "$base_dir/$user"
  
  if [ -d "$base_dir/$user" ]; then
    sudo cat > .env << EOF
PORT=$port
NAMA_PELANGGAN=$user
PASSWORD_PELANGGAN=$newpw
EOF
    echo "Password changed successfully for user $user"
    
    sudo docker-compose -p $user down
    sudo docker-compose -p $user up -d
    echo "Docker container restarted for user $user"
    
    if [ "$option" = "2" ]; then
      echo " mem_limit: $mem" >> docker-compose.yml
      echo " cpus: $cpu" >> docker-compose.yml
      echo "Memory and CPU limits updated for user $user"
    fi
  else
    echo "User $user does not exist or workspace directory not found"
  fi
}

scheduledocker(){
read -p "Input User : " user
echo Are the file is using docker or dockermemlimit?
read -r -p "Answer Y if you are using docker and answer N if you are using dockermemlimit [y/N] " response
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
    [yY][eE][sS]|[yY]) 
at $waktu <<END
cd /home/c9users
sudo docker-compose -p $user down
END
        ;;
    *)
at $waktu <<END
cd /home/c9usersmemlimit
sudo docker-compose -p $user down
END
        ;;
esac
}

configuredocker(){
read -p "Input User : " user
echo 1. Stop
echo 2. Start
echo 3. Restart
read -r -p "Choose: " response
case "$restart" in
    1) 
echo Are the file is using Docker or Docker Memory Limit?
echo 1. Docker
echo 2. Docker Memory Limit
read -r -p "Choose: " response
case "$response" in
    1) 
cd /home/c9users
        ;;
    *)
cd /home/c9usersmemlimit
        ;;
esac
sudo docker container stop $user
        ;;
    2) 
echo Are the file is using Docker or Docker Memory Limit?
echo 1. Docker
echo 2. Docker Memory Limit
read -r -p "Choose: " response
case "$response" in
    1) 
cd /home/c9users
        ;;
    *)
cd /home/c9usersmemlimit
        ;;
esac
sudo docker container start $user
        ;;
    *)
echo Are the file is using Docker or Docker Memory Limit?
echo 1. Docker
echo 2. Docker Memory Limit
read -r -p "Choose: " response
case "$response" in
    1) 
cd /home/c9users
        ;;
    *)
cd /home/c9usersmemlimit
        ;;
esac
sudo docker container stop $user
sudo docker container start $user
        ;;
esac
}

restartdocker(){
docker restart $(docker ps -q)
}

startdocker(){
sudo service docker start
}

backups(){
echo "=Everyday Backup at 2 AM="
echo "Make sure you has been setup a rclone config file using command: rclone config"
echo ""
read -p "If all has been set up correctly, then input your rclone remote name : " name
echo ""
echo "Choose the backup service provider"
echo "1. Google Drive"
echo "2. Storj"
read -r -p "Choose: " response
case "$response" in
    1) 
sudo cat > /home/backup-$name.sh << EOF
#!/bin/bash
date=\$(date +%y-%m-%d)
rclone mkdir $name:Backup/backup-\$date
cd /home
for i in */; do if ! [[ \$i =~ ^(c9users/|c9usersmemlimit/)$ ]]; then zip -r "\${i%/}.zip" "\$i"; fi done
cd /home/c9users
for i in */; do zip -r "\${i%/}.zip" "\$i"; done
cd /home/c9usersmemlimit
for i in */; do zip -r "\${i%/}.zip" "\$i"; done
mkdir /home/backup
mv /home/*.zip /home/backup
mv /home/c9users/*.zip /home/backup
mv /home/c9usersmemlimit/*.zip /home/backup
rclone copy /home/backup $name:Backup/backup-\$date
rm -rf /home/backup
lines=\$(rclone lsf $name: 2>&1 | wc -l)
if [ \$lines -gt 1 ]
then
    oldbak=\$(rclone lsf $name: 2>&1 | head -n 1)
    rclone purge "$name:\$oldbak"
else
    echo "Old backup not detected, not executing remove command"
fi
EOF
chmod +x /home/backup-$name.sh
echo ""
echo "Backup command created..."
crontab -l > backup-$name
echo "0 2 * * * /home/backup-$name.sh > /home/backup-$name.log 2>&1" >> backup-$name
crontab backup-$name
rm backup-$name
echo ""
echo "Cron job created..."
echo ""
echo "Make sure it's included on your cron list :"
crontab -l
        ;;
    *)
sudo cat > /home/backup-$name.sh << EOF
#!/bin/bash
date=\$(date +%y-%m-%d)
rclone mkdir $name:backup-\$date
cd /home
for i in */; do if ! [[ \$i =~ ^(c9users/|c9usersmemlimit/)$ ]]; then zip -r "\${i%/}.zip" "\$i"; fi done
cd /home/c9users
for i in */; do zip -r "\${i%/}.zip" "\$i"; done
cd /home/c9usersmemlimit
for i in */; do zip -r "\${i%/}.zip" "\$i"; done
mkdir /home/backup
mv /home/*.zip /home/backup/
mv /home/c9users/*.zip /home/backup/
mv /home/c9usersmemlimit/*.zip /home/backup/
rclone copy /home/backup/ $name:backup-\$date/
rm -rf /home/backup
lines=\$(rclone lsf $name: 2>&1 | wc -l)
if [ \$lines -gt 1 ]
then
    oldbak=\$(rclone lsf $name: 2>&1 | head -n 1)
    rclone purge "$name:\$oldbak"
else
    echo "Old backup not detected, not executing remove command"
fi
EOF
chmod +x /home/backup-$name.sh
echo ""
echo "Backup command created..."
crontab -l > backup-$name
echo "0 2 * * * /home/backup-$name.sh > /home/backup-$name.log 2>&1" >> backup-$name
crontab backup-$name
rm backup-$name
echo ""
echo "Cron job created..."
echo ""
echo "Make sure it's included on your cron list :"
crontab -l
        ;;
esac
echo "Backup rule successfully added"
}

portlist(){
sudo lsof -i -P -n | grep LISTEN
}

# BASIC MENUS

helps(){
banner
bantuan
}

versions(){
banner
about
}

# MENU

case $1 in
create)
  case $2 in
    systemd)
      createnewsystemd
    ;;
    systemdlimit)
      createnewsystemdlimit
    ;;
    docker)
      createnewdocker
    ;;
    dockerlimit)
      createnewdockermemlimit
    ;;
    *)
      echo "Command not found, type codecli help for help"
  esac
  ;;
manage)
  case $2 in
    systemctl)
    case $3 in
      delete)
        deletesystemctl
      ;;
      status)
        statussystemctl
      ;;
      restart)
        statussystemctl
      ;;
      password)
        changepasswordsystemctl
      ;;
      schedule)
        schedulesystemctl
      ;;
      scheduled)
        scheduledatq
      ;;
      convert)
        convertsystemctl
      ;;
      *)
      echo "Command not found, type c9cli help for help"
    esac
        ;;
    docker)
    case $3 in
      delete)
        deletedocker
      ;;
      list)
        listdocker
      ;;
      status)
        statusdocker
      ;;
      password)
        changepassworddocker
      ;;
      schedule)
        scheduledocker
      ;;
      scheduled)
        scheduledatq
      ;;
      configure)
        configuredocker
      ;;
      restart)
        restartdocker
      ;;
      start)
        startdocker
      ;;
      *)
      echo "Command not found, type c9cli help for help"
    esac
  esac
;;
port)
  portlist
;;
backup)
  backups
;;
daemon)
  dockerdaemon
;;
help)
  helps
;;
version)
  versions
;;
*)
echo "Command not found, type c9cli help for help"
esac