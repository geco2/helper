#!/bin/bash
##################################################################
# Base functions library
#
BASE_LIB_AUTHOR="Andreas Eisenreich"
BASE_LIB_CONTACT="andi@nanuc.de"
BASE_LIB_DATE="09.05.2012"
BASE_LIB_VERSION="0.0.1"
BASE_LIB_FUNCTION="A basic functios lib"
#
##################################################################

# USAGE
#
# Please source this library at the beginning of a script before
# define any variable!
###########################
# EXAMPLE USAGE:
###########################
# BASE_LIB="/usr/local/lib/BASE_lib.sh"
# if [ -f ${BASE_LIB} ];then
# 	. ${BASE_LIB}
# else
# 	echo "ERROR: Not able to use the standard BASE libary [${BASE_LIB}]!"
#	exit 1
# fi
###########################
# The following Configuration has to be done in each script that
# Source the BASE library set:
# SCRIPT="${0}"
# SCRIPT_NAME="$(basename "${SCRIPT}")"
# SCRIPT_SHORTNAME="${SCRIPT_NAME%.sh}"
# LOG_DIR="<insert_log_dir>" #Example directory: /var/log
# LOG_FILE="${LOG_DIR}/${SCRIPT_SHORTNAME}.log"
# LOCK_FILE="<insert_lockfile>" #Example: /var/run/${SCRIPT_SHORTNAME}
# LOGFILES_AGE_DAYS=14 #Keep the logs 14 days
# PRINTHELP_OPTIONS="f		force"
##################################################################

##################################################################
# CONFIGURATION
if [ -z "${DEBUG}" ]; then
	DEBUG="0"
fi
if [ -z "${SILENT}" ]; then
	SILENT="0"
fi
if [ -z "${FORCE}" ]; then
	FORCE="0"
fi
if [ -z "${DRYRUN}" ]; then
	DRYRUN="0"
fi

##################################################################
# FUNCTIONS
function func_checklog ()
{
if [ ! -d "${LOG_DIR}" ]; then
        echo "INFO    - Log directory ${LOG_DIR} not found."
        echo "INFO    - try to create logdir."
        mkdir -p ${LOG_DIR} 2>/dev/null; RC=$?
        if [[ "${RC}" != "0" ]];then
                echo "WARNING - Log directory creation failed. Set LOG_FILE to [/dev/null]."
                LOG_FILE=/dev/null
                return
        fi
else
        touch ${LOG_FILE} 2>/dev/null; RC=$?
        if [[ "${RC}" != "0" ]];then
                echo "WARNING - Can\`t write on LOG_FILE [${LOG_FILE}]. Set LOG_FILE to [/dev/null]."
                LOG_FILE=/dev/null
        else
                #rm ${LOG_FILE}
		if [ "$(uname)" == "FreeBSD" ];then
                	LOGFILES_AGE_DATE=$(date -v-${LOGFILES_AGE_DAYS}d +%Y%m%d%H%M)
		else
			LOGFILES_AGE_DATE=$(date --date="${LOGFILES_AGE_DAYS} days ago" +%Y%m%d%H%M)
		fi
                LOGFILES_AGE_TMP_FILE="/tmp/find_flag_$$"
                touch -amt ${LOGFILES_AGE_DATE} ${LOGFILES_AGE_TMP_FILE}; RC=$?
                if [[ "${RC}" != "0" ]]; then
                        echo "ERROR: Can\`t write ${LOGFILES_AGE_TMP_FILE}"
                        RC=1; exit
                fi
                LOGFILES_TO_DELETE=$(find ${LOG_DIR} -maxdepth 1 -type f ! -newer ${LOGFILES_AGE_TMP_FILE} -name "${SCRIPT_SHORTNAME}.log")
                rm -f ${LOGFILES_AGE_TMP_FILE} ${LOGFILES_TO_DELETE} >/dev/null; RC=$?
                if [[ "${RC}" != "0" ]];then
                        echo "WARNING - Can\`t delete all the old Logfiles"
                fi
        fi
fi
}

function func_msg()
{
        # Available msg types:
        # $1                                                            $2
        # LIST                                                          OK,ERROR,FAILED,WARING,WORKING,MSG_RESULT*,<MESSAGE>
        # INFO,VINFO,ERROR,FAILED,WARING        <MESSAGE>
        # LOG                                                           <MESSAGE>

        MSG_TYPE="$1"
        MSG="$2"
        MSG_CHAR="."
        MSG_FILLUP=" "
        MSG_LISTWITH_MAX="200"
        MSG_DEL="\b\b\b\b\b\b\b\b\b\b\b"
        MSG_DATE=$(date '+%b %d %Y %H:%M:%S')

        MSG_TERMWITH=$(tput cols); RC=$?
        if [[ "${RC}" != "0" ]]
        then
                MSG_TERMWITH="80"
        fi
        MSG_LISTWITH=$(( ${MSG_TERMWITH} - 12 )) #12 == [   OK   ]
        if (( ${MSG_LISTWITH} < 0 )) || (( ${MSG_LISTWITH} > ${MSG_LISTWITH_MAX} ));then
                MSG_LISTWITH=${MSG_LISTWITH_MAX}
        fi

        if [[ ${LOG_FILE} != "" ]]; then
                if [[ "${MSG_TYPE}" = "LOG" ]]; then
                        echo -e "${MSG}" |sed -e "s/^/${MSG_DATE} ${USER} ${HOSTNAME} [$$] : /g" >> ${LOG_FILE}
                        return
                else
                        echo -e "${MSG_DATE} ${USER} ${HOSTNAME} [$$] : ${MSG_TYPE} : ${MSG}" >> ${LOG_FILE}
                fi
        fi

        if [ "${DEBUG}" -eq "0" ] && [ "${SILENT}" -eq "0" ];then
                case ${MSG_TYPE} in
                        INFO)           if [[ "${LISTMODE}" = "open" ]]; then
                                                                echo -e "${MSG_DEL}[   \033[1;32mOK\033[0m    ]"
                                                                LISTMODE="closed"
                                                        fi
                                                        echo -e "${MSG_TYPE}    - ${MSG}"
                                                        ;;
                        VINFO)          if [[ "${VERBOSE}" = "1" ]]; then
                                                                if [[ "${LISTMODE}" = "open" ]]; then
                                                                        echo -e "${MSG_DEL}[   \033[1;32mOK\033[0m    ]"
                                                                        LISTMODE="closed"
                                                                fi
                                                                echo -e "INFO    - ${MSG}"
                                                        fi
                                                        ;;
                        ERROR)          if [[ "${LISTMODE}" = "open" ]]; then
                                                                echo -e "${MSG_DEL}[  \033[1;31mERROR\033[0m  ]"
                                                                LISTMODE="closed"
                                                                CHAPTER_FAILED="FAILED"
                                                        fi
                                                        echo -e "${MSG_TYPE}   - ${MSG}"
                                                        ;;
                        FAILED)                 if [[ "${LISTMODE}" = "open" ]]; then
                                                                echo -e "${MSG_DEL}[ \033[1;31mFAILED\033[0m  ]"
                                                                LISTMODE="closed"
                                                                CHAPTER_FAILED="FAILED"
                                                        fi
                                                        echo -e "${MSG_TYPE}   - ${MSG}"
                                                        ;;
                        WARNING)        if [[ "${LISTMODE}" = "open" ]]; then
                                                                echo -e "${MSG_DEL}[ \033[1;33mWARNING\033[0m ]"
                                                                LISTMODE="closed"
                                                        fi
                                                        echo -e "${MSG_TYPE} - ${MSG}"
                                                        ;;
                esac

                if [[ "${MSG_TYPE}" = "LINE" ]]; then
                        if [[ ${MSG} != "" ]]; then
                                MSG_FILLUP=""
                                MSG_BCOUNT=$(( ${MSG_TERMWITH} - 1 ))
                                MSG_i=0
                                while (( ${MSG_i} < ${MSG_BCOUNT} )); do
                                        MSG_FILLUP="${MSG_FILLUP}${MSG}"
                                        MSG_i=$(( ${MSG_i} + 1))
                                done
                                echo ${MSG_FILLUP}
                        else
                                echo
                        fi
                fi

                if [[ "${MSG_TYPE}" = "CHAPTER" ]]; then
                        if [[ "${CHAPTER_INFOS}" = "" ]]; then
                                CHAPTER_INFOS="func_msg LIST \"${MSG}\""
                        else
                                echo
                                CHAPTER_INFOS="${CHAPTER_INFOS}\nfunc_msg LIST ${CHAPTER_FAILED}"
                                CHAPTER_INFOS="${CHAPTER_INFOS}\nfunc_msg LIST \"${MSG}\""
                        fi
                        CHAPTER_FAILED="PASSED"
                        echo -e "\033[1;34m${MSG}:\033[0m"
                fi

                if [[ "${MSG_TYPE}" = "SUMMARY" ]]; then
                        echo -e "\n\033[1;35m${MSG}:\033[0m"
                        CHAPTER_INFOS="${CHAPTER_INFOS}\nfunc_msg LIST ${CHAPTER_FAILED}"
                        eval "$(echo -e "${CHAPTER_INFOS}")"
                        return
                fi

                if [[ "${MSG_TYPE}" = "LIST" ]] || [[ "${MSG_TYPE}" = "VLIST" && "${VERBOSE}" = "1" ]];then
                        if [[ "${LISTMODE}" = "open" ]]; then
                                case $MSG in
                                        OK)             echo -e "${MSG_DEL}[   \033[1;32mOK\033[0m    ]"
                                                                        LISTMODE="closed"
                                                                        ;;
                                        PASSED)                 echo -e "${MSG_DEL}[ \033[1;32mPASSED\033[0m  ]"
                                                                        LISTMODE="closed"
                                                                        ;;
                                        ERROR)          echo -e "${MSG_DEL}[  \033[1;31mERROR\033[0m  ]"
                                                                        LISTMODE="closed"

                                                                        ;;
                                        FAILED)          echo -e "${MSG_DEL}[ \033[1;31mFAILED\033[0m  ]"
                                                                        LISTMODE="closed"
                                                                        ;;
                                        WARNING)        echo -e "${MSG_DEL}[ \033[1;33mWARNING\033[0m ]"
                                                                        LISTMODE="closed"
                                                                        ;;
                                        NA)                     echo -e "${MSG_DEL}[   N/A   ]"
                                                                        LISTMODE="closed"
                                                                        ;;
					WORKING)	echo -e "${MSG_DEL}[ working ]"
									LISTMODE="closed"
									;;
                                        MSG_RESULT*)    NEW_MSG=$(echo ${MSG} |sed -e 's/MSG_RESULT //')
                                                                        MSG_SPACE=$(( 10 - $(echo ${NEW_MSG} |wc -c)))
                                                                        if (( "${MSG_SPACE}" < "0" ))
                                                                        then
                                                                                func_msg LIST OK
                                                                                func_msg INFO "Result: ${NEW_MSG}"
                                                                        fi
                                                                        echo -en "${MSG_DEL}["
                                                                        case $MSG_SPACE in
                                                                                0) echo -e "${NEW_MSG}]";;
                                                                                1) echo -e " ${NEW_MSG}]";;
                                                                                2) echo -e " ${NEW_MSG} ]";;
                                                                                3) echo -e "  ${NEW_MSG} ] ";;
                                                                                4) echo -e "  ${NEW_MSG}  ] ";;
                                                                                5) echo -e "   ${NEW_MSG}  ] ";;
                                                                                6) echo -e "   ${NEW_MSG}   ] ";;
                                                                                7) echo -e "    ${NEW_MSG}   ] ";;
                                                                                8) echo -e "    ${NEW_MSG}    ] ";;
                                                                        esac
                                                                        LISTMODE="closed"
                                                                        ;;
                                esac
                        elif [[ "${MSG}" != "OK" ]] && [[ "${MSG}" != "ERROR" ]] && [[ "${MSG}" != "FAILED" ]] && [[ "${MSG}" != "WARNING" ]] && [[ "${MSG}" != "WORKING" ]]; then
                                MSG_COUNT=`echo ${MSG} | wc -c`
                                MSG_BCOUNT=$(( ${MSG_LISTWITH} - ${MSG_COUNT} - 1 ))
                                while (( ${MSG_BCOUNT} < "1" ));do
                                        MSG_BCOUNT=$((${MSG_BCOUNT} + ${MSG_TERMWITH}))
                                done
                                MSG_i=0
                                while (( ${MSG_i} < ${MSG_BCOUNT} )); do
                                        MSG_FILLUP="${MSG_FILLUP}${MSG_CHAR}"
                                        MSG_i=$(( ${MSG_i} + 1))
                                done
                                echo -en "${MSG}${MSG_FILLUP} [ working ]"
                                LISTMODE="open"
                        fi
                fi
        elif [[ ${DEBUG} = "1" ]]; then
                echo  "${MSG_TYPE}: ${MSG}" 1>&2
#       elif [[ ${SILENT} = "1" ]] && [[ "${MSG_TYPE}" = "INFO" || "${MSG_TYPE}" = "WARNING" || "${MSG_TYPE}" = "ERROR" ]]; then
        elif [[ ${SILENT} = "1" ]] && [[ "${MSG_TYPE}" = "WARNING" || "${MSG_TYPE}" = "FAILED" || "${MSG_TYPE}" = "ERROR" ]]; then
                echo  "${MSG_TYPE};${MSG}"; SILENT_ERROR="1"
        fi
}

function func_lock()
{
		MODE=$1
		EXITCODE=$2
		if [[ -z "${EXITCODE}" ]];
		then
			EXITCODE="0"
		fi

		func_msg DEBUG "Start function func_lock in mode [${MODE}] exitcode [${EXITCODE}]"

		if [ ${MODE} == "on" ];then
			if [ -f ${LOCK_FILE} ];then
				func_msg INFO "Another ${SCRIPT_SHORTNAME} is currently running"
				func_msg INFO "Lock file: [${LOCK_FILE}]"

				if [ ${FORCE} -eq "1" ];then
					func_msg INFO "${SCRIPT_SHORTNAME} started in force mode! proceed..."
				else
					exit "${EXITCODE}"
				fi
			else
				func_msg DEBUG "Create lock file [${LOCK_FILE}]"
				touch ${LOCK_FILE} 2>/dev/null
				RC=$?
				if [ ${RC} -ne "0" ];then
					func_msg ERROR "Not able to create lock file [${LOCK_FILE}]"
					exit 1
				fi
			fi
		fi

		if [ ${MODE} == "off" ];then
			func_msg DEBUG "Remove lock file [${LOCK_FILE}]"
			rm ${LOCK_FILE} 2>/dev/null
			RC=$?
			if [ ${RC} -ne "0" ];then
				func_msg ERROR "Not able to remove lock file [${LOCK_FILE}]"
				exit 1
			fi
		fi
}

function func_printhelp()
{
cat <<EO_HELP
${SCRIPT_SHORTNAME} version ${VERSION} date ${DATE}
Author: ${AUTHOR} <${CONTACT}>

${SCRIPT_SHORTNAME} ${FUNCTION}

Usage: ${SCRIPT_NAME} ${USAGE}

Options:
	-h		Print this [h]elp message.
	-d		[D]ebug mode on.
	-n		Enable Dryru[n] mode.
	-f		[F]orce mode on.
	-v		Print script [v]ersion.
${PRINTHELP_OPTIONS}
EO_HELP

}

#$(echo -e "${PRINTHELP_OPTIONS}")

function func_cleanup()
{
	func_msg LIST "Run clean up"

	func_msg DEBUG "run \"rm -rf ${PUPPET_CONF_DIR_TMP_DIR}\""
	OUTPUT=$(rm -rf ${PUPPET_CONF_DIR_TMP_DIR} 2>&1)
	RC=$?
	if [ ${RC} -ne "0" ];then
		func_msg ERROR "${OUTPUT}"
		func_lock off
		exit 1
	else
		func_msg LIST "OK"
	fi
}

function func_BASE_LIB_check_var()
{
	BASE_LIB_VAR=$1

	if [ ${#BASE_LIB_VAR} -eq "0" ];then
		return 1
	else
		return 0
	fi
}

