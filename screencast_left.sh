#!/bin/bash
 
# @Author: momo <1209816754@qq.com>
# @Date: 2022-11-03 00:38:59
# @Last Modified by: momo <1209816754@qq.com>
# @Last Modified time: 2022-11-03 00:38:59

script_dir=$(cd `dirname $0`;pwd)
cd $script_dir

main_screen=$(xrandr --query | grep "primary" | awk '{print $1}')

cast_screen=$(xrandr --query | grep -v "primary" | grep " connected" | awk '{print $1}' | head -n 1)

if [ "$cast_screen" == "" ];then
    exit 0
fi

xrandr --output $cast_screen --left-of $main_screen --auto

./wp-change.sh
