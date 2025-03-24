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

sudo curl -fsSL https://hostingjaya.ninja/api/mirror/code-server/install?raw=true | sudo bash

sudo curl -fsSL https://hostingjaya.ninja/api/mirror/code-server/c9cli?raw=true -o /usr/local/bin/c9cli && sudo chmod +x /usr/local/bin/c9cli

if [ $? -eq 0 ]; then
    echo "code-server installation successful!"
    sudo code-server version
    echo "Type 'sudo code-server help' to see the available commands."
else
    echo -e "\e[31mcode-server installation failed.\e[0m"
fi
