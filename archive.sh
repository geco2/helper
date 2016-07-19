#!/usr/local/bin/bash

TES_LANG="deu" # get a list using "tesseract --list-langs"

for FILE in *;do
	echo ${FILE} | grep -q .txt$ && continue
	FILE_N=`echo ${FILE} | cut -d "." -f 1`
	if [ ! -f ${FILE_N}.txt ];then
		echo -n "${FILE}:"
		tesseract -l ${TES_LANG} ${FILE} ${FILE_N} 2>/dev/null
		RC=$?
		if [ ${RC} == 0 ];then
			echo " OK"
		else
			echo " ERROR"
		fi
	fi
done
