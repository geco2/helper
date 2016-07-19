#!/usr/local/bin/bash

MAX_SNAPSHOTS=48


VERSION="0.1"
DATE="09.09.2014"
AUTHOR="Andreas Eisenreich"
CONTACT="andi@nanuc.de"
FUNCTION="create and roll over zfs snapshots. Please provide one directory stored on a zfs volume."
USAGE="[option] <directory>"
SCRIPT="${0}"
SCRIPT_NAME="$(basename "${SCRIPT}")"
SCRIPT_SHORTNAME="${SCRIPT_NAME%.sh}"
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/${SCRIPT_SHORTNAME}.log"
LOCK_FILE="/var/run/${SCRIPT_SHORTNAME}}"
LOGFILES_AGE_DAYS=14 #Keep the logs 14 days
PRINTHELP_OPTIONS=""

BASE_LIB="$(dirname ${SCRIPT})/base_lib.sh"
if [ -f ${BASE_LIB} ];then
. ${BASE_LIB}
else
	echo "ERROR: Not able to use the standard BASE libary [${BASE_LIB}]!"
    exit 1
fi
##################################################################
# CONFIGURATION
if [ -z "${DEBUG}" ]; then
DEBUG="0"
fi
if [ -z "${FORCE}" ]; then
FORCE="0"
fi
if [ -z "${DRYRUN}" ]; then
DRYRUN="0"
fi

##################################################################
# Parse command line arguments
while getopts dfnh option
do
	case $option in
		d)		DEBUG="1";;
		f)		FORCE="1";;
		n)		DRYRUN="1";;
		h)		func_printhelp;exit 0;;
	
	esac
done

shift $(($OPTIND-1))

if [ $1 ]; then
	FOLDER=$1
else
	func_printhelp
	exit 1
fi


func_checklog

##################################################################
# Get filesystem
func_msg DEBUG "Check if [${FOLDER}] is a valid ZFS file system (zfs list -H -o name ${FOLDER})"
FILESYSTEM=$(zfs list -H -o name ${FOLDER} 2>&1)
RC=$?
if [ ${RC} -ne 0 ]; then
	func_msg ERROR "Please provide a filesystem or a directory stored on a zfs volume"
	exit 1
fi
MOUNTPOINT=$(zfs get -H -o value "mountpoint" ${FILESYSTEM})

##################################################################
# Create a snapshot
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M")
func_msg DEBUG "Check if we already have an snapshot for this minute [${TIMESTAMP}]"
ls -d ${MOUNTPOINT}/.zfs/snapshot/${TIMESTAMP} >/dev/null 2>&1
RC=$?
if [ ${RC} -eq 0 ];then
	func_msg INFO "We already have an snapshot for [$TIMESTAMP]"
	exit 0
fi

func_msg DEBUG "Create snapshot (zfs snapshot ${FILESYSTEM}@${TIMESTAMP})"
if [ ${DRYRUN} -eq 0 ];then
	RETURN=`sync 2>&1`
	RC=$?
	if [ ${RC} -ne 0 ];then
		func_msg ERROR "Filesystem syncronization issue [sync]"
		func_msg ERROR "Message: ${RETURN}"
	fi
	
	RETURN=$(zfs snapshot ${FILESYSTEM}@${TIMESTAMP} 2>&1)
	RC=$?
	if [ ${RC} -ne 0 ];then
		func_msg ERROR "Not able to create a snapshot for ${FILESYSTEM}"
		func_msg ERROR "Message: ${RETURN}"
		exit 1
	fi
else
	func_msg INFO "Dryrun is enabled... Skip snapshot creation."
fi


##################################################################
# roll snapshots
FILES=$(ls -1 ${MOUNTPOINT}/.zfs/snapshot/)
FILES_COUNT=$(echo "${FILES}" | wc -l)
NOT_NEEDED=$(( ${FILES_COUNT} - ${MAX_SNAPSHOTS} ))


if [ ${NOT_NEEDED} -gt 0 ];then
	TO_BE_DELETED=$(echo "${FILES}" | head -${NOT_NEEDED})
	func_msg DEBUG "found [${FILES_COUNT}] snapshots - max is [${MAX_SNAPSHOTS}] - going to delete [${NOT_NEEDED}]"
	
	for FILE in ${TO_BE_DELETED};do
		if [ ${DRYRUN} -eq 0 ];then
			func_msg DEBUG "Remove snapshot ${FILESYSTEM}@${FILE}"
			RETURN=$(zfs destroy ${FILESYSTEM}@${FILE} 2>&1 )
			RC=$?
			if [ ${RC} -ne 0 ];then
				func_msg ERROR "Not able to delete snapshot [${FILESYSTEM}@${FILE}]"
				func_msg ERROR "Message: ${RETURN}"
				exit 1
			fi
		else
			func_msg INFO "Dryrun is enabled. Snapshot [${FILESYSTEM}@${FILE}] is not deleted."
		fi
	done
else
	func_msg DEBUG "found [${FILES_COUNT}] snapshots - max is [${MAX_SNAPSHOTS}] - nothing to do."
fi
