#! /usr/bin/env bash

# variables for mysql & server
WORDPRESS_USER="wordpress"
WORDPRESS_PASSWORD="wordpress"
WORDPRESS_DB="wordpress"
SERVERNAME="wordpress.dev"

# set mysql root password
echo "mysql-server-5.5 mysql-server/root_password password rootpass" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password rootpass" | debconf-set-selections

# install apache, mysql, php
apt-get update
apt-get install -y apache2 mysql-server-5.5 php5-mysql php5 php5-mcrypt git curl

# configure Apache
if [ ! -f /var/log/apachesetup ];
then
    # add www-data to vagrant group
    usermod -a -G vagrant www-data
    
    # enable mod rewrite
    a2enmod rewrite
    sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www\/html\n        <Directory "\/var\/www\/html">\n            AllowOverride All\n        <\/Directory>/' /etc/apache2/sites-available/000-default.conf

    # configure ServerName
    echo "ServerName $SERVERNAME" >> /etc/apache2/conf-available/servername.conf
    a2enconf servername

    sed -i "s/#ServerName www.example.com/ServerName $SERVERNAME/" /etc/apache2/sites-available/000-default.conf

    touch /var/log/apachesetup
fi

# configure php
if [ ! -f /var/log/phpsetup ];
then

    # enable mcrypt
    php5enmod mcrypt

    # increase file upload limits
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 20M/g' /etc/php5/apache2/php.ini
    sed -i 's/post_max_size = .*/post_max_size = 20M/g' /etc/php5/apache2/php.ini
    
    # turn on error reporting
    sed -i 's/error_reporting = .*/error_reporting = E_ALL/' /etc/php5/apache2/php.ini
    sed -i 's/display_errors = .*/display_errors = On/' /etc/php5/apache2/php.ini

    # install composer
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer

    touch /var/log/phpsetup
fi

# set up the database
if [ ! -f /var/log/databasesetup ];
then
    mysql -uroot -prootpass -e "CREATE USER '$WORDPRESS_USER'@'localhost' IDENTIFIED BY '$WORDPRESS_PASSWORD'"
    mysql -uroot -prootpass -e "CREATE DATABASE $WORDPRESS_DB"
    mysql -uroot -prootpass -e "GRANT ALL ON $WORDPRESS_DB.* TO '$WORDPRESS_USER'@'localhost'"
    mysql -uroot -prootpass -e "flush privileges"

    touch /var/log/databasesetup

    if [ -f /vagrant/database.sql ];
    then
        mysql -uroot -prootpass $WORDPRESS_DB < /vagrant/database.sql
    fi

    # add db_backup to bin
    if [ -f /vagrant/db_backup ]; then
        if [ ! -d /home/vagrant/bin ]; then
            mkdir /home/vagrant/bin
        fi
        ln -fs /vagrant/db_backup /home/vagrant/bin/db_backup
    fi
fi

# configure phpmyadmin
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password rootpass" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password rootpass" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password rootpass" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections

export DEBIAN_FRONTEND=noninteractive
apt-get install -y phpmyadmin 

# configure wordpress
if [ ! -f /var/www/html/wp-config.php ];
then
    # install latest wordpress from git repo
    rm -rf /var/www/html
    git clone https://github.com/WordPress/WordPress /var/www/html

    cd /var/www/html
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    git checkout tags/$latestTag

    # create wp-config
    cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

    sed -i "s/database_name_here/$WORDPRESS_DB/" /var/www/html/wp-config.php
    sed -i "s/username_here/$WORDPRESS_USER/" /var/www/html/wp-config.php
    sed -i "s/password_here/$WORDPRESS_PASSWORD/" /var/www/html/wp-config.php

    # replace generic salt values
    curl -s https://api.wordpress.org/secret-key/1.1/salt >> /usr/local/src/wp.keys
    sed -i '/#@-/r /usr/local/src/wp.keys' /var/www/html/wp-config.php
    sed -i "/#@+/,/#@-/d" /var/www/html/wp-config.php

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
    " >> /var/www/html/.htaccess

    # symlink uploads folder
    if [ -d /vagrant/wp-content ];
    then
        rm -rf /var/www/html/wp-content
        ln -fs /vagrant/wp-content /var/www/html/wp-content
    fi
fi


# restart apache
sudo service apache2 restart
