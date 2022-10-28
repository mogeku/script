#!/bin/sh

# A dwm_bar function to show the current network connection/SSID, Wifi Strength, private IP using Connmanctl.
# procrastimax <heykeroth.dev@gmail.com>
# GNU GPLv3

dwm_nmcli () {
    printf "%s" "$SEP1"
    if [ "$IDENTIFIER" = "unicode" ]; then
        # printf "🌐 "
        printf " "
    else
        printf "NET "
    fi

    NMCLI_OUTPUT=$(nmcli -f IN-USE,SIGNAL,SSID device wifi | grep '*' | grep -v '\-\-')

    if [ ! "$NMCLI_OUTPUT" ]; then
        printf "OFFLINE"
        printf "%s\n" "$SEP2"
        return
    else
        CONNAME=$(printf "%s" "$NMCLI_OUTPUT" | awk '{print $3}')
        STRENGTH=$(printf "%s" "$NMCLI_OUTPUT" | awk '{print $2}')
    fi

    # if STRENGTH is empty, we have a wired connection
    if [ "$STRENGTH" ]; then
        # printf "%s %s %s%%" "$IP" "$CONNAME" "$STRENGTH"
        CONNAME=${CONNAME: 0: 4}
        if [ ${#CONNAME} -gt 4 ];then
            CONNAME=${CONNAME}..
        fi

        printf "%s|%s%%" "$(echo $CONNAME)" "$STRENGTH"
    else
        printf "%s" "$CONNAME"
    fi

    printf "%s\n" "$SEP2"
}

dwm_nmcli

