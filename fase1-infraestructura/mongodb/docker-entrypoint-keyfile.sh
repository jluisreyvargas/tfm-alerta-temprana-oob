#!/bin/bash
# Arregla permisos del keyFile antes de arrancar mongod
cp /tmp/mongo-keyfile /etc/mongodb/mongo-keyfile
chown mongodb:mongodb /etc/mongodb/mongo-keyfile
chmod 400 /etc/mongodb/mongo-keyfile
exec docker-entrypoint.sh "$@"
