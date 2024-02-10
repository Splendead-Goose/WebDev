#!/usr/bin/bash

#############################
### Rotate Database Dumps ###
###   Created by: Goose   ###
#############################

# Assumes .my.cnf is setup for user
# Pop in crontab for auto backup

#################
### Variables ###
#################

maindir="/opt/deploy"
mysqldir="_mysql"
dumpext="$(date +"%Y%m%d").sql"
latestext="latest.sql"
retention=7


#################
### Functions ###
#################

dumpdb () {
	mysqldump $1 > $maindir/$1/$mysqldir/$1.$dumpext
	[[ $? = 0 ]] && symlink $1
}

symlink () {
	unlink $maindir/$1/$mysqldir/$1.$latestext
	ln -s $maindir/$1/$mysqldir/$1.$dumpext $maindir/$1/$mysqldir/$1.$latestext
	[[ $? = 0 ]] && cleanup $1
}

cleanup () {
	find $maindir/$1/$mysqldir/ -type f -mtime +$retention -name '*.sql' -delete
}


###############
### Do Work ###
###############

dumpdb "dbname1"
dumpdb "dbname2"

# Add more dbs above - dbname should exist in maindir
