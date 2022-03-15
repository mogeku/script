#!/bin/bash

pic_dir="$HOME/Pictures/wallpaper"
filename=$(ls $pic_dir | sort -R | head -n1)
feh --bg-fill "$pic_dir/$filename"
