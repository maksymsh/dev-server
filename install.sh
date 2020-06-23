#!/bin/bash

sudo apt update
sudo apt upgrade -y

sudo chown -R dev:dev /srv
sudo chgrp -hR dev /srv


##############################
##### Create Work folder #####
##############################
mkdir -p /srv/{www,logs,conf,ssl,bin}
mkdir -p /srv/lib/{nvm,composer}
#-----------------------------------------------------------------------------------------------------------------------

echo 'PATH="/srv/bin:$PATH"' >> ~/.profile

# add new user
#newUser=dev
#sudo useradd -s /bin/bash -d /home/$newUser/ -m -G sudo $newUser


##############################
######### Local DNS ##########
##############################
#local_domains=( "localhost" )
#for i in "${local_domains[@]}"
#do
#    sudo sh -c "echo address=/.$i/127.0.0.1 >> /etc/NetworkManager/dnsmasq.d/dev"
#done


#sudo sed -i "s/\[main\]/\[main\]\\ndns=dnsmasq/g" /etc/NetworkManager/NetworkManager.conf
#-----------------------------------------------------------------------------------------------------------------------


##############################
####### Curl Git Htop ########
##############################
sudo apt install -y curl git htop

#-----------------------------------------------------------------------------------------------------------------------
##############################
########## Node JS ############
##############################
echo "export NVM_DIR='/srv/lib/nvm'" >> $HOME/.bashrc
source .bashrc
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.34.0/install.sh | bash
sed -i "s/export NVM_DIR='\/srv\/lib\/nvm'//" $HOME/.bashrc
source ~/.bashrc
nvm install --lts --latest-npm
npm i -global yarn
yarn config set prefix $(npm config get prefix)


##############################
############ PHP #############
##############################
sudo add-apt-repository -y ppa:ondrej/php
phpversions=( "5.6" "7.4" )
for i in "${phpversions[@]}"
do
    sudo apt install -y php$i php$i-fpm php$i-dev php$i-curl php$i-gd php$i-intl php$i-mysql php$i-mbstring php$i-xml php$i-bcmath php$i-zip php$i-pgsql
done

sudo apt install -y php-xdebug php-memcached php-http

sudo sed -i "s/www-data/$USER/g" /etc/php/*/fpm/pool.d/www.conf
sudo sed -i "s/display_errors = Off/display_errors = On/g" /etc/php/*/*/php.ini
sudo sed -i "s/short_open_tag = Off/short_open_tag = On/g" /etc/php/*/*/php.ini

for i in "${phpversions[@]}"
do
sudo tee -a /etc/php/$i/*/php.ini >/dev/null <<'EOF'
[xdebug]
xdebug.remote_enable=1
xdebug.remote_autostart=1
xdebug.remote_connect_back=1
xdebug.remote_port=9000
xdebug.remote_handler=dbgp
xdebug.remote_host=localhost
xdebug.idekey=PHPSTORM
xdebug.extended_info=1
xdebug.profiler_enable=1
EOF
sudo service php$i-fpm restart
done

install_apache2(){

# Change apache port

sudo apt install -y --no-install-recommends apache2 
sudo mv /etc/apache2 /srv/conf/apache2
sudo chown -R dev:dev /srv/conf/apache2
sudo ln -sd /srv/conf/apache2 /etc/apache2

}



mkdir /srv/conf/apache2;
mkdir /srv/conf/apache2/vhosts;

sudo a2enmod rewrite proxy_fcgi

for i in "${phpversions[@]}"
do
    sudo a2enconf php$i-fpm
done

sudo service apache2 restart
#-----------------------------------------------------------------------------------------------------------------------


##############################
######### Composer ###########
##############################
echo "export COMPOSER_HOME='/srv/lib/composer'" >> $HOME/.bashrc
source $HOME/.bashrc
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
echo 'PATH="$COMPOSER_HOME/vendor/bin:$PATH"' >> ~/.profile
#-----------------------------------------------------------------------------------------------------------------------


##############################
###### SSL Certificate #######
##############################
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /srv/ssl/localhost.key -out /srv/ssl/localhost.crt -subj "/C=GB/ST=London/L=London/O=Dev/OU=Dev/CN=localhost"
openssl dhparam -out /srv/ssl/dhparam.pem 2048
#-----------------------------------------------------------------------------------------------------------------------


##############################
########### Nginx ############
##############################
sudo apt install -y nginx

sudo mv /srv/conf/nginx /srv/conf/nginx
sudo chown -R dev:dev /srv/conf/nginx
sudo ln -sd /srv/conf/nginx /srv/conf/nginx

mkdir /srv/conf/nginx;
mkdir /srv/conf/nginx/vhosts;
mkdir /srv/conf/nginx/snippets;

sh -c 'cat > /srv/conf/nginx/snippets/self-signed.conf <<EOF
ssl_certificate /srv/ssl/localhost.crt;
ssl_certificate_key /srv/ssl/localhost.key;
EOF'

sh -c 'cat > /srv/conf/nginx/snippets/ssl-params.conf <<EOF
ssl_protocols TLSv1.2;
ssl_prefer_server_ciphers on;
ssl_dhparam /srv/ssl/dhparam.pem;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
ssl_ecdh_curve secp384r1; # Requires nginx >= 1.1.0
ssl_session_timeout  10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off; # Requires nginx >= 1.5.9
ssl_stapling on; # Requires nginx >= 1.3.7
ssl_stapling_verify on; # Requires nginx => 1.3.7
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
# Disable strict transport security for now. You can uncomment the following
# line if you understand the implications.
# add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
EOF'

sudo rm /srv/conf/nginx/sites-available/default
sudo rm /srv/conf/nginx/sites-enabled/default
sudo sed -i "s/include \/etc\/nginx\/modules-enabled\/\*\.conf;/include \/etc\/nginx\/modules-enabled\/\*\.conf;\ninclude \/srv\/conf\/nginx\/global\.conf;/g" /srv/conf/nginx/nginx.conf
sudo sed -i "s/include \/etc\/nginx\/sites-enabled\/\*;/include \/etc\/nginx\/sites-enabled\/\*;\n\tinclude \/srv\/conf\/nginx\/vhosts\.conf;/g" /srv/conf/nginx/nginx.conf
sh -c 'cat > /srv/conf/nginx/global.conf <<EOF
#global nginx conf
EOF'
sh -c 'cat > /srv/conf/nginx/vhosts.conf <<EOF
include /srv/conf/nginx/vhosts/*.conf;
EOF'
sh -c 'cat > /srv/conf/nginx/vhosts/localhost.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name *.localhost;

    include /srv/conf/nginx/snippets/self-signed.conf;
    include /srv/conf/nginx/snippets/ssl-params.conf;

    set \$projectpath /srv/www;

    # check one name domain for simple application
    if (\$host ~ "^(.[^.]*)\.localhost$") {
        set \$domain \$1;
    }

    # check multi name domain to multi application
    if (\$host ~ "^(.*)\.(.[^.]*)\.localhost$") {
        set \$subdomain \$1;
        set \$domain \$2;
    }

    set \$projectpath \$projectpath/\$domain;

    if (-d \$projectpath/www){
        set \$projectpath \$projectpath/www;
    }

    set \$rootdir \$projectpath;

    if (-d \$projectpath/subdomains/\$subdomain){
        # in which case, set that directory as the root
        set \$rootdir \$projectpath/subdomains/\$subdomain;
    }

    
    if (-f \$rootdir/index.php){
        set \$index index.php;
    }

    # For Laravel
    if (-f \$rootdir/public/index.php){
        set \$rootdir \$rootdir/public;
        set \$index index.php;
    }

    # For Symfony
    if (-f \$rootdir/web/app_dev.php){
        set \$rootdir \$rootdir/web;
        set \$index app_dev.php;
    }

    # For YII
    if (-f \$rootdir/web/index.php){
        set \$rootdir \$rootdir/web;
        set \$index index.php;
    }

    root \$rootdir;

    index index.php app_dev.php index.html index.htm index.nginx-debian.html;

    # Front-controller pattern as recommended by the nginx docs
    location / {
        try_files \$uri \$uri/ /\$index?\$query_string;
    }

    # Standard php-fpm based on the default config below this point
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php7.4-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }

    access_log off;
    error_log /srv/logs/nginx.log;
}
EOF'
sudo sed -i "s/www-data/$USER/g" /srv/conf/nginx/nginx.conf
sudo service nginx restart
#-----------------------------------------------------------------------------------------------------------------------



##############################
########### Mysql ############
##############################
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password secret';
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password secret';
sudo apt -y install mysql-server
sudo sh -c 'echo "character-set-server=utf8" >> /etc/mysql/mysql.conf.d/mysqld.cnf'
sudo sh -c 'echo "collation-server=utf8_general_ci" >> /etc/mysql/mysql.conf.d/mysqld.cnf'
sudo sh -c 'echo "sql_mode = NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION" >> /etc/mysql/mysql.conf.d/mysqld.cnf'
sudo sh -c 'echo "default-time-zone=+02:00" >> /etc/mysql/mysql.conf.d/mysqld.cnf'
sudo sh -c 'echo "default-authentication-plugin=mysql_native_password" >> /etc/mysql/mysql.conf.d/mysqld.cnf'
mysql --user=root --password=secret -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '123'; flush privileges;"
mysql --user=root --password=123 -e "CREATE USER 'max'@'localhost'IDENTIFIED WITH mysql_native_password BY ''; flush privileges;"
mysql --user=root --password=123 -e "GRANT ALL PRIVILEGES ON *.* TO 'max'@'localhost'; flush privileges;"
#-----------------------------------------------------------------------------------------------------------------------


##############################
######## Redis Server ########
##############################
sudo apt install -y redis-server
#-----------------------------------------------------------------------------------------------------------------------


##############################
######### PostgreSQL #########
##############################
sudo apt install -y postgresql postgresql-contrib
#wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
#echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | sudo tee  /etc/apt/sources.list.d/pgdg.list
#sudo apt update
#sudo apt install -y pgadmin4 pgadmin4-apache2
#-----------------------------------------------------------------------------------------------------------------------



##############################
########## Docker ############
##############################

#-----------------------------------------------------------------------------------------------------------------------


##############################
######### Sublime ############
##############################
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -
sudo apt-add-repository "deb https://download.sublimetext.com/ apt/stable/"
sudo apt install sublime-text
#-----------------------------------------------------------------------------------------------------------------------



##############################
###### File management #######
##############################
sudo apt install -y gparted doublecmd-qt filezilla putty unrar
#-----------------------------------------------------------------------------------------------------------------------

##############################
########### Skype ############
##############################
wget https://repo.skype.com/latest/skypeforlinux-64.deb
sudo dpkg --install skypeforlinux-64.deb
rm skypeforlinux-64.deb
# or
#sudo snap install skype --classic


##############################
######### Telegram ###########
##############################
wget https://telegram.org/dl/desktop/linux
sudo tar xJf linux -C /opt/
sudo ln -s /opt/Telegram/Telegram /usr/local/bin/telegram
rm linux
# or
#sudo snap install telegram-desktop

##############################
######### PHPStorm ###########
##############################
#sudo sh -c 'echo "0.0.0.0 account.jetbrains.com" >> /etc/hosts'
#sudo sh -c 'echo "0.0.0.0 www.jetbrains.com" >> /etc/hosts'
#sudo sh -c 'echo "0.0.0.0 https://account.jetbrains.com:443" >> /etc/hosts'
#sudo sh -c 'echo "1.2.3.4 account.jetbrains.com" >> /etc/hosts'
#sudo sh -c 'echo "1.2.3.4 http://www.jetbrains.com" >> /etc/hosts'
#sudo sh -c 'echo "1.2.3.4 www-weighted.jetbrains.com" >> /etc/hosts'
#sudo sh -c 'echo "0.0.0.0 account.jetbrains.com " >> /etc/hosts'

#sudo mkdir -p /opt/jetbrains

#wget https://download-cf.jetbrains.com/webide/PhpStorm-2019.3.4.tar.gz
#sudo tar -xzvf PhpStorm-*.tar.gz -C /opt/jetbrains/
#sudo mv /opt/jetbrains/PhpStorm-* /opt/jetbrains/phpstorm
#rm PhpStorm-*.tar.gz

#wget https://download-cf.jetbrains.com/webide/WebStorm-2019.3.4.tar.gz
#sudo tar -xzvf WebStorm-*.tar.gz -C /opt/jetbrains/
#sudo mv /opt/jetbrains/WebStorm-* /opt/jetbrains/webstorm
#rm WebStorm-*.tar.gz

##############################
########## Trello ############
##############################
sudo apt install -y libgconf-2-4
wget https://github.com/danielchatfield/trello-desktop/releases/download/v0.1.9/Trello-linux-0.1.9.zip
unzip Trello-linux-0.1.9.zip -d trello
sudo mv trello /opt/trello
rm Trello-linux-0.1.9.zip
mkdir -p $HOME/.local/share/applications
sh -c 'cat > $HOME/.local/share/applications/trello.desktop <<EOF
[Desktop Entry]
Name=Trello
Exec=/opt/trello/Trello
Terminal=false
Type=Application
Icon=/opt/trello/resources/app/static/Icon.png
EOF'


### Fix for thunderbird tray
#wget http://archive.ubuntu.com/ubuntu/pool/main/t/thunderbird/thunderbird_60.9.1+build1-0ubuntu0.16.04.1_amd64.deb
#sudo dpkg --install thunderbird*.deb
#rm thunderbird*.deb
#sudo apt-mark hold thunderbird
#git clone https://github.com/firetray-updates/FireTray
#cd FireTray/src
#make build
#ls ../build-*/*.xpi # <-- your xpi, ready to be installed


sudo sh -c "echo \"alias pkexec='pkexec /usr/bin/env DISPLAY=\\\$DISPLAY XAUTHORITY=\\\$XAUTHORITY $@'\" >> $HOME/.bashrc"
source $HOME/.bashrc

sudo apt update
sudo apt upgrade -y



