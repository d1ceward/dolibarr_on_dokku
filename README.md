![](.github/images/repo_header.png)

[![Dolibarr](https://img.shields.io/badge/Dolibarr-20.0.1-blue.svg)](https://github.com/Dolibarr/dolibarr/releases/tag/20.0.1)
[![Dokku](https://img.shields.io/badge/Dokku-Repo-blue.svg)](https://github.com/dokku/dokku)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/d1ceward/dolibarr_on_dokku/graphs/commit-activity)
# Run Dolibarr on Dokku

## Perquisites

### What is Dolibarr?

[Dolibarr](https://www.dolibarr.org/) is a modern software package to manage your company or foundation's activity (contacts, suppliers, invoices, orders, stocks, agenda, accounting, ...).

### What is Dokku?

[Dokku](http://dokku.viewdocs.io/dokku/) is the smallest PaaS implementation you've ever seen - _Docker
powered mini-Heroku_.

### Requirements
* A working [Dokku host](http://dokku.viewdocs.io/dokku/getting-started/installation/)
* [MariaDB](https://github.com/dokku/dokku-mariadb) plugin for Dokku
* [Letsencrypt](https://github.com/dokku/dokku-letsencrypt) plugin for SSL (optionnal)

# Setup

**Note:** Throughout this guide, we will use the domain `dolibarr.example.com` for demonstration purposes. Make sure to replace it with your actual domain name.

## Create the app

Log into your Dokku host and create the Dolibarr app:

```bash
dokku apps:create dolibarr
```

## Configuration

### Install, create and link MariaDB plugin

```bash
# Install MariaDb plugin on Dokku
dokku plugin:install https://github.com/dokku/dokku-mariadb.git mariadb
```

```bash
# Create running plugin
dokku mariadb:create dolibarr
```

```bash
# Link plugin to the main app
dokku mariadb:link dolibarr dolibarr
```

## Persistent storage

To ensure that uploaded data persists between restarts, we create a folder on the host machine, grant write permissions to the user defined in the Dockerfile, and instruct Dokku to mount it to the app container. Follow these steps:

```bash
dokku storage:ensure-directory theoldclunker-dolibarr-documents --chown false
dokku storage:mount theoldclunker-dolibarr /var/lib/dokku/data/storage/theoldclunker-dolibarr-documents:/var/www/documents
```

```bash
dokku storage:ensure-directory theoldclunker-dolibarr-custom --chown false
dokku storage:mount theoldclunker-dolibarr /var/lib/dokku/data/storage/theoldclunker-dolibarr-custom:/var/www/html/custom
```

## Domain setup

To enable routing for the Dolibarr app, we need to configure the domain. Execute the following command:

```bash
dokku domains:set dolibarr dolibarr.example.com
```

## Push Dolibarr to Dokku

### Grabbing the repository

Begin by cloning this repository onto your local machine.

```bash
# Via SSH
git clone git@github.com:d1ceward/dolibarr_on_dokku.git

# Via HTTPS
git clone https://github.com/d1ceward/dolibarr_on_dokku.git
```

### Set up git remote

Now, set up your Dokku server as a remote repository.

```bash
git remote add dokku dokku@example.com:dolibarr
```

### Push Dolibarr

Now, you can push the Dolibarr app to Dokku. Ensure you have completed this step before moving on to the [next section](#ssl-certificate).

```bash
git push dokku master
```

## SSL certificate

Lastly, let's obtain an SSL certificate from [Let's Encrypt](https://letsencrypt.org/).

```bash
# Install letsencrypt plugin
dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git

# Set certificate contact email
dokku letsencrypt:set dolibarr email you@example.com

# Generate certificate
dokku letsencrypt:enable dolibarr
```

## Wrapping up

Congratulations! Your Dolibarr instance is now up and running, and you can access it at [https://dolibarr.example.com](https://dolibarr.example.com).
