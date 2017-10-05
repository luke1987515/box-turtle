lsblk | awk '{print $1}' > lsblk.log

while read line
do
 #echo \[dev-$line\]
 echo dd if=/dev/zero of=/dev/$line status=progress \&
done < lsblk.log

rm -rf lsblk.log
