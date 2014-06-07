# Vagrant-WP

Vagrant-WP is a Vagrant configuration for creating and provisioning a LAMP stack development environment with Wordpress.

# Getting Started

## Requirements
Your machine needs to have [VirtualBox](http://www.virtualbox.org) and [Vagrant](http://www.vagrantup.com) installed. If you want Vagrant to automatically update your hosts file, install the [hostsupdater](https://github.com/cogitatio/vagrant-hostsupdater) Vagrant plugin. For automatic database backups, install the [Triggers](https://github.com/emyl/vagrant-triggers) Vagrant plugin.

## Configuring WordPress

Vagrant-WP will automatically install the latest version of Wordpress and configure wp-config.php. It will create a `wordpress` user with password `wordpress` and database `wordpress`. 

### WP Database

Vagrant-WP will import `database.sql` from the parent directory into the database if the file exists. You can change the wordpress database credentials by editing the variables in `provision.sh`.

If the Vagrant Triggers plugin has been installed, Vagrant will automatically backup the database into `database.sql` when you issue the `vagrant destroy` command.

### wp-content

Vagrant-WP will automatically sync a `wp-content` folder from the parent directory into the WordPress base folder.  This will allow you to add plugins, themes, or uploads content automatically to the development environment.

## Build

To build the development environment, clone the repo and run:

`vagrant up`

After Vagrant has created the development environment, Wordpress will be available at [192.168.33.10](http://192.168.33.10) or [wordpress.dev](http://wordpress.dev) if the vagrant-hostsupdater plugin has been installed.

# Server Details

Vagrant-WP creates a Ubuntu 14.04 LTS (Trusty Tahr) development server with the following installed:

- Apache 2.4
- MySQL 5.5
- PHP 5.5.9
- PhpMyAdmin
- Git
- Curl
- Wordpress

