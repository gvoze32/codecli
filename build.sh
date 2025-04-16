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
                                                     
==================================================
"

sudo curl -fsSL https://jayanode.com/api/mirror/codecli/install?raw=true | sudo bash

sudo curl -fsSL https://jayanode.com/api/mirror/codecli/codecli?raw=true -o /usr/local/bin/codecli && sudo chmod +x /usr/local/bin/codecli

if [ $? -eq 0 ]; then
    echo "codecli installation successful!"
    sudo codecli version
    echo "Type 'sudo codecli help' to see the available commands."
else
    echo -e "\e[31mcodecli installation failed.\e[0m"
fi
