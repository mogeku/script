#!/bin/bash

remote_ssh=$1

if [ "$remote_ssh" == "" ];then
   echo usage: addssh root@xxx.xxx.xxx.xxx
   exit 1
fi

if [ ! -e ~/.ssh/id_rsa.pub ];then
    ssh-keygen
fi

if ! cat ~/.ssh/id_rsa.pub | ssh $remote_ssh "cat >> ~/.ssh/authorized_keys" ; then
    ssh $remote_ssh "mkdir ~/.ssh"
    cat ~/.ssh/id_rsa.pub | ssh $remote_ssh "cat >> ~/.ssh/authorized_keys"
fi
