#!/usr/bin/env bash
########################################
# ./backplace_backup.sh archive 1388904647 /backup/Backup/1388904647

TEMPDIR="/backup/tmp"
PGP_KEY="F32BBEE6"

ID=${RANDOM}
DATE=$(date '+%Y%m%d')
if [ ! -d ${TEMPDIR}/* ];then
    TEMPDIR="${TEMPDIR}/${DATE}"
else
    TEMPDIR="${TEMPDIR}/$(ls -1 ${TEMPDIR} | tail -1)"
    NUMBER_CHUNKS="$(ls -1 ${TEMPDIR}/chunk-* | wc -l | awk '{print $1}')"
    echo "INFO: Old local backup found... start upload ${TEMPDIR} - (${NUMBER_CHUNKS} chuncks)"
fi
CHUNK_NAME="chunk-"
MAX_UPLOAD_COUNT="999"
#MAX_UPLOAD_COUNT="1"
CONTENT_TYPE="application/octet-stream"
AUTH_FILE="/root/.backplace_auth"

##################################################################
# DEFAULTS
SCRIPT="${0}"
SCRIPT_NAME="$(basename "${SCRIPT}")"
SCRIPT_SHORTNAME="${SCRIPT_NAME%.sh}"
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/${SCRIPT_SHORTNAME}.log"
LOCK_FILE="/var/run/${SCRIPT_SHORTNAME}}"
LOGFILES_AGE_DAYS=14 #Keep the logs 14 days
PRINTHELP_OPTIONS="d		debug
n       dry run"

BASE_LIB="$(dirname ${SCRIPT})/base_lib.sh"
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

##################################################################
# HELP
function func_help {
cat <<EOF
$0 does a remote backup to backplace b2 for any directory or file

    Usage:
        $0  [-d|-n] <b2 vault> <archive description> <path to be backuped>

        -d      Turn on debug output
        -n      Dryrun (local opertaions only)

Example usage:
        $0 -d archive 1388904647 /backup/Backup/1388904647/

b2 credentials have to be configured for your user using b2 "authorize_account"
EOF

}

##################################################################
# Parse command line arguments
while getopts dnh option
do
	case $option in
		d)		DEBUG="1";;
		n)		DRYRUN="1";;
		h)		func_help;exit 0;;
	
	esac
done

shift $(($OPTIND-1))

BUCKETNAME=$1
ARCHIVE_NAME=$2
BACKUP=$3

if [ ! ${BUCKETNAME} ] || [ ! ${ARCHIVE_NAME} ] || [ ! ${BACKUP} ];then
    func_help
    exit 1
fi

##################################################################
# ACCOUNT
function func_authorize_account {
    func_msg DEBUG ":: Authorize Account: ${ACCOUNT_ID}"

    RETURN=$(curl -s https://api.backblaze.com/b2api/v1/b2_authorize_account -u "${ACCOUNT_ID}:${APPLICATION_KEY}")
    echo ${RETURN} |grep -q minimumPartSize
    RC=$?
    if [ ${RC} -ne 0 ];then
        func_msg ERROR "Not able to authenticate. Please check your account_id and application_key."
    else
        API_URL=$(echo "${RETURN}" | grep apiUrl | cut -d "\"" -f 4)
        ACCOUNT_AUTHORIZATION_TOKEN=$(echo "${RETURN}" | grep authorizationToken | cut -d "\"" -f 4)
        DOWNLOAD_URL=$(echo "${RETURN}" | grep downloadUrl | cut -d "\"" -f 4)
        MIN_PART_SIZE=$(echo "${RETURN}" | grep minimumPartSize | cut -d "\"" -f 4)
    fi

}

##################################################################
# HOUSEKEEPING
function func_housekeeping {
    func_msg DEBUG ":: Do housekeeping..."
    RETURN=$(rm -r ${TEMPDIR} 2>&1)
    #RETURN=$(true)
    RC=$?                                                                                                                  
    if [ ${RC} != "0" ];then                                                                                               
            func_msg ERROR "Can't remove dir \"${TEMPDIR}\". (${RETURN})"                                             
            exit 1                                                                                                         
    fi
}

##################################################################
# CREATE TMPDIR
function func_create_tempdir {
    func_msg DEBUG ":: Create temp dir (${TEMPDIR})"
    RETURN=$(mkdir -p ${TEMPDIR} 2>&1) 
    RC=$?
    if [ ${RC} != "0" ];then
            func_msg ERROR "Can't create dir \"${TEMPDIR}\". (${RETURN})"
            exit 1
    fi
}

##################################################################
# ARCHIVE/TAR
function func_create_archive {
    DIRECTORY="$1"
    func_msg DEBUG ":: Create archive: ${TEMPDIR}/${ARCHIVE_NAME}_${DATE}.tgz2"
    if [ ! -f ${TEMPDIR}/${ARCHIVE_NAME}_${DATE}.tgz2 ]; then
        #func_msg DEBUG "tar cjf ${TEMPDIR}/${ARCHIVE_NAME}_${DATE}.tgz2 \"${DIRECTORY}\""
        RESULT=$(env LC_ALL=C; tar cjf ${TEMPDIR}/${ARCHIVE_NAME}_${DATE}.tgz2 "${DIRECTORY}" 2>&1)
        RC=$?                                                                                                                 
        if [ ${RC} != "0" ];then                                                                                               
                echo "ERROR: Can't create archive"
                echo "ERROR: ${RESULT}"                               
                exit 1                                                                                                         
        fi
    else 
        func_msg DEBUG "File already exist"
    fi
    #func_msg DEBUG "$(ls -lh ${TEMPDIR}/${ARCHIVE_NAME}_${DATE}.tgz2)"
}

##################################################################
# SPLIT
function func_split {
        FILE=$1
        RETURN=""

        # Check for useful chunk size (min 100M max 5GB b2 definitions)
        FILE_SIZE=$(ls -l ${FILE} | awk '{print $5}')
        if [ ${FILE_SIZE} -ge 107374182400 ];then # from 100 GB
            SIZE="5G"
        elif [ ${FILE_SIZE} -ge 53687091200 ];then # from 50 GB
            SIZE="3G"
        elif [ ${FILE_SIZE} -ge 26843545600 ];then # from 25 GB
            SIZE="2G"
        elif [ ${FILE_SIZE}  -ge  10737418240 ];then # from 10 GB
             SIZE="1G"
        elif [ ${FILE_SIZE}  -ge  5368709120 ];then # from 5 GB
            SIZE="500M"
        elif [ ${FILE_SIZE}  -ge  2684354560 ];then # from 2,5 GB
            SIZE="250M"
        else
            SIZE="100M"
        fi

        func_msg DEBUG ":: Split archive (${FILE}) in ${SIZE} chunks"
        cd ${TEMPDIR}

        RETURN=$(split -b ${SIZE} -d ${FILE} ${CHUNK_NAME})
        RC=$?                                                                                                                 
        if [ ${RC} != "0" ];then                                                                                               
                echo "ERROR: Can't split archive"
                echo "ERROR: ${RETURN}"
                exit 1                                                                                                         
        fi
        NUMBER_CHUNKS=$(ls -1 ${CHUNK_NAME}* | wc -l)
        func_msg DEBUG "Created ${NUMBER_CHUNKS} x ${SIZE} chunks"

        cd - >/dev/null 2>&1
}

##################################################################
# CHECKSUM
function func_hash {
    FILES=( $(echo "$*") )
    INDEX=0

    FILE_COUNT=${#FILES[@]}
    func_msg DEBUG ":: Create checksum for ${FILE_COUNT} files"

    while [ ${INDEX} -lt ${FILE_COUNT} ]; do
        if [ ! -f "${FILES[${INDEX}]}-hash" ];then
            HASHES[${INDEX}]=$(openssl sha1 ${FILES[${INDEX}]} | awk '{print $2}')
            RC=$?
            if [ ${RC} != "0" ];then                                                                                               
                echo "ERROR: Hash creation failed"
                exit 1
            else
                    func_msg DEBUG "${FILES[${INDEX}]} - ${HASHES[${INDEX}]}"
                    HASH_JSON="${HASH_JSON} \"${HASHES[${INDEX}]}\", "
                    func_msg DEBUG "Write hash file (${FILES[${INDEX}]}-hash)"
                    echo ${HASHES[${INDEX}]} > ${FILES[${INDEX}]}-hash                                                                                            
            fi
        else
            func_msg DEBUG "Hash file found (${FILES[${INDEX}]}-hash)"
            HASHES[${INDEX}]=$(cat ${FILES[${INDEX}]}-hash | tr -d '\n')
            func_msg DEBUG "${FILES[${INDEX}]} - ${HASHES[${INDEX}]}"
            HASH_JSON="${HASH_JSON} \"${HASHES[${INDEX}]}\", "
        fi
        INDEX=$(( ${INDEX} + 1 ))
    done
    HASH_JSON=$(echo ${HASH_JSON} | sed 's/,$//g')
    #func_msg DEBUG "JSON Hash: (${HASH_JSON})"
}

##################################################################
# CHECK B2 BUCKET
# FIXIT b2 binary used
function func_b2_check_bucket {
    RETURN=""
    func_msg DEBUG ":: Check Backplace B2 bucket ${BUCKETNAME}"
#    RETURN=$(b2 list_buckets | grep "${BUCKETNAME}$")
     RETURN=$(curl -s -H "Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}" "${API_URL}/b2api/v1/b2_list_buckets?accountId=${ACCOUNT_ID}")
     echo ${RETURN} | grep -q "\"${BUCKETNAME}\","
    RC=$?
    if [ ${RC} != "0" ];then
            if [ ${DRYRUN} -eq 0 ];then
                func_msg INFO "Create Backplace B2 bucket ${BUCKETNAME}"
#                RETURN=$(b2 create_bucket ${BUCKETNAME} allPrivate)
		        RETURN=$(curl -s -H "Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}" "${API_URL}/b2api/v1/b2_create_bucket?accountId=${ACCOUNT_ID}&bucketName=${BUCKETNAME}&bucketType=allPrivate")
                RC=$?
                if [ ${RC} != "0" ];then
                        func_msg ERROR "bucket creation failed"
                        func_msg ERROR "${RETURN}"
                        exit 1
                fi
            else
                func_msg INFO "The used bucket ${BUCKETNAME} does not exist. Cration skipped (dry mode)"
            fi
    fi

    BUCKET_ID=$(echo ${RETURN} | tr '\n' ' ' | tr ']' '\n' | grep ${BUCKETNAME} | tr ',' '\n' | grep "bucketId" | cut -d ':' -f 2 | sed 's/\"//g')
    if [ ${#BUCKET_ID} -eq 0 ];then
        func_msg ERROR "Not able to get a valid bucket id."
        func_msg DEBUG "${BUCKET_ID}"
        exit 1
    fi
}

##################################################################
# CRYPT
function func_crypt {
        ARCHIVE="$1"
        RETURN=""

        func_msg DEBUG ":: Encrypt file ${ARCHIVE}"
        if [ ! -f ${ARCHIVE}.gpg ];then
            func_msg DEBUG "gpg --batch --trust-model always -q -e -r ${PGP_KEY} ${ARCHIVE}"
            RETURN=$(gpg --batch --trust-model always -q -e -r ${PGP_KEY} ${ARCHIVE} 2>&1)
            RC=$?
            if [ ${RC} != "0" ];then
                    func_msg ERROR "Crypto failed."
                    func_msg ERROR "${RETURN}"
                    exit 1
            fi
        else
            func_msg DEBUG "Crypted file already exists"
        fi
}

##################################################################
# INIT B2 MULTIUPLAD JOB CREATION
function func_b2_init_upload {
    DIRECTORY=$1
    BUCKET_ID=$2
    RETURN=""

    CHUNKSIZE=$(ls -l ${DIRECTORY}${CHUNK_NAME}00 | awk '{print $5}')

    func_msg DEBUG ":: Create b2 multipart upload job"
    #func_msg DEBUG "curl -H \"Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}\" -d \"`printf '{\"fileName\":\"%s\", \"bucketId\":\"%s\", \"contentType\":\"%s\"}' ${ARCHIVE_NAME} ${BUCKET_ID} ${CONTENT_TYPE}`\" \"${API_URL}/b2api/v1/b2_start_large_file\";\""
    if [ ${DRYRUN} -eq 0 ];then
        RETURN=$(curl -s -H "Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}" -d "`printf '{"fileName":"%s", "bucketId":"%s", "contentType":"%s"}' ${ARCHIVE_NAME} ${BUCKET_ID} ${CONTENT_TYPE}`" "${API_URL}/b2api/v1/b2_start_large_file" 2>&1)
        echo ${RETURN} | grep -q fileId
        RC=$?
        if [ ${RC} != "0" ];then
                func_msg ERROR "job creation failed"
                func_msg ERROR "ACCOUNT_AUTHORIZATION_TOKEN: \"${ACCOUNT_AUTHORIZATION_TOKEN:7}\""
                func_msg ERROR "ARCHIVE_NAME: \"${ARCHIVE_NAME}\""
                func_msg ERROR "BUCKET_ID: \"${BUCKET_ID}\""
                func_msg ERROR "CONTENT_TYPE: \"${CONTENT_TYPE}\""
                func_msg ERROR "API_URL: \"${API_URL}\""
                func_msg ERROR "${RETURN}"
                exit 1
        else
            FILE_ID=$(echo "${RETURN}" | grep fileId | cut -d "\"" -f4)
        fi
    else 
        FILE_ID="00FAKE00"
    fi
    func_msg DEBUG "FileID: ${FILE_ID}"
}

##################################################################
# GET UPLOAD URL
function func_b2_get_upload_url {
    FILE_ID=$1
    RETURN=""
    
    func_msg DEBUG ":: Get Upload URL"
    #func_msg DEBUG "curl -s -H \"Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}\" -d \"`printf '{\"fileId\":\"%s\"}' ${FILE_ID}`\" \"${API_URL}/b2api/v1/b2_get_upload_part_url\""
    if [ ${DRYRUN} -eq 0 ];then
        if [ ${#FILE_ID} -ge 1 ];then
            RETURN=$(curl -s -H "Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}" -d "`printf '{"fileId":"%s"}' ${FILE_ID}`" "${API_URL}/b2api/v1/b2_get_upload_part_url")
        else
            RETURN=$(curl -s -H "Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}" -d "`printf '{"bucketId":"%s"}' ${BUCKET_ID}`" "${API_URL}/b2api/v1/b2_get_upload_url")
        fi
        echo ${RETURN} | grep -q uploadUrl
        RC=$?
        if [ ${RC} != "0" ];then
    	    func_msg ERROR "job creation failed"
    	    func_msg ERROR "${RETURN}"
            func_abort_upload
    	    exit 1
        else
            UPLOAD_URL=$(echo "${RETURN}" | grep uploadUrl | cut -d "\"" -f4)
            UPLOAD_AUTHORIZATION_TOKEN=$(echo "${RETURN}" | grep authorizationToken | cut -d "\"" -f4)
        fi
    else
        UPLOAD_URL="DRYRUN_FAKE_URL"
        UPLOAD_AUTHORIZATION_TOKEN="DRYRUN_AUTH_TOKEN"
    fi
    func_msg DEBUG "UploadURL: ${UPLOAD_URL}"
    func_msg DEBUG "Upload Auth: ${UPLOAD_AUTHORIZATION_TOKEN}"

}

##################################################################
# UPLOAD
function func_b2_part_upload {
    UPLOAD_URL=$1
    shift
    CHUNKS=$*
    RETURN=""

    if [ $(echo ${CHUNKS} | wc -w) -eq 1 ];then
        SINGLE_UPLOAD=1
    else
        SINGLE_UPLOAD=0
    fi

    PART_NO=1
    INDEX=0
    COUNT=0

    for CHUNK in $(echo ${CHUNKS});do
        while [ ${COUNT} -le ${MAX_UPLOAD_COUNT} ]; do
            ACT_SIZE=$(ls -l ${CHUNK} | awk '{print $5}')
            if [ ${DRYRUN} -eq 0 ];then
                if [ ${SINGLE_UPLOAD} -eq 0 ];then
                    func_msg DEBUG ":: Multipart upload ${CHUNK}"
                    #func_msg DEBUG "curl -s -H \"Authorization: ${UPLOAD_AUTHORIZATION_TOKEN}\" -H \"X-Bz-Part-Number: ${PART_NO}\" -H \"X-Bz-Content-Sha1: ${HASHES[$INDEX]}\" -H \"Content-Length: ${ACT_SIZE}\" --data-binary \"@${CHUNK}\" ${UPLOAD_URL}"
                    RETURN=$(curl -s -H "Authorization: ${UPLOAD_AUTHORIZATION_TOKEN}" -H "X-Bz-Part-Number: ${PART_NO}" -H "X-Bz-Content-Sha1: ${HASHES[$INDEX]}" -H "Content-Length: ${ACT_SIZE}" --data-binary "@${CHUNK}" ${UPLOAD_URL} 2>&1)
                else
                    func_msg DEBUG ":: Singlefile upload ${CHUNK}"
                    RETURN=$(curl -s -H "Authorization: ${UPLOAD_AUTHORIZATION_TOKEN}" -H "X-Bz-File-Name: ${ARCHIVE_NAME}" -H "X-Bz-Content-Sha1: ${HASHES[$INDEX]}" -H "Content-Type: ${CONTENT_TYPE}" -H "X-Bz-Info-Author: unknown" --data-binary "@${CHUNK}" ${UPLOAD_URL} 2>&1)
                fi
                echo ${RETURN} | grep -q contentSha1
                RC=$?
                if [ ${RC} -ne 0 ];then
                    func_msg DEBUG "${CHUNK} - ${COUNT}/${MAX_UPLOAD_COUNT}"
                    func_msg DEBUG "Return: ${RETURN}"
    func_b2_get_upload_url ${FILE_ID} ##
                    COUNT=$(( ${COUNT} + 1 ))
                    if [ ${COUNT} -eq ${MAX_UPLOAD_COUNT} ];then
                    	func_msg ERROR "Not able to upload all chunks."
                        func_msg ERROR "Return: ${RETURN}"
                        func_abort_upload
                    	exit 1
    	            fi
                else
                    REMOTE_CHECKSUM=$(echo "${RETURN}" | grep contentSha1 | cut -d "\"" -f 4)
                    func_msg DEBUG "Remote checksum: ${REMOTE_CHECKSUM}"
                    if [ ${SINGLE_UPLOAD} -eq 1 ];then
                        FILE_NAME=$(echo "${RETURN}" | grep "fileName" | cut -d "\"" -f4)
                        FILE_ID=$(echo "${RETURN}" | grep "fileId" | cut -d "\"" -f4)
                    fi
                    break
                fi
            fi 
        done
        PART_NO=$(( ${PART_NO} + 1 ))
        INDEX=$(( ${INDEX} + 1 ))
        COUNT=0
    done
}

##################################################################
# CLOSE MULTI UPLOAD

function func_b2_close_upload {
    FILE_ID=$1
    RETURN=""

    func_msg DEBUG ":: Close b2 multi part upload."

    #func_msg DEBUG "curl -s -H \"Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}\" -d \"{ \"partSha1Array\": ${HASH_JSON}, \"fileId\":\"${FILE_ID}\"}\" \"${API_URL}/b2api/v1/b2_finish_large_file\""
    if [ ${DRYRUN} -eq 0 ];then
        RETURN=$(curl -s -H "Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}" -d "{ \"partSha1Array\": [ ${HASH_JSON} ], \"fileId\":\"${FILE_ID}\"}" "${API_URL}/b2api/v1/b2_finish_large_file")
        echo ${RETURN} | grep -q uploadTimestamp
        RC=$?
        if [ ${RC} != "0" ];then
            func_msg ERROR "close failed"
            func_msg ERROR "ACCOUNT_AUTHORIZATION_TOKEN: \"${ACCOUNT_AUTHORIZATION_TOKEN:7}\""
            func_msg ERROR "HASH_JSON: \"${HASH_JSON}\""
            func_msg ERROR "FILE_ID: \"${FILE_ID}\""
            func_msg ERROR "API_URL: \"${API_URL}\""
            func_msg ERROR "${RETURN}"
            exit 1
        else
            FILE_NAME=$(echo "${RETURN}" | grep "fileName" | cut -d "\"" -f4)
            FILE_ID=$(echo "${RETURN}" | grep "fileId" | cut -d "\"" -f4)
            func_housekeeping
        fi

    else
        FILE_ID="111FAKE111"
    fi
}

##################################################################
# ABORT UPLOAD
function func_abort_upload {
    RETURN=""

    func_msg ERROR ":: Aborting upload."

    if [ ${DRYRUN} -eq 0 ];then
        RETURN=$(curl -s -H "Authorization: ${ACCOUNT_AUTHORIZATION_TOKEN}" -d "`printf '{"fileId":"%s"}' ${FILE_ID}`" "${API_URL}/b2api/v1/b2_cancel_large_file";)
        RC=$?
        if [ ${RC} != "0" ];then
            func_msg ERROR "close failed"
            func_msg ERROR "${RETURN}"
            exit 1
        else
            func_msg DEBUG ${RETURN}
        fi
    else
        func_msg INFO "Abort dryrun"
        exit 1
    fi
}

##################################################################
# MAIN
trap func_abort_upload SIGINT SIGTERM

### Source credentials file ###
if [ ! -f ${AUTH_FILE} ];then
    func_msg ERROR "Please create a authentication file (${AUTH_FILE}) before using $0"
    func_msg INFO "The file have to contain at least two lines starting with \"ACCOUNT_ID=\" and \"APPLICATION_KEY=\" followed by your backplaze credentials"
else
    ACCOUNT_ID=$(grep ^ACCOUNT_ID= ${AUTH_FILE} | sed 's/^ACCOUNT_ID=//g')
    APPLICATION_KEY=$(grep ^APPLICATION_KEY= ${AUTH_FILE} | sed 's/^APPLICATION_KEY=//g')
    if [ ! ${#ACCOUNT_ID} -ge 1 ] && [ ! ${APPLICATION_KEY} -ge 1 ];then
        func_msg ERROR "Credentials in your authfile seem to be not ok. Please check ${AUTH_FILE}"
        exit 1
    fi
fi

### Local preperation ###
if [ ! -d ${TEMPDIR} ];then
	func_create_tempdir
	func_create_archive "${BACKUP}"
	func_crypt ${TEMPDIR}/${ARCHIVE_NAME}_${DATE}.tgz2

	func_split ${TEMPDIR}/${ARCHIVE_NAME}_${DATE}.tgz2.gpg
fi
func_hash $(ls -1 ${TEMPDIR}/${CHUNK_NAME}* | grep -v "hash$")

### Upload ###
func_authorize_account
func_b2_check_bucket
if [ ${NUMBER_CHUNKS} -gt 1 ];then
    func_msg DEBUG "func_b2_init_upload ${TEMPDIR}/ ${BUCKET_ID}"
    func_b2_init_upload ${TEMPDIR}/ ${BUCKET_ID}
    func_msg DEBUG "func_b2_get_upload_url ${FILE_ID}"
    func_b2_get_upload_url ${FILE_ID}
    func_msg DEBUG "func_b2_part_upload ${UPLOAD_URL} $(ls -1 ${TEMPDIR}/${CHUNK_NAME}??) "
    func_b2_part_upload ${UPLOAD_URL} $(ls -1 ${TEMPDIR}/${CHUNK_NAME}??) 
    func_msg DEBUG "func_b2_close_upload ${FILE_ID}"
    func_b2_close_upload ${FILE_ID}
else
    func_b2_get_upload_url
    func_msg DEBUG "func_b2_part_upload ${UPLOAD_URL} $(ls -1 ${TEMPDIR}/${CHUNK_NAME}??)"
    func_b2_part_upload ${UPLOAD_URL} $(ls -1 ${TEMPDIR}/${CHUNK_NAME}??)
fi

func_msg INFO "FileID: ${FILE_ID}"
func_msg INFO "Uploaded ${FILE_NAME} in bucket ${BUCKETNAME}"
