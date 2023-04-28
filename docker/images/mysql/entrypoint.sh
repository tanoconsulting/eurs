#!/bin/sh

echo "[$(date)] Bootstrapping MySQL..."

clean_up() {
    # Perform program exit housekeeping
    echo "[$(date)] Stopping the service..."
    pkill --signal term mysqld
    if [ -f /var/run/bootstrap_ok ]; then
        rm /var/run/bootstrap_ok
    fi
    echo "[$(date)] Exiting"
    exit
}

# Allow any process to see if bootstrap finished by looking up this file
if [ -f /var/run/bootstrap_ok ]; then
    rm /var/run/bootstrap_ok
fi

# Fix UID & GID for user 'mysql'

echo "[$(date)] Fixing filesystem permissions..."

ORIGPASSWD=$(cat /etc/passwd | grep mysql)
ORIG_UID=$(echo $ORIGPASSWD | cut -f3 -d:)
ORIG_GID=$(echo $ORIGPASSWD | cut -f4 -d:)
ORIG_HOME=$(echo "$ORIGPASSWD" | cut -f6 -d:)
CONTAINER_USER_UID=${CONTAINER_USER_UID:=$ORIG_UID}
CONTAINER_USER_GID=${CONTAINER_USER_GID:=$ORIG_GID}

if [ "$CONTAINER_USER_UID" != "$ORIG_UID" -o "$CONTAINER_USER_GID" != "$ORIG_GID" ]; then
    # note: we allow non-unique user and group ids...
    groupmod -o -g "$CONTAINER_USER_GID" mysql
    usermod -o -u "$CONTAINER_USER_UID" -g "$CONTAINER_USER_GID" mysql
fi
if [ $(stat -c '%u' "/var/lib/mysql") != "${CONTAINER_USER_UID}" -o $(stat -c '%g' "/var/lib/mysql") != "${CONTAINER_USER_GID}" ]; then
    chown -R "${CONTAINER_USER_UID}":"${CONTAINER_USER_GID}" "/var/lib/mysql"
    #chown -R "${CONTAINER_USER_UID}":"${CONTAINER_USER_GID}" "/var/log/mysql"
    # $HOME is set to /home/mysql, but the dir does not exist...
fi

chown -R mysql:mysql /var/run/mysqld

if [ -d /tmpfs ]; then
    chmod 0777 /tmpfs
fi

# if required, fix db server config (run db-config.sh)
if [ -f /home/test/teststack/bin/setup/db-config.sh ]; then
    /home/test/teststack/bin/setup/db-config.sh
fi

echo "[$(date)] Handing over control to /entrypoint.sh..."

trap clean_up TERM

if [ -f /usr/local/bin/docker-entrypoint.sh ]; then
    /usr/local/bin/docker-entrypoint.sh $@ &
else
    /entrypoint.sh $@ &
fi

# wait until mysql is ready to accept connections over the network before saying bootstrap is finished
# we impose no timeout here, but have one in in the teststack script, which checks for that file
which mysqladmin 2>/dev/null
if [ $? -eq 0 ]; then
    while ! mysqladmin ping -h 127.0.0.1 --silent; do
        sleep 1
    done
fi

echo "[$(date)] Bootstrap finished" | tee /var/run/bootstrap_ok

tail -f /dev/null &
child=$!
wait "$child"
