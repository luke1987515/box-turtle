#!/bin/bash
# CentOS 7.4
# Put "set_1920x1080.sh" in "/etc/profile.d"

#xrandr
##gtf 1920 1080 60 -x
#xrandr --newmode "1920x1080"  172.80  1920 2040 2248 2576  1080 1081 1084 1118  -HSync +Vsync
#xrandr --addmode VGA-1 "1920x1080"
#xrandr --output VGA-1 --mode "1920x1080"
#xrandr

#cvt -r 1920 1080 60
#xrandr --newmode "1920x1080"  138.50  1920 1968 2000 2080  1080 1083 1088 1111 +hsync -vsync
#xrandr --addmode VGA-1 "1920x1080"
#xrandr --output VGA-1 --mode "1920x1080"
#xrandr

# CentOS 7.4 auto login 
# edit /etc/gdm/custom.conf
# [daemon]
# AutomaticLoginEnable=true
# AutomaticLogin=username
