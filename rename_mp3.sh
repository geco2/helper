#!/bin/bash

# Rename MP3
# Result in: ARTIST – ALBUM / TRACK_NUMBER ARTIST – SONG_NAME
#
# Andi E.
# 07.05.12

##########################################
# Config


##########################################
# Functions
function func_tag
{
	tail -c 128 "$1" | head -c 3
}

function func_rtrim
{
	sed 's/\([^ ]*\) *$/\1/'
}

function func_title
{
	tail -c 125 "$1" | head -c 30 | func_rtrim
}

function func_artist
{
	tail -c 95 "$1" | head -c 30 | func_rtrim
}

function func_album
{
	tail -c 65 "$1" | head -c 30 | func_rtrim
}

function func_year
{
	tail -c 35 "$1" | head -c 4 | func_rtrim
}

function func_comment
{
	tail -c 31 "$1" | head -c 28 | func_rtrim
}

function func_track
{
	tail -c 3 "$1" | hexdump -ve '/1 "%02i "' | awk '{ if ($1 == 0 && $2 != 0) print $2" " }'
}

function func_genre
{
	tail -c 1 "$1" | hexdump -ve '/1 "%03i"'
}

function func_filt
{
	tr -d '/*?'
}

##########################################
# MAIN

for file in *.mp3; do
	echo "--------------------------------------------"
	echo "Working on \"${file}\""

	if [ "$(func_tag "${file}")" == "TAG" ];then
		artist="$(func_artist "${file}" | func_filt)"
		echo -e "\tArtist: [${artist}]"
		album="$(func_album "${file}" | func_filt)"
		echo -e "\tAlbum: [${album}]"
	        title="$(func_title "${file}" | func_filt)"
		echo -e "\tTile: [${title}]"
		track="$(func_track "${file}" | func_filt)"
		echo -e "\tTrack: [${track}]"

		dir="${artist}-${album}"
		
		if [ ${#track} -ne 0 ];then
			newfile="${track}-${artist}-${title}.mp3"
		else
			newfile="${artist}-${title}.mp3"
		fi
		
		if [ ! -d "${dir}" ];then
			echo -e "\t+ Create directory [${dir}]"
			mkdir -p "${dir}"
		fi

		echo -e "\t+ Create File [${dir}/${newfile}]"
		mv "${file}" "${dir}/${newfile}"
	else
		echo -e "\n\t\"${file}\" Has no IDTAG skip this file."
	fi
done
