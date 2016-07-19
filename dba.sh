#!/usr/bin/env bash

###################################################
# dba.sh (Docker Binary assistant)
#
# Description:  Helper for creating docker images
#
# Author:       Andreas Eisenreich <andi@nanuc.de>
# Version:      0.1
# History:
#       07.04.2016    Initial version
###################################################
# GLOBAL CONFIGURATION
SCRIPT="${0}"
SCRIPT_NAME="$(basename "${SCRIPT}")"
SCRIPT_SHORTNAME="${SCRIPT_NAME%.sh}"
SCRIPT_DIR=$(cd $(dirname "${SCRIPT}");pwd; cd - >/dev/null)
LOG_DIR="/var/log"
#LOG_FILE="${LOG_DIR}/${SCRIPT_SHORTNAME}.log"
LOCK_FILE="/var/run/${SCRIPT_SHORTNAME}"
LOGFILES_AGE_DAYS=14 #Keep the logs 14 days
BASE_LIB="${SCRIPT_DIR}/base_lib.sh"
PRINTHELP_OPTIONS="  "

DEBUG=0
BATCH=0

###################################################
# SOURSE BASELIB
if [ -f ${BASE_LIB} ];then
        . ${BASE_LIB}
else
        echo "ERROR: Not able to use the standard BASE libary [${BASE_LIB}]!"
        exit 1
fi

#########################################################
# BINARY
function func_get_binary ()
{
  func_msg LIST "Identifiy binary location"

  PROC=$1
  RESULT=$(echo ${PROC} | grep "^/")
  RC=$?
  if [ ${RC} -ne 0 ];then
    PROC=$(whereis -b ${PROC} | awk '{print $2}')
    RC=$?
    if [ ${RC} -eq 0 ]; then
        func_msg LIST "OK"
    else
        echo "Error no binary found with (whereis -b ${PROC})"
        exit 1
    fi
  else
    if [ -f ${PROC} ];then
        func_msg LIST "OK"
    else
        func_msg ERROR "\"${PROC}\" seems to be not a file."
        exit 1
    fi
  fi
}

#########################################################
# CHROOT PATH
function func_check_chroot ()
{
    func_msg LIST "Check chroot directory"
    
    DIRECTORY=$1
    
    RESULT=$(echo "${DIRECTORY}" | grep "^/")
    RC=$?
    func_msg DEBUG "Check if the user uses a complete path. (${RESULT})"
    if [ ${RC} -eq 0 ] && [ -d ${DIRECTORY} ] && [ ${DIRECTORY} != "/" ]; then
        CHROOT_PATH=$(echo ${DIRECTORY} | sed 's/\/$//')
        func_msg LIST "OK"
    else
       echo "ERROR: (${DIRECTORY}) is not a valid chroot path"
    fi
}  

#########################################################
# IDENTIFY LIBS
function func_ident_libs ()
{
    func_msg LIST "Identify used libs:"
    RESULT=$(ldd ${PROC} 2>&1)
    RC=$?
    if [ ${RC} -eq 0 ];then
        RESULT=$(echo ${RESULT} | tr ' ' '\n'| grep "^/")
        for LIB in ${RESULT};do
            if [ ! -f ${CHROOT_PATH}${LIB} ]; then
                LIB_STATUS="${LIB_STATUS}LIBARY  : ${CHROOT_PATH}${LIB}\n"
                LIBS="${LIBS} ${LIB}"
            else
                LIB_STATUS="${LIB_STATUS}LIBARY  : ${CHROOT_PATH}${LIB} (Already available - skipped)\n"
            fi
            func_msg LIST "OK"
        done
    else
        func_msg ERROR "${RESULT}"
        func_msg INFO "Try to specifiy the full path to your binary."
        exit 1
    fi
}

#########################################################
# COPY
function func_copy ()
{
    func_msg LIST "Copy ${1} to ${2}"
    
    SOURCE=$1
    DESTINATION=$2
    DESTINATION_DIR=$(dirname ${DESTINATION})
        
    if [ -d ${CHROOT_PATH} ];then
        func_msg DEBUG "/bin/mkdir -pv ${DESTINATION_DIR}"
        RESULT=$(/bin/mkdir -pv ${DESTINATION_DIR} 2>&1)
        RC=$?
        if [ ${RC} -ne "0" ];then
            func_msg ERROR "Not able to create target directory \"${DESTINATION_DIR}\""
            func_msg ERROR "${RESULT}"
            exit 1
        fi
        func_msg DEBUG "${RESULT}"
    fi
    
    RESULT=$(/bin/cp -vf ${SOURCE} ${DESTINATION} 2>&1)
    RC=$?
    if [ ${RC} -ne "0" ];then
        func_msg ERROR "Not able to copy \"${SOURCE}\" to \"${DESTINATION}\""
        func_msg ERROR "${RESULT}"
    else
        func_msg DEBUG "${RESULT}"
        func_msg LIST "OK"
    fi
}

#########################################################
# Help
function func_help
{
cat <<EOF
${SCRIPT_NAME} is a helper for binary placement in Docker base images.

Usage:
        ${SCRIPT_NAME} [-b] <chroot pwd> <bin> ...
        
        Example: ${SCRIPT_NAME} /srv/docker/my_image ls vim fish /bin/bash

        -b | b        Batchmode, to be used from within other scripts
                      No user interaction at all 
        -h | h        This text
EOF
}

#########################################################
# MAIN
#func_checklog
case $1 in
    -b|b)       BATCH=1;
                SILENT=1;
                shift;
                ;;
    -h|h|help)   func_help;
                exit 0;
                ;;
esac

func_check_chroot $1
shift
if [ -z $1 ];then
    func_msg ERROR "Binary missing"
    func_help
    exit 1
fi
for BINARY in $*; do
    func_get_binary ${BINARY}
    func_ident_libs

    if [ ${BATCH} -eq "0" ];then
        echo -e "\nBinary  : ${CHROOT_PATH}${PROC}"
        echo -e "${LIB_STATUS}"
        echo "Do you want to install the binary and all necessary libs? [y/n]"
        read INPUT
        echo ""
    else
        INPUT="y"
    fi

    if [ ! -z ${INPUT} ] && [ ${INPUT} = "y" ];then
        func_copy ${PROC} ${CHROOT_PATH}${PROC}
    for LIB in ${LIBS}; do
        func_copy ${LIB} ${CHROOT_PATH}${LIB}
    done
    else
        func_msg INFO "Thank you for dryrun \"${PROC}\" in \"${CHROOT_PATH}\""
    fi
done
exit 0
