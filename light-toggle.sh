#!/bin/bash

cur_light=$(light | awk -F . '{print $1}')

if [ $cur_light -eq 100 ]; then
    echo 10
    sudo light -S 10
else
    echo 100
    sudo light -S 100
fi
