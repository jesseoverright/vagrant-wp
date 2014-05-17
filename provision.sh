#! /usr/bin/env bash

# variables passed from Vagrantfile
MYSQL_PASSWORD="rootpass"
WORDPRESS_USER="wordpress"
WORDPRESS_PASSWORD="wordpress"
WORDPRESS_DB="wordpress"

# set mysql root password
echo "mysql-server-5.5 mysql-server/root_password password $MYSQL_PASSWORD" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASSWORD" | debconf-set-selections

# install apache, mysql, php
apt-get update
apt-get install -y apache2 mysql-server-5.5 php5-mysql php5 git curl

# configure Apache
if [ ! -f /var/log/apachesetup ];
then
    # add www-data to vagrant group
    usermod -a -G vagrant www-data

    # symlink www folder
    rm -rf /var/www
    ln -fs /vagrant/www /var/www
    
    # enable mod rewrite
    a2enmod rewrite
    sed -i '/AllowOverride None/c AllowOverride All' /etc/apache2/sites-available/default

    # configure httpd.conf
    echo "ServerName wordpress.dev" >> /etc/apache2/httpd.conf

    touch /var/log/apachesetup
fi

# configure php
if [ -f /var/log/phpsetup ];
then

    # increase file upload limits
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 20M/g' /etc/php5/apache2/php.ini
    sed -i 's/post_max_size = .*/post_max_size = 20M/g' /etc/php5/apache2/php.ini
    
    # turn on error reporting
    sed -i 's/error_reporting = .*/error_reporting = E_ALL/' /etc/php5/apache2/php.ini
    sed -i 's/display_errors = .*/display_errors = On/' /etc/php5/apache2/php.ini

    touch /var/log/phpsetup
fi

# set up the database
if [ ! -f /var/log/databasesetup ];
then
    mysql -uroot -p$MYSQL_PASSWORD -e "CREATE USER '$WORDPRESS_USER'@'localhost' IDENTIFIED BY '$WORDPRESS_PASSWORD'"
    mysql -uroot -p$MYSQL_PASSWORD -e "CREATE DATABASE $WORDPRESS_DB"
    mysql -uroot -p$MYSQL_PASSWORD -e "GRANT ALL ON $WORDPRESS_DB.* TO '$WORDPRESS_USER'@'localhost'"
    mysql -uroot -p$MYSQL_PASSWORD -e "flush privileges"

    touch /var/log/databasesetup

    if [ -f /vagrant/content.sql ];
    then
        mysql -uroot -p$MYSQL_PASSWORD $WORDPRESS_DB < /vagrant/content.sql
    fi
fi

# configure phpmyadmin
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $MYSQL_PASSWORD" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_PASSWORD" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $MYSQL_PASSWORD" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections

export DEBIAN_FRONTEND=noninteractive
apt-get install -y phpmyadmin 

# configure wordpress
if [ ! -f /var/www/wp-config.php ];
then
    # install latest wordpress from git repo
    rm -rf /var/www
    git clone https://github.com/WordPress/WordPress /var/www

    cd /var/www
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    git checkout tags/$latestTag

    # create wp-config
    cp /var/www/wp-config-sample.php /var/www/wp-config.php

    sed -i "s/database_name_here/$WORDPRESS_DB/" /var/www/wp-config.php
    sed -i "s/username_here/$WORDPRESS_USER/" /var/www/wp-config.php
    sed -i "s/password_here/$WORDPRESS_PASSWORD/" /var/www/wp-config.php

    # replace generic salt values
    wget -O /usr/local/src/wp.keys https://api.wordpress.org/secret-key/1.1/salt/
    sed -i '/#@-/r /usr/local/src/wp.keys' /var/www/wp-config.php
    sed -i "/#@+/,/#@-/d" /var/www/wp-config.php

    # creat htaccess?
    echo "
    # BEGIN WordPress
    <IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /
    RewriteRule ^index\.php$ - [L]
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule . /index.php [L]
    </IfModule>

    # END WordPress
    " >> /var/www/.htaccess

    # symlink uploads folder
    if [ -d /vagrant/wp-content ];
    then
        rm -rf /var/www/wp-content
        ln -fs /vagrant/wp-content /var/www/wp-content
    fi
fi


# restart apache
sudo service apache2 restart
