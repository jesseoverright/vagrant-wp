#! /usr/bin/env bash

# load database settings
. /vagrant/settings.sh

# set mysql root password
echo "mysql-server-5.5 mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections

# install apache, mysql, php
apt-get update
apt-get install -y apache2 mysql-server-5.5 php5-mysql php5 php5-mcrypt php5-xdebug git curl

# configure Apache
if [ ! -f /var/log/apachesetup ];
then
    # add www-data to vagrant group
    usermod -a -G vagrant www-data

    # create vhost
    cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/$SERVERNAME.conf
    a2dissite 000-default
    a2ensite $SERVERNAME
    
    # enable mod rewrite
    a2enmod rewrite
    sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www\/html\n        <Directory "\/var\/www\/html">\n            AllowOverride All\n        <\/Directory>/' /etc/apache2/sites-available/$SERVERNAME.conf

    # configure ServerName
    echo "ServerName $SERVERNAME" >> /etc/apache2/conf-available/servername.conf
    a2enconf servername

    sed -i "s/#ServerName www.example.com/ServerName $SERVERNAME/" /etc/apache2/sites-available/$SERVERNAME.conf

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

    #configure xdebug
    echo "zend_extension=xdebug.so
    xdebug.remote_enable=1
    xdebug.remote_handler=dbgp
    xdebug.remote_host=$SERVERNAME
    xdebug.remote_port=9000
    xdebug.remote_log=\"/var/log/xdebug/xdebug.log\"" > /etc/php5/mods-available/xdebug.ini

    # install composer
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer

    touch /var/log/phpsetup
fi

# set up the database
if [ ! -f /var/log/databasesetup ];
then
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE USER '$DATABASE_USER'@'localhost' IDENTIFIED BY '$DATABASE_PASSWORD'"
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $DATABASE_NAME"
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL ON $DATABASE_NAME.* TO '$DATABASE_USER'@'localhost'"
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "flush privileges"

    touch /var/log/databasesetup

    if [ -f /vagrant/database.sql ];
    then
        mysql -uroot -p$MYSQL_ROOT_PASSWORD $DATABASE_NAME < /vagrant/database.sql
    fi

    # add db_backup to bin
    if [ -f /vagrant/db_backup ]; then
        ln -fs /vagrant/db_backup /usr/local/bin/db_backup
    fi
fi

# configure phpmyadmin
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections

export DEBIAN_FRONTEND=noninteractive
apt-get install -y phpmyadmin 

# install wordpress
if [ "$INSTALL_WORDPRESS" == true ];
then
    # install latest wordpress from git repo
    rm -rf /var/www/html
    git clone https://github.com/WordPress/WordPress /var/www/html

    cd /var/www/html
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    git checkout tags/$latestTag

    # create wp-config
    cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

    sed -i "s/database_name_here/$DATABASE_NAME/" /var/www/html/wp-config.php
    sed -i "s/username_here/$DATABASE_USER/" /var/www/html/wp-config.php
    sed -i "s/password_here/$DATABASE_PASSWORD/" /var/www/html/wp-config.php

    # replace generic salt values
    curl -s https://api.wordpress.org/secret-key/1.1/salt >> /usr/local/src/wp.keys
    sed -i '/#@-/r /usr/local/src/wp.keys' /var/www/html/wp-config.php
    sed -i "/#@+/,/#@-/d" /var/www/html/wp-config.php

    # create htaccess with permalinks enabled
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

    # change permissions of wordpress to vagrant user
    chown -R vagrant:vagrant /var/www/html

    # symlink uploads folder
    if [ -d /vagrant/wp-content ];
    then
        rm -rf /var/www/html/wp-content
        ln -fs /vagrant/wp-content /var/www/html/wp-content
    fi

    # install wordpress cli
    curl -Os https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp

    # configure wordpress cli packages with composer
    mkdir /home/vagrant/.wp-cli
    cd /home/vagrant/.wp-cli
    composer init --stability dev --no-interaction
    composer config bin-dir bin
    composer config vendor-dir vendor

    composer config repositories.wp-cli composer 'http://wp-cli.org/package-index/'

    touch /home/vagrant/.wp-cli/config.yml
    echo "require:
    - vendor/autoload.php" >> /home/vagrant/.wp-cli/config.yml

    # install dictator
    composer require danielbachhuber/dictator=dev-master
else
    # symlink www folder
    rm -rf /var/www/html
    ln -fs /vagrant/www /var/www/html
fi

# restart apache
sudo service apache2 restart
