#!/usr/bin/bash

##############################
### Drupal Deploy and Sync ###
###    Created by Goose    ###
### Maintained by PraviinM ###
##############################


#############################
#### SET THESE VARIABLES ####
####=====================####
#### Hostname or IP Addr ####
#############################

who_am_i="PROD"	# DEV/STAGE/PROD

prod_file_host="prod-files"
prod_db_host="prod-db"

stage_file_host="stage-files"
stage_db_host="stage-db"

dev_file_host="dev-files"
dev_db_host="dev-db"

#############################
####   File Server Dir   ####
#############################

# Defaults used in variables

# Main Dir:	/opt/deploy/

# Repo Dir:	main_dir/repo_name
# Config:	repo_dir/_config
# Files:	repo_dir/_data
# DB Dumps:	repo_dir/_mysql
# Drupal Code:	repo_dir/src

# Script Dir:	main_dir/_scripts
# Script Logs:	script_dir/logs

#############################
#############################


#################
### Variables ###
#################

## General ##
where_am_i=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
main_dir="/opt/deploy"
repo_name=""
code_dir="src"
script_dir="_scripts"
log_dir="$script_dir/logs"
cron_pb=0
git_diffs=0
log_cron="cron"

## Deploy ##
git_pull=0
build_site=0
conf_dir="_config"
conf_file="settings.php"
drupal_sites_dir="sites/default"
drupal_files_dir="$drupal_sites_dir/files"
apache_dir="/var/www"
git_dir=".git"

## Environment ##
src_env=""
dst_env="$who_am_i"
prod_env="PROD"
stage_env="STAGE"
dev_env="DEV"

## Sync ##
sync_files=0
files_root="_data"
files_dir="$files_root/files"
sync_mysql=0
mysql_dir="_mysql"
mysql_ext=".latest.sql"
mysql_env=""
drush_bin="./vendor/bin/drush"

## Error ##
repo_err="ERROR: Please specify repo"
exist_err="ALERT: Repo does not exist yet. Make directories? (y/n): "
dir_create="Setup git before running this script again."
git_err="ERROR: GIT is not setup yet for repo"
env_err="ERROR: Please specify environment"
same_err="ERROR: Please specify different environments"
prod_prompt="ALERT: You are about to make changes to $prod_env. Are you sure? (y/n): "
src_err="ERROR: Source environment unknown"
dest_err="ERROR: Destination environment unknown"
no_diffs="Skipping Pulling Code - No Changes"


#################
### Functions ###
#################

usage () {
	cat << EOF
$0 can pull the latest code from git and sync files/db between environments

General Options:
    -h			Shows this message
    -r [repo_name]	Set git repository name - Required
    -c			Set for cron auto pull and build

Deployment Options:
    -p			Pull latest code from git
    -b			Build site from code using composer

Sync Options:
    -s [src_env]	Sync from source environment
    -f			Sync files from source environment
    -m			Sync database from source environment

Requirements:
    Flag '-r [repo_name]' is required
    Flag '-s [src_env]' is required when syncing
    git, composer, rsync, mysql and tee installed
    ssh keys shared between all servers
    .my.cnf files setup on mysql servers

Assumptions:
    File structure identical between hosts - $main_dir
    $0 should be run on server with code and files
    $0 modified for DEV, STAGE and PROD hosts

Defaults:
    Default directory for git repositories is $main_dir
    Default logs  directory is $main_dir/$log_dir
    Default code  directory is $main_dir/repo_name/$code_dir
    Default conf  directory is $main_dir/repo_name/$conf_dir
    Default files directory is $main_dir/repo_name/$files_dir
    Default mysql directory is $main_dir/repo_name/$mysql_dir
    Default mysql file name is repo_name$mysql_ext

Examples:
    Deploy:	$0 -r test_repo -pb
    Sync:	$0 -r test_repo -s PROD -fm
    Both:	$0 -r test_repo -pbfm -s PROD
    Cron:	*/5 * * * * $where_am_i/$(basename "$0") -r test_repo -c
EOF
}

createrepo () {
	echo "Creating Directories"
	mkdir -p "$workdir"/{"$conf_dir","$files_dir","$mysql_dir","$code_dir/$drupal_sites_dir"}
	create_links
}

create_log () {
	if [[ $cron_pb = 1 ]]; then
		logname="$log_cron-$repo_name-$(date '+%Y%m%d-%H%M').log"
	else
		logname="$repo_name-$(date '+%Y%m%d-%H%M').log"
	fi
	logfile="$main_dir/$log_dir/$logname"
}

setworkdir () {
	workdir="$main_dir/$repo_name"
}

check_diff () {
	! $(git -C "$workdir/$code_dir/" diff --quiet) && git_diffs=1
	if [[ $cron_pb = 1 ]] && [[ $git_diffs = 0 ]]; then
		# No git diffs = no need to pull or build when running from cron
		exit
	fi
}

findsrcenv () {
	if [ "${src_env^^}" = $prod_env ]; then
		src_fhost=$prod_file_host
		src_mhost=$prod_db_host
		mysql_env="$prod_env.sql"
	elif [ "${src_env^^}" = $stage_env ]; then
		src_fhost=$stage_file_host
		src_mhost=$stage_db_host
		mysql_env="$stage_env.sql"
	elif [ "${src_env^^}" = $dev_env ]; then
		src_fhost=$dev_file_host
		src_mhost=$dev_db_host
		mysql_env="$dev_env.sql"
	else
		echo "$src_err"
		exit 1
	fi
}

finddstenv () {
	if [ "${dst_env^^}" = $prod_env ]; then
		dest_mhost=$prod_db_host
	elif [ "${dst_env^^}" = $stage_env ]; then
		dest_mhost=$stage_db_host
	elif [ "${dst_env^^}" = $dev_env ]; then
		dest_mhost=$dev_db_host
	else
		echo "$dest_err"
		exit 1
	fi
}

echoenvvar () {
	echo "------------------------------------------------------------"
	echo "Repo: $repo_name"
	echo "------------------------------------------------------------"
	echo "Log File: $logfile"
	echo "Working Dir: $workdir"
	if [[ -n $src_env ]]; then
		echo ""
		echo "Source Env: ${src_env^^}"
		echo "Source File Server: $src_fhost"
		echo "Source DB Server: $src_mhost"
	fi
	if [[ -n $dst_env ]]; then
		echo ""
		echo "Destination Env: ${dst_env^^}"
		echo "Destination DB Server: $dest_mhost"
	fi
	echo ""
}

deploy_git () {
	if [[ $git_pull = 1 ]] || [[ $build_site = 1 ]] || [[ $cron_pb = 1 ]]; then
		echo "------------------------------------------------------------"
		echo "Deploying Site: $repo_name"
		echo "------------------------------------------------------------"
		echo ""
	fi
	if ([[ $git_pull = 1 ]] || [[ $cron_pb = 1 ]]) && [[ $git_diffs = 1 ]]; then
		pull_code
	else
		echo "$no_diffs"
		echo ""
	fi
	if [[ $build_site = 1 ]] || ([[ $cron_pb = 1 ]] && [[ $git_diffs = 1 ]]); then
		run_composer
	fi
}

pull_code () {
	echo "Pulling Latest Code"
	cd $workdir/$code_dir
	git pull
	echo ""
	create_links
}

create_links () {
	echo "Linking Config and Files Directory"
	conf_link="$workdir/$code_dir/$drupal_sites_dir/$conf_file"
	files_link="$workdir/$code_dir/$drupal_files_dir"
	apache_link="$apache_dir/$repo_name"
	[[ ! -L ${conf_link} ]] && ln -s $workdir/$conf_dir/$conf_file $conf_link
	[[ ! -L ${files_link} ]] && ln -s $workdir/$files_dir $files_link
	echo "Linking Apache Directory"
	[[ ! -L ${apache_link} ]] && ln -s $workdir/$code_dir $apache_link
	echo ""
}

run_composer () {
	echo "Running Composer"
	cd $workdir/$code_dir
	#composer update
	composer install
	$drush_bin cr
	echo ""
}

sync_stuff () {
	if [[ $sync_files = 1 ]] || [[ $sync_mysql = 1 ]]; then
		echo "------------------------------------------------------------"
		echo "Syncing: $repo_name from $src_env to $dst_env"
		echo "------------------------------------------------------------"
		echo ""
	fi

	[[ $sync_files = 1 ]] && rsync_files
	[[ $sync_mysql = 1 ]] && rsync_db
}

rsync_files () {
	echo "Syncing Files from $src_env"
	rsync -avh --stats --delete $src_fhost:$workdir/$files_dir $workdir/$files_root/
	echo ""
}

rsync_db () {
	echo "Syncing DB from $src_env"
	rsync -avhL --stats $src_mhost:$workdir/$mysql_dir/$repo_name$mysql_ext $workdir/$mysql_dir/$repo_name-$mysql_env
	echo ""
	echo "Importing DB to $dst_env"
	mysql -s $dest_mhost $repo_name < $workdir/$mysql_dir/$repo_name-$mysql_env
	[[ $? = 0 ]] && drush_update
}

drush_update () {
	echo ""
	echo "Updating DB with DRUSH"
	cd $workdir/$code_dir
	$drush_bin updb -y
	echo ""
}


##################
### Pre-Flight ###
##################

# Get Flags
while getopts "r:s:hcpbfm" opt; do
	case ${opt} in
		h ) usage
		    exit ;;
		r ) repo_name=${OPTARG} ;;
		c ) cron_pb=1 ;;
		p ) git_pull=1 ;;
		b ) build_site=1 ;;
		s ) src_env=${OPTARG} ;;
		#d ) dst_env=${OPTARG} ;;
		f ) sync_files=1 ;;
		m ) sync_mysql=1 ;;
		\?) exit 1 ;; # Invalid Option
		: ) exit 1 ;; # Missing Argument
	esac
done

# Check for Nothing
[[ -z "${1}" ]] && usage && exit

# Check for Repo
[[ -z "${repo_name}" ]] && echo "$repo_err" && exit 1

# Verify Repo Dir
if [ ! -d "$main_dir/$repo_name/$code_dir" ]; then
	read -p "$exist_err" -n 1 -r
	echo ""
	[[ ! $REPLY =~ ^[yY]$ ]] && exit 1
	setworkdir
	createrepo
	echo "$dir_create"
	exit
fi

# Verify Repo Git
[ ! -d "$main_dir/$repo_name/$code_dir/$git_dir" ] && echo "$git_err" && exit 1

# Check Sync Environment
if ([[ $sync_files = 1 ]] || [[ $sync_mysql = 1 ]]) && ([[ -z "${src_env}" ]] || [[ -z "${dst_env}" ]]); then
	echo "$env_err"
	exit 1
fi

# Check Same Environment
if [[ ${src_env^^} = ${dst_env^^} ]] && [[ -n $src_env ]]; then
	echo "$same_err"
	exit 1
fi

# Catch PROD Destination
if [[ ${dst_env^^} = $prod_env ]]; then
	read -p "$prod_prompt" -n 1 -r
	echo ""
	[[ ! $REPLY =~ ^[yY]$ ]] && exit 1
fi


###############
### Do Work ###
###############

create_log
setworkdir
check_diff
[[ -n $src_env ]] && findsrcenv
[[ -n $dst_env ]] && finddstenv
echoenvvar | tee -aip $logfile
deploy_git | tee -aip $logfile
sync_stuff | tee -aip $logfile

# Going Back Home
cd $where_am_i
