#!/bin/bash

set -e
BACKUP_NAME="Backup_"$(date +%Y%m%dT%H%M%S)

. /home/ubuntu/iudx-resource-server/single-node/.env

mkdir -p /root/backup
rm -rf /root/backup/*
docker exec -i mongo /usr/bin/mongodump -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --db resource_server --out=$BACKUP_NAME
if [ $? -eq 0 ]; then
	docker cp mongo:/$BACKUP_NAME .
	echo "Zipping the dump file."
	tar -zcvf $BACKUP_NAME.tar.gz $BACKUP_NAME
	rm -rf $BACKUP_NAME
	mv $BACKUP_NAME.tar.gz /root/backup
	docker exec -d mongo rm -rf $BACKUP_NAME
	exit 0
else
	exit 1
fi
