lsblk | awk '{print $1}' > lsblk.log

while read line
do
 echo \[dev-$line\]
 echo filename=/dev/$line
done < lsblk.log

rm -rf lsblk.log
