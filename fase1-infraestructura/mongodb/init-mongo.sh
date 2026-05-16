#!/bin/bash
# Espera a que MongoDB esté listo
until mongosh --quiet --eval "db.adminCommand('ping').ok" &>/dev/null; do
  echo "Waiting for MongoDB..."
  sleep 2
done

echo "MongoDB ready. Initializing replica set and users..."

mongosh admin << JSEOF
rs.initiate({_id:"rs0", members:[{_id:0, host:"mongodb:27017"}]});
sleep(2000);
db.createUser({
  user: "${MONGO_INITDB_ROOT_USERNAME}",
  pwd: "${MONGO_INITDB_ROOT_PASSWORD}",
  roles: [
    {role:"root", db:"admin"},
    {role:"clusterAdmin", db:"admin"}
  ]
});
JSEOF

echo "Init complete."
