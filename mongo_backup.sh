#!/bin/bash

set -e

CATALOGUE_SERVER_URL="pudx.catalogue.iudx.org.in"
RESOURCE_SERVER_URL="resource-server.iudx.org.in"
ANALYTICS_SERVER_URL="video.iudx.org.in"
SERVER_TO_BACKUP=$1
timestamp=$(date +%Y-%m-%dT%H:%M:%S)
USERNAME=root
alert_bot_token=`cat tokens.json | jq -r .alert_bot`
chat_command_token=`cat tokens.json | jq -r .chat_command`
date

minor_alert() {
    curl -XPOST "https://slack.com/api/chat.postMessage" -H "Authorization: Bearer ${1}" -H "Content-Type: application/json" -d '{"channel": "'${2}'", "text": "'"${3}"'", "as_user": "false", "username": "alert-bot"}'
}

major_alert(){
	curl -X POST -H 'Content-type: application/json' -H "Authorization: Bearer ${1}" --data '{"channel":"'${2}'","command": "/email", "text": "'"${3}"'"}' "https://slack.com/api/chat.command"
}

backup() 
{
    	if [ $1 == "catalogue" ] ; then
    	        SERVER_URL=$CATALOGUE_SERVER_URL
    	elif [ $1 == "resource" ]; then
    	        SERVER_URL=$RESOURCE_SERVER_URL
		CHANNEL=standby-server
		CHANNEL_NO=`jq '.channels[] | select(.name=="standby-server") | .number' channel_info.json`
		TEAM=standby_server_team
    	elif [ $1 == "analytics" ]; then
    	        SERVER_URL=$ANALYTICS_SERVER_URL
		CHANNEL=analytics-server
		CHANNEL_NO=`jq '.channels[] | select(.name=="analytics-server") | .number' channel_info.json`
		TEAM=analytics_team
    	fi
	
	mkdir -p /home/ubuntu/Backups/$SERVER_TO_BACKUP

    	ROOT_BACKUP_DIR=/home/ubuntu/Backups/$SERVER_TO_BACKUP    

	NO_OF_BACKUPS=`ls -1 $ROOT_BACKUP_DIR | wc -l`

	if [ $NO_OF_BACKUPS -gt 1 ]; then	
    		#Get the current hot backup filename for comparison
		HOT_BACKUP=$(ls -t $ROOT_BACKUP_DIR/ | head -1)
	fi

    	echo "Backing up MongoDB $SERVER_TO_BACKUP Server Database: $SERVER_URL"
    	echo "Dumping MongoDB data to compressed archive..."
    	
    	if ssh $USERNAME@$SERVER_URL ./run_mongodump.sh; then 
    	    echo "Copying archive data and cleaning compressed archive..."
   	    
    	    if rsync -azhe ssh $USERNAME@$SERVER_URL:/root/backup/ $ROOT_BACKUP_DIR --remove-source-files ; then	
		if [ $NO_OF_BACKUPS -gt 1 ]; then	
			LATEST_BACKUP=$(ls -t $ROOT_BACKUP_DIR/ | head -1)
    	    		new_size=`gzip -l $ROOT_BACKUP_DIR/$LATEST_BACKUP | awk 'FNR == 2 {print $2}'`
    	       		old_size=`gzip -l $ROOT_BACKUP_DIR/$HOT_BACKUP | awk 'FNR == 2 {print $2}'`
			threshold=$((10 * 1024 * 1024))
			difference=$(($old_size - $new_size))
    	        	if [ $difference -ge $threshold ] ; then
				echo $timestamp" Standby Server: Latest MongoDB Backup Size is at least 100MB smaller than the previous backup. Take action if needed."
				minor_alrt $alert_bot_token $CHANNEL $timestamp" Standby Server: Latest MongoDB Backup Size is at least 100MB smaller than the previous backup. Take action if needed."
				major_alert $chat_command_token $CHANNEL_NO "$TEAM/all/Latest Backup Size dropped drastically/"$timestamp" Standby Server: Latest MongoDB Backup Size is at least 100MB smaller than the previous backup. Take action if needed."
    	        	fi
    	        	
			echo "$SERVER_TO_BACKUP Server Backup complete."
    	        	echo "Cleaning archives older than 6 hours."
			COLD_BACKUP=`ls -t $ROOT_BACKUP_DIR | tail -1`
			rm $ROOT_BACKUP_DIR/$COLD_BACKUP
		fi
    	        echo "Backup complete!"
    	    else
    	        echo $timestamp" Standby Server: Syncing remote backup with local failed. Check logs for more information. Backup failed!"
    	        minor_alert $alert_bot_token $CHANNEL $timestamp" Standby Server: Syncing remote backup with local failed. Check logs for more information. Backup failed!"
    	    fi
    	else
    	    echo $timestamp" Standby Server: Collecting dump failed. Check logs for more information. Backup failed!"
    	    minor_alert $alert_bot_token $CHANNEL $timestamp" Standby Server: Collecting dump failed. Check logs for more information. Backup failed!"
    	fi
}

if [ $SERVER_TO_BACKUP == "catalogue" ]; then
    backup "catalogue"
elif [ $SERVER_TO_BACKUP == "resource" ]; then
    backup "resource" 
elif [ $SERVER_TO_BACKUP == "analytics" ]; then
    backup "analytics" 
else
	echo "Invalid Arguments!"
fi
