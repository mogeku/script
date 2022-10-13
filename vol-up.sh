#!/bin/bash

/usr/bin/amixer -qM set Speaker 5%+ umute
#pactl set-sink-volume @DEFAULT_SINK@ +5%
bash ~/script/dwm-status.sh
