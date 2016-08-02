#!/usr/bin/env bash
#azure extenstions for mcos snipped

for LINE in $*; do
    echo ${LINE} >>/etc/epmf/secret.txt
done

reboot
