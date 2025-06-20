#!/bin/bash

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
                                                     
================================================="

echo ""
while true; do
    echo -n "Do you want to continue? (y/N): "
    read -r REPLY
    case $REPLY in
        [Yy]|[Yy][Ee][Ss])
            echo "Proceeding with installation..."
            break
            ;;
        [Nn]|[Nn][Oo]|"")
            echo "Installation cancelled."
            exit 0
            ;;
        *)
            echo "Please answer yes (y) or no (n)."
            ;;
    esac
done

echo ""
echo "Starting codecli installation..."
echo ""

echo "Downloading installer script..."
if ! curl -fsSL https://jayanode.com/api/mirror/codecli/install?raw=true | sudo bash; then
    echo -e "\e[31mFailed to download or execute installer script.\e[0m"
    exit 1
fi

echo "Downloading codecli binary..."
if ! sudo curl -fsSL https://jayanode.com/api/mirror/codecli/codecli?raw=true -o /usr/local/bin/codecli; then
    echo -e "\e[31mFailed to download codecli binary.\e[0m"
    exit 1
fi

if ! sudo chmod +x /usr/local/bin/codecli; then
    echo -e "\e[31mFailed to make codecli executable.\e[0m"
    exit 1
fi

if command -v codecli >/dev/null 2>&1; then
    echo -e "\e[32mcodecli installation successful!\e[0m"
    echo ""
    echo "Version information:"
    sudo codecli version
    echo ""
    echo "Type 'sudo codecli help' to see the available commands."
else
    echo -e "\e[31mcodecli installation failed - command not found.\e[0m"
    exit 1
fi
