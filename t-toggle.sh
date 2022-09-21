#!/bin/bash

result=$(ps -ef | grep -v grep | grep trayer)
if [ "$result" == "" ]; then
    trayer --transparent true --expand false --align right --width 20 --height 40 --SetDockType false &
else
    killall trayer
fi
