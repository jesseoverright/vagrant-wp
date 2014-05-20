#! /usr/bin/env bash

# variables passed from Vagrantfile
MYSQL_PASSWORD="rootpass"
DATABASE_USER="mysql_db"
DATABASE_PASSWORD="mysql_db"
DATABASE_DB="mysql_db"

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
    rm -rf /var/www/html
    ln -fs /vagrant/www /var/www/html
    
    # enable mod rewrite
    a2enmod rewrite
    sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www\/html\n        <Directory "\/var\/www\/html">\n            AllowOverride All\n        <\/Directory>/' /etc/apache2/sites-available/000-default.conf

    # configure ServerName
    echo 'ServerName lamp.dev' >> /etc/apache2/conf-available/servername.conf
    a2enconf servername

    sed -i 's/#ServerName www.example.com/ServerName lamp.dev/' /etc/apache2/sites-available/000-default.conf

    touch /var/log/apachesetup
fi

# configure php
if [ ! -f /var/log/phpsetup ];
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
    mysql -uroot -p$MYSQL_PASSWORD -e "CREATE USER '$DATABASE_USER'@'localhost' IDENTIFIED BY '$DATABASE_PASSWORD'"
    mysql -uroot -p$MYSQL_PASSWORD -e "CREATE DATABASE $DATABASE_DB"
    mysql -uroot -p$MYSQL_PASSWORD -e "GRANT ALL ON $DATABASE_DB.* TO '$DATABASE_USER'@'localhost'"
    mysql -uroot -p$MYSQL_PASSWORD -e "flush privileges"

    touch /var/log/databasesetup

    if [ -f /vagrant/database.sql ];
    then
        mysql -uroot -p$MYSQL_PASSWORD $DATABASE_DB < /vagrant/database.sql
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

# restart apache
sudo service apache2 restart
