#!/bin/bash
 
# @Author: momo <1209816754@qq.com>
# @Date: 2022-11-02 21:50:58
# @Last Modified by: momo <1209816754@qq.com>
# @Last Modified time: 2022-11-02 21:50:58

while true; do
    # Log stderror to a file 
    dwm 2> ~/.dwm.log
    # No error logging
    #dwm >/dev/null 2>&1
done
