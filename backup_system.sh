#!/bin/bash

# https://www.cnblogs.com/youxia/p/linux013.html#_label2
# sudo time rsync -Paz / /media/momo/Ventoy/backup/ubuntu20.04/backup_20221006_work --exclude=/media/*
# --exclude=/sys/* --exclude=/proc/* --exclude=/mnt/* --exclude=/tmp/* --exclude=/dev/* --exclude=/run/*

backup_path=/backup_`date "+%Y%m%d"`_work.tgz

sudo time tar cvpzf $backup_path --exclude=/media/* --exclude=/sys/* --exclude=/proc/* --exclude=/mnt/* --exclude=/tmp/* --exclude=/dev/* --exclude=/run/* --exclude=/home/momo/vmwareMachine/* --exclude=/home/momo/Downloads/* --exclude=$backup_path /
