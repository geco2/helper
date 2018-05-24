#!/usr/bin/env bash

MAX=50
MAX_P=5
DISPLAY_REFRESH=2

LOG=$$.csv

BASE_LIB="./base_lib.sh"
if [ -f ${BASE_LIB} ];then
	. ${BASE_LIB}
else
	echo "ERROR: Not able to use the standard BASE libary [${BASE_LIB}]!"
	exit 1
fi
func_checklog

if [ -z "${DEBUG}" ]; then
    DEBUG="0"
fi
if [ -z "${FORCE}" ]; then
    FORCE="0"
fi
if [ -z "${DRYRUN}" ]; then
    DRYRUN="0"
fi
if [ -z "${PFORKS}" ];then
    PFORKS="0"
fi
if [ -z "${KEEPLOG}" ];then
    KEEPLOG="0"
fi
if [ -z "${VERBOSE}" ];then
    VERBOSE="0"
fi
if [ -z "${JOBS}" ];then
    JOBS="0"
fi

START_TIME=$(date "+%s")

function func_help
{
cat << EOF
$0 is a helper for parallel jobs in bash
Usage:
    $0 [-dn] [-r SEC_REFRESH_OUTPUT] [-j] [-p] COMMAND

Examples:
    $0 -j 10 -v -n
    $0 -p 5 -j 10 -m results.csv -v ./deploy_aws.sh 2

Options:
        -d              Enable debugging (igonres COMMAND)
        -n              Dry run - Fork slepp jobs
        -i              Refresh interval for status output
        -p              Amount of parallel forks
        -j              Amount of JOBS performed 
        -v              Display progress

If -p is not given the amount of parallel forks is randomized (up to ${MAX_P})
If -j is not defined a random number will be used (up to ${MAX})

BEWARE: Please ensure propper logging of commands used to fork. Any output is suppressed!
EOF
}
##################################################################
# Parse command line arguments
while getopts dnhvr:p:j:m: option
do
        case $option in
                d)              DEBUG="1";;
                n)              DRYRUN="1";;
                i)              DISPLAY_REFRESH="${OPTARG}";;
                j)              JOBS="${OPTARG}";;
                p)              PFORKS="${OPTARG}";;
                m)              LOG="${OPTARG}";KEEPLOG="1";;
                v)              VERBOSE="1";;
                h)              func_help;exit 0;;

        esac
done

shift $(($OPTIND-1))
COMMAND=$*

function func_duration
{
    local CMD=$*

    local BEGIN=$(date "+%s")
    ${CMD} 2>/dev/null 1>&2
    RC=$?
    local END=$(date "+%s")
    
    local DURATION=$(( ${END} - ${BEGIN} ))

    echo -n ${RC} ${DURATION}
}

function func_do
{
     local NAME=$1

    if [ ${DRYRUN} -eq 1 ];then
        local DURATION=$(func_duration "sleep $(func_rand 20)")
    else
        if [ ${#COMMAND} -ne 0 ];then
            local DURATION=$(func_duration ${COMMAND})
        else
            func_msg ERROR "Not able to run \"${COMMAND}\""
            exit 1
        fi
    fi

    local DURATION=$(echo ${DURATION} | cut -d " " -f 2)
    
    local DURATION_HUMAN=$(func_displaytime ${DURATION})
    local DATE=$(date "+%Y;%m;%d;%H;%M;%S")
    local DATES=$(date "+%s")

    echo "${DATES}${DATE};${NAME};${RC};${DURATION};${DURATION_HUMAN}" >>${LOG}
}

function func_rand
{
    local MAX=$1
    local RAND=0; while [ "$RAND" -le 1 ];do RAND=$RANDOM; let "RAND %= ${MAX}";done
    echo -n ${RAND}
}

function func_create_name
{
    local TYPE=$1
    local SEQ=$(date "+%Y%m%d%H%M%S")
    local RAND=$(func_rand 100)

    echo ${TYPE}${SEQ}${RAND}

}

function func_displaytime
{
    local T=$1
    local D=$((T/60/60/24))
    local H=$((T/60/60%24))
    local M=$((T/60%60))
    local S=$((T%60))

    if [[ $D > 0 ]];then
        echo -n "${D} days ";
    fi
    if [[ $H > 0 ]];then
        echo -n "${H} hours ";
    fi
    if [[ $M > 0 ]];then
        echo -n "${M} minutes ";
    fi

    if [[ $D > 0 || $H > 0 || $M > 0 ]];then
        echo -n "and "
    fi
    echo "${S} seconds"
}

if [ ${JOBS} -eq "0" ];then
    NRTODEPLOY=$(func_rand ${MAX})
else
    NRTODEPLOY=${JOBS}
fi

ALL=${NRTODEPLOY}
i=0
i2=0

while [ ${NRTODEPLOY} -gt 0 ];do
    if [ ${PFORKS} -eq "0" ];then
        NRTODEPLOY_P=$(func_rand ${MAX_P})
    else
        NRTODEPLOY_P=${PFORKS}
    fi

    if [ ${NRTODEPLOY_P} -gt ${NRTODEPLOY} ];then
        NRTODEPLOY_P=${NRTODEPLOY}
        func_msg DEBUG "Reduce to ${NRTODEPLOY} jobs"
    fi
    i=${NRTODEPLOY_P}

    while [ ${i} -gt 0 ];do
        VMNAME[${i2}]=$(func_create_name)
        func_msg DEBUG "func_do ${VMNAME[${i2}]}"
        func_do ${VMNAME[${i2}]} &
        JOBID[${i2}]=$(jobs -l | tail -1 | awk '{print $2}')
        i2=$(( ${i2} + 1 ))
        i=$(( ${i} - 1 ))             
    done

    while true; do
        PROCEED=${#JOBID[@]}
        i=0
        if [ ${VERBOSE} -eq 1 ];then
            if [ ${DEBUG} -eq 0 ];then
                clear
            fi
            echo "-----------------------------------------------------------"
            if [ ${DRYRUN} -eq 0 ];then
                echo "Running forks for \"${COMMAND}\""
            else
                echo "DRYRUN - Random sleep mode"
            fi
            echo "-----------------------------------------------------------"
            func_msg DEBUG "Job IDs: ${JOBID[*]}"
            for JOB in ${JOBID[*]};do
                if [ -f ${LOG} ];then
                    JOBRC=$(grep ";${VMNAME[${i}]};" ${LOG} | cut -d ";" -f 8)
                fi
                if [ ${#JOBRC} -gt 0 ];then
                    func_msg LIST "${VMNAME[${i}]} [${JOBRC}]"
                    if [ ${JOBRC} -eq 0 ];then
                        func_msg LIST OK
                        PROCEED=$(( ${PROCEED} - 1 ))
                    else
                        func_msg LIST ERROR
                        PROCEED=$(( ${PROCEED} - 1 ))
                    fi
                else
                    func_msg LIST "${VMNAME[${i}]}"
                    func_msg LIST WORKING
                fi
                i=$(( ${i} + 1 ))
            done
            if [ ${PROCEED} -eq 0 ];then
                break
            fi
            echo "-----------------------------------------------------------"
            echo -e "Jobs: \t\t\t${NRTODEPLOY}/${ALL}"
            echo -e "Running: \t\t${NRTODEPLOY_P}"
            if [ -f ${LOG} ];then
                LATEST=$(tail -1 ${LOG} | cut -d ";" -f 10)
                echo -e "Max. last deployment: \t${LATEST}"
            fi
            echo "-----------------------------------------------------------"
            sleep ${DISPLAY_REFRESH}
        else
            for JOB in ${JOBID[*]};do
                JOBRC=$(grep ${VMNAME[${i}]} ${LOG} | cut -d ";" -f 8)
                if [ ${#JOBRC} -gt 0 ];then
                    PROCEED=$(( ${PROCEED} - 1 ))
                fi
                i=$(( ${i} + 1 ))
            done
            if [ ${PROCEED} -eq 0 ];then
                break
            fi
        fi
    done

    NRTODEPLOY=$(( ${NRTODEPLOY} - ${NRTODEPLOY_P} ))
done
    END_TIME=$(date "+%s")
    DURATION=$(( ${END_TIME} - ${START_TIME} ))
    DURATION=$(func_displaytime ${DURATION})
    if [ ${VERBOSE} -eq 1 ];then
        echo "-----------------------------------------------------------"
        echo -e "Jobs done: \t\t${ALL}"
        echo -e "Duration:  \t\t${DURATION}"
        echo "-----------------------------------------------------------"
    fi

if [ ${KEEPLOG} -eq 0 ];then
    rm ${LOG}
fi
