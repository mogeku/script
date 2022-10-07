#!/bin/sh

# A dwm_bar function to display information regarding system memory, CPU temperature, and storage
# Joe Standring <git@joestandring.com>
# GNU GPLv3

df_check_location='/home'

dwm_resources () {
	# get all the infos first to avoid high resources usage
	free_output=$(free -h | grep Mem)
	df_output=$(df -h $df_check_location | tail -n 1)
	# Used and total memory
	MEMUSED=$(echo $free_output | awk '{print $3}' | cut -f1 -d 'i')
	MEMTOT=$(echo $free_output | awk '{print $2}' | cut -f1 -d 'i')
	# CPU temperature
	CPU=$(top -bn1 | grep Cpu | awk '{print $2}')%
	#CPU=$(sysctl -n hw.sensors.cpu0.temp0 | cut -d. -f1)
	# Used and total storage in /home (rounded to 1024B)
    ROOTPART=$(df -h | awk '/\/$/ { print $5}') 
	HOMEPART=$(df -h | awk '/\/home/ { print $5}') 
	# STOUSED=$(echo $df_output | awk '{print $3}')
	# STOTOT=$(echo $df_output | awk '{print $2}')
	# STOPER=$(echo $df_output | awk '{print $5}')

	printf "%s" "$SEP1"
	if [ "$IDENTIFIER" = "unicode" ]; then
		printf " %s/%s  %s$SEP2$SEP1 %s  %s" "$MEMUSED" "$MEMTOT" "$CPU" "$ROOTPART" "$HOMEPART"
	else
		printf "STA | MEM %s/%s CPU %s STO %s/%s: %s" "$MEMUSED" "$MEMTOT" "$CPU" "$STOUSED" "$STOTOT" "$STOPER"
	fi
	printf "%s\n" "$SEP2"
}

dwm_resources
