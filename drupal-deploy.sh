#!/usr/bin/bash

##############################
### Drupal Deploy and Sync ###
###    Created by Goose    ###
##############################


#############################
#### SET THESE VARIABLES ####
####=====================####
#### Hostname or IP Addr ####
#############################

prod_file_host="prod-files"
prod_db_host="prod-db"

stage_file_host="stage-files"
stage_db_host="stage-db"

dev_file_host="dev-files"
dev_db_host="dev-db"

#############################
#############################
#############################


#################
### Variables ###
#################

## General ##
script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
work_path="/opt/deploy/"
repo_path="/opt/deploy/"
repo_name=""
log_dir="$script_dir/logs"

## Deploy ##
git_pull=0
build_site=0

## Environment ##
src_env=""
dest_env=""
prod_env="PROD"
stage_env="STAGE"
dev_env="DEV"

## Sync ##
sync_files=0
files_dir="sites/default/files"
sync_mysql=0
mysql_dir="$work_path/mysql/"
mysql_ext=".latest.sql"
mysql_cur=".sync.sql"

## Error ##
repo_err="ERROR: Please specify repo"
env_err="ERROR: Please specify environment"
same_err="ERROR: Please specify different environments"
src_err="ERROR: Source environment unknown"
dest_err="ERROR: Destination environment unknown"


#################
### Functions ###
#################

usage () {
	cat << EOF
$0 can pull the latest code from git and sync files/db between environments

General Options:
    -h			Shows this message
    -g [repos_dir]	Set directory for git repositories
    -r [repo_name]	Set git repository name - Required
    -l [logs_dir]	Set logging directory for output

Deployment Options:
    -p			Pull latest code from git
    -b			Build site from code using composer

Sync Options:
    -s [src_env]	Sync FROM source environment
    -d [dest_env]	Sync TO destination environment
    -f			Sync files from source environment
    -m			Sync database from source environment

Requirements:
    Flag '-r [repo_name]' is required
    Flag '-s [src_env]' and '-d [dest_env]' are required when sycning
    git, composer, rsync, mysql and tee installed
    ssh keys shared between all servers
    .my.cnf files setup on mysql servers
    File structure identical between hosts
    $0 should be run on server with code and files
    $0 modified for DEV, STAGE and PROD hosts

Defaults:
    Default directory for git repositories is $repo_path
    Default log directory is $log_dir
    Default files directory is $files_dir
    Default mysql directory is $mysql_dir
    Default mysql file name is repo$mysql_ext

Examples:
    Deploy:	$0 -r test_repo -pb
    Sync:	$0 -r test_repo -s PROD -d DEV -fm
    Both:	$0 -r test_repo -pbfm -s PROD -d DEV
    Overrides:	$0 -g /opt/deploy/git/ -r test_repo -l /opt/deploy/logs/ -pb -s PROD -d DEV -fm
EOF
}

create_log () {
	logname="$repo_name-$(date '+%Y%m%d-%H%M').log"
	logfile="$log_dir/$logname"
}

setworkdir () {
	echo "Setting Working Directory"
	workdir=$repo_path/$repo_name
	echo "Working Dir: $workdir"
	echo ""
}

findsrcenv () {
	if [[ -n $src_env ]]; then
		echo "Getting Environment Source"
		if [ "${src_env^^}" = $prod_env ]; then
			echo "Source: $prod_env"
			src_fhost=$prod_file_host
			src_mhost=$prod_db_host
		elif [ "${src_env^^}" = $stage_env ]; then
			echo "Source: $stage_env"
			src_fhost=$stage_file_host
			src_mhost=$stage_db_host
		elif [ "${src_env^^}" = $dev_env ]; then
			echo "Source: $dev_env"
			src_fhost=$dev_file_host
			src_mhost=$dev_db_host
		else
			echo "$src_err"
			exit 1
		fi
		echo "Source File Server: $src_fhost"
		echo "Source DB Server: $src_mhost"
		echo ""
	fi
}

finddstenv () {
	if [[ -n $dest_env ]]; then
		echo "Getting Environment Destination"
		if [ "${dest_env^^}" = $prod_env ]; then
			echo "Dest: $prod_env"
			dest_fhost=$prod_file_host
			dest_mhost=$prod_db_host
		elif [ "${dest_env^^}" = $stage_env ]; then
			echo "Dest: $stage_env"
			dest_fhost=$stage_file_host
			dest_mhost=$stage_db_host
		elif [ "${dest_env^^}" = $dev_env ]; then
			echo "Dest: $dev_env"
			dest_fhost=$dev_file_host
			dest_mhost=$dev_db_host
		else
			echo "$dest_err"
			exit 1
		fi
		echo "Destination File Server: $dest_fhost"
		echo "Destination DB Server: $dest_mhost"
		echo ""
	fi
}

deploy_git () {
	if [[ $git_pull = 1 ]] || [[ $build_site = 1 ]]; then
		echo "Deploying Site: $repo_name"
		echo ""
	fi

	if [[ $git_pull = 1 ]]; then
		pull_code
	fi

	if [[ $build_site = 1 ]]; then
		run_composer
	fi
}

pull_code () {
	echo "Pulling Latest Code"
	echo ""
	#cd $workdir
	#git pull
}

run_composer () {
	echo "Running Composer"
	echo ""
	#cd $workdir
	#composer update
	#composer install
}

sync_stuff () {
	if [[ $sync_files = 1 ]] || [[ $sync_mysql = 1 ]]; then
		echo "Syncing: $repo_name in $dest_env with $src_env"
		echo ""
	fi

	if [[ $sync_files = 1 ]]; then
		rsync_files
	fi

	if [[ $sync_mysql = 1 ]]; then
		rsync_db
	fi
}

rsync_files () {
	echo "Syncing Files from $src_env"
	echo ""
	#rsync -avh --stats --delete $src_fhost:$workdir/$files_dir $dest_fhost:$workdir/$files_dir/
}

rsync_db () {
	echo "Syncing DB from $src_env"
	echo ""
	#rsync -avhL --stats --delete $src_mhost:$mysql_dir/$repo$mysql_ext $dest_mhost:$mysql_dir/$repo$mysql_cur
	#mysql -s $dest_mhost $repo < $dest_mhost:$mysql_dir/$repo$mysql_cur
	drush_update
}

drush_update () {
	echo "Updating DB with DRUSH"
	echo ""
	#drush updb -y
}


##################
### Pre-Flight ###
##################

# Get Flags
while getopts "g:r:l:s:d:hpbfm" opt; do
	case ${opt} in
		h ) usage
		    exit ;;
		g ) repo_path=${OPTARG} ;;
		r ) repo_name=${OPTARG} ;;
		l ) log_dir=${OPTARG} ;;
		p ) git_pull=1 ;;
		b ) build_site=1 ;;
		s ) src_env=${OPTARG} ;;
		d ) dest_env=${OPTARG} ;;
		f ) sync_files=1 ;;
		m ) sync_mysql=1 ;;
		\?) exit 1 ;; # Invalid Option
		: ) exit 1 ;; # Missing Argument
	esac
done

# Check for Nothing
if [[ -z "${1}" ]]; then
	usage
	exit
fi

# Check for Repo
if [[ -z "${repo_name}" ]]; then
	echo "$repo_err"
	exit 1
fi

# Check Sync Environment
if ([[ $sync_files = 1 ]] || [[ $sync_mysql = 1 ]]) && ([[ -z "${src_env}" ]] || [[ -z "${dest_env}" ]]); then
	echo "$env_err"
	exit 1
fi

# Check Same Environment
if [[ $src_env = $dest_env ]] && [[ -n $src_env ]]; then
	echo "$same_err"
	exit 1
fi


###############
### Do Work ###
###############

create_log
setworkdir | tee -a $logfile
findsrcenv | tee -a $logfile
finddstenv | tee -a $logfile
deploy_git | tee -a $logfile 
sync_stuff | tee -a $logfile
