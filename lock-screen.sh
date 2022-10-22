#!/bin/bash
 
# @Author: momo <1209816754@qq.com>
# @Date: 2022-10-22 21:02:26
# @Last Modified by: momo <1209816754@qq.com>
# @Last Modified time: 2022-10-22 21:02:26

img=$(find ~/Pictures/ -type f -name "*.png" | sort -R | head -n1)
i3lock -e -t -i "$img"
# xset dpms force off  #turn off screen at once

