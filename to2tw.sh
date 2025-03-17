#!/bin/bash

OBSIDIANDIR="~/Documents/obsidian/"
IFS=$'\n'

MD_LIST=$(find ${OBSIDIANDIR} | grep .md$)

for FILE in ${MD_LIST};do
    TASKS=$(grep '\- \[ \] [[:alnum:]].*' ${FILE})
    RC=$?
    if [ ${RC} -eq 0 ];then
        echo ${FILE}
        for TASK in ${TASKS};do
            TASK_CLEAN=$(echo ${TASK} | sed 's/\- \[ ] //g')
            echo $TASK_CLEAN
            #### ADD TO TASKARRIOR ###
            task add +obsidian ${TASK_CLEAN}
            gsed -i "s/\- \[ ] ${TASK_CLEAN}/\- \[x] ${TASK_CLEAN} #importedtw/g" ${FILE} 

        done
    fi
done
