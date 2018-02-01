xrandr
##gtf -x 1920 1080 60
#cvt -r 1920 1080 60
xrandr --newmode "1920x1080R"  138.50  1920 1968 2000 2080  1080 1083 1088 1111 +hsync -vsync
xrandr --addmode VGA-1 "1920x1080R"
xrandr --output VGA-1 --mode "1920x1080R"
xrandr
