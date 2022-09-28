#!/bin/bash

light=$(xbacklight | awk -F . '{print $1}')

if [ $light -eq 100 ]; then
    echo 10
    xbacklight -set 10
else
    echo 100
    xbacklight -set 100
fi
