#!/bin/bash

parseDatabaseURI() {
  eval $(echo "$1" | sed -e "s#^\(\(.*\)://\)\?\(\([^:@]*\)\(:\(.*\)\)\?@\)\?\([^/?]*\)\(/\(.*\)\)\?#${PREFIX:-URI_}SCHEME='\2' ${PREFIX:-URI_}USER='\4' ${PREFIX:-URI_}PASSWORD='\6' ${PREFIX:-URI_}HOSTPORT='\7' ${PREFIX:-URI_}NAME='\9'#")
}

initDolibarr() {
  local CURRENT_UID=$(id -u www-data)
  local CURRENT_GID=$(id -g www-data)
  usermod -u ${WWW_USER_ID} www-data
  groupmod -g ${WWW_GROUP_ID} www-data

  if [[ ! -d /var/www/documents ]]; then
    echo "[INIT] => create volume directory /var/www/documents ..."
    mkdir -p /var/www/documents
  fi

  if [[ ! -d /var/www/html/custom ]]; then
    echo "[INIT] => create volume directory /var/www/html/custom ..."
    mkdir -p /var/www/html/custom
  fi

  echo "[INIT] => update PHP Config ..."
  cat > ${PHP_INI_DIR}/conf.d/dolibarr-php.ini << EOF
date.timezone = ${PHP_INI_DATE_TIMEZONE}
sendmail_path = /usr/sbin/sendmail -t -i
memory_limit = ${PHP_INI_MEMORY_LIMIT}
upload_max_filesize = ${PHP_INI_UPLOAD_MAX_FILESIZE}
post_max_size = ${PHP_INI_POST_MAX_SIZE}
allow_URI_fopen = ${PHP_INI_ALLOW_URI_FOPEN}
session.use_strict_mode = 1
disable_functions = pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_get_handler,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,pcntl_async_signals,passthru,shell_exec,system,proc_open,popen
EOF

  if [[ ! -f /var/www/html/conf/conf.php ]]; then
    echo "[INIT] => update Dolibarr Config ..."
    cat > /var/www/html/conf/conf.php << EOF
<?php
\$dolibarr_main_URI_root='${DOLIBARR_URI_ROOT}';
\$dolibarr_main_document_root='/var/www/html';
\$dolibarr_main_URI_root_alt='/custom';
\$dolibarr_main_document_root_alt='/var/www/html/custom';
\$dolibarr_main_data_root='/var/www/documents';
\$dolibarr_main_db_host='${DOLIBARR_DB_HOST}';
\$dolibarr_main_db_port='${DOLIBARR_DB_PORT}';
\$dolibarr_main_db_name='${DOLIBARR_DB_NAME}';
\$dolibarr_main_db_prefix='llx_';
\$dolibarr_main_db_user='${DOLIBARR_DB_USER}';
\$dolibarr_main_db_pass='${DOLIBARR_DB_PASSWORD}';
\$dolibarr_main_db_type='mysqli';
\$dolibarr_main_authentication='dolibarr';
\$dolibarr_main_prod=${DOLIBARR_PROD};
EOF
    if [[ ! -z ${DOLIBARR_INSTANCE_UNIQUE_ID} ]]; then
      echo "[INIT] => update Dolibarr Config with instance unique id ..."
      echo "\$dolibarr_main_instance_unique_id='${DOLIBARR_INSTANCE_UNIQUE_ID}';" >> /var/www/html/conf/conf.php
    fi
  fi

  echo "[INIT] => update ownership for file in Dolibarr Config ..."
  chown www-data:www-data /var/www/html/conf/conf.php
  chmod 400 /var/www/html/conf/conf.php

  if [[ ${CURRENT_UID} -ne ${WWW_USER_ID} || ${CURRENT_GID} -ne ${WWW_GROUP_ID} ]]; then
    # Refresh file ownership cause it has changed
    echo "[INIT] => As UID / GID have changed from default, update ownership for files in /var/ww ..."
    chown -R www-data:www-data /var/www
  else
    # Reducing load on init : change ownership only for volumes declared in docker
    echo "[INIT] => update ownership for files in /var/www/documents ..."
    chown -R www-data:www-data /var/www/documents
  fi
}

waitForDataBase() {
  r=1

  while [[ ${r} -ne 0 ]]; do
    mysql -u ${DOLIBARR_DB_USER} --protocol tcp -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} --connect-timeout=5 -e "status" > /dev/null 2>&1
    r=$?
    if [[ ${r} -ne 0 ]]; then
      echo "Waiting that SQL database is up ..."
      sleep 2
    fi
  done
}

initializeDatabase() {
  for fileSQL in /var/www/html/install/mysql/tables/*.sql; do
    if [[ ${fileSQL} != *.key.sql ]]; then
      echo "Importing table from `basename ${fileSQL}` ..."
      sed -i 's/--.*//g;' ${fileSQL} # remove all comment
      mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} < ${fileSQL}
    fi
  done

  for fileSQL in /var/www/html/install/mysql/tables/*.key.sql; do
    echo "Importing table key from `basename ${fileSQL}` ..."
    sed -i 's/--.*//g;' ${fileSQL}
    mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} < ${fileSQL} > /dev/null 2>&1
  done

  for fileSQL in /var/www/html/install/mysql/functions/*.sql; do
    echo "Importing `basename ${fileSQL}` ..."
    sed -i 's/--.*//g;' ${fileSQL}
    mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} < ${fileSQL} > /dev/null 2>&1
  done

  for fileSQL in /var/www/html/install/mysql/data/*.sql; do
    echo "Importing data from `basename ${fileSQL}` ..."
    sed -i 's/--.*//g;' ${fileSQL}
    mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} < ${fileSQL} > /dev/null 2>&1
  done

  echo "Set some default const ..."
  mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} -e "DELETE FROM llx_const WHERE name='MAIN_VERSION_LAST_INSTALL';" > /dev/null 2>&1
  mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} -e "DELETE FROM llx_const WHERE name='MAIN_NOT_INSTALLED';" > /dev/null 2>&1
  mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} -e "DELETE FROM llx_const WHERE name='MAIN_LANG_DEFAULT';" > /dev/null 2>&1
  mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} -e "INSERT INTO llx_const(name,value,type,visible,note,entity) values('MAIN_VERSION_LAST_INSTALL', '${DOLIBARR_VERSION}', 'chaine', 0, 'Dolibarr version when install', 0);" > /dev/null 2>&1
  mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} -e "INSERT INTO llx_const(name,value,type,visible,note,entity) VALUES ('MAIN_LANG_DEFAULT', 'auto', 'chaine', 0, 'Default language', 1);" > /dev/null 2>&1
  mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} -e "INSERT INTO llx_const(name,value,type,visible,note,entity) VALUES ('SYSTEMTOOLS_MYSQLDUMP', '/usr/bin/mysqldump', 'chaine', 0, '', 0);" > /dev/null 2>&1

  echo "Enable user module ..."
  php /var/www/scripts/docker-init.php

  if [ -d /var/www/scripts/docker-init.d ] ; then
    for file in /var/www/scripts/docker-init.d/*; do
      [ ! -f $file ] && continue

      # If extension is not in PHP SQL SH, we loop
      isExec=$(echo "PHP SQL SH" | grep -wio ${file##*.})
      [ -z "$isExec" ] && continue

      echo "Importing custom ${isExec} from `basename ${file}` ..."
      if [ "$isExec" == "SQL" ] ; then
        sed -i 's/--.*//g;' ${file}
        mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} < ${file} > /dev/null 2>&1
      elif [ "$isExec" == "PHP" ] ; then
        php $file
      elif [ "$isExec" == "SH" ] ; then
        /bin/bash $file
      fi
    done
  fi

  # Update ownership after initialisation of modules
  chown -R www-data:www-data /var/www/documents
}

migrateDatabase() {
  TARGET_VERSION="$(echo ${DOLIBARR_VERSION} | cut -d. -f1).$(echo ${DOLIBARR_VERSION} | cut -d. -f2).0"
  echo "Schema update is required ..."
  echo "Dumping Database into /var/www/documents/dump.sql ..."

  mysqldump -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} > /var/www/documents/dump.sql
  r=${?}
  if [[ ${r} -ne 0 ]]; then
    echo "Dump failed ... Aborting migration ..."
    return ${r}
  fi
  echo "Dump done ... Starting Migration ..."

  echo "" > /var/www/documents/migration_error.html
  pushd /var/www/htdocs/install > /dev/null
  php upgrade.php ${INSTALLED_VERSION} ${TARGET_VERSION} >> /var/www/documents/migration_error.html 2>&1 && \
  php upgrade2.php ${INSTALLED_VERSION} ${TARGET_VERSION} >> /var/www/documents/migration_error.html 2>&1 && \
  php step5.php ${INSTALLED_VERSION} ${TARGET_VERSION} >> /var/www/documents/migration_error.html 2>&1
  r=$?
  popd > /dev/null

  if [[ ${r} -ne 0 ]]; then
    echo "Migration failed ... Restoring DB ... check file /var/www/documents/migration_error.html for more info on error ..."
    mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} < /var/www/documents/dump.sql
    echo "DB Restored ..."
    return ${r}
  else
    echo "Migration successful ... Enjoy !!"
  fi

  return 0
}

lockInstallation() {
  touch /var/www/documents/install.lock
  chown www-data:www-data /var/www/documents/install.lock
  chmod 400 /var/www/documents/install.lock
}

run() {
  initDolibarr
  echo "Current Version is : ${DOLIBARR_VERSION}"

  if [[ ${DOLIBARR_INSTALL_AUTO} -eq 1 && ! -f /var/www/documents/install.lock ]]; then
    waitForDataBase

    mysql -u ${DOLIBARR_DB_USER} -p${DOLIBARR_DB_PASSWORD} -h ${DOLIBARR_DB_HOST} -P ${DOLIBARR_DB_PORT} ${DOLIBARR_DB_NAME} -e "SELECT Q.LAST_INSTALLED_VERSION FROM (SELECT INET_ATON(CONCAT(value, REPEAT('.0', 3 - CHAR_LENGTH(value) + CHAR_LENGTH(REPLACE(value, '.', ''))))) as VERSION_ATON, value as LAST_INSTALLED_VERSION FROM llx_const WHERE name IN ('MAIN_VERSION_LAST_INSTALL', 'MAIN_VERSION_LAST_UPGRADE') and entity=0) Q ORDER BY VERSION_ATON DESC LIMIT 1" > /tmp/lastinstall.result 2>&1
    r=$?
    if [[ ${r} -ne 0 ]]; then
      initializeDatabase
    else
      INSTALLED_VERSION=`grep -v LAST_INSTALLED_VERSION /tmp/lastinstall.result`
      echo "Last installed Version is : ${INSTALLED_VERSION}"
      if [[ "$(echo ${INSTALLED_VERSION} | cut -d. -f1)" -lt "$(echo ${DOLIBARR_VERSION} | cut -d. -f1)" ]]; then
        migrateDatabase
      else
        echo "Schema update is not required ... Enjoy !!"
      fi
    fi

    lockInstallation
  fi
}

# prefix variables to avoid conflicts and run parse url function on arg url
PREFIX="DOLIBARR_DB_" parseDatabaseURI "$DATABASE_URL"

# Separate host and port
DOLIBARR_DB_HOST="$(echo $DOLIBARR_DB_HOSTPORT | sed -e 's,:.*,,g')"
DOLIBARR_DB_PORT="$(echo $DOLIBARR_DB_HOSTPORT | sed -e 's,^.*:,:,g' -e 's,.*:\([0-9]*\).*,\1,g' -e 's,[^0-9],,g')"

run

set -e

if [ "${1#-}" != "$1" ]; then
  set -- apache2-foreground "$@"
fi

exec "$@"
