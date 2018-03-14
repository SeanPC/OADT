#!/usr/bin/sh
base=/var/orainst
flag=`ls -lrt $base/|grep kernel|tail -1|cut -d . -f 2`
rac=`cat $base/setconf.$flag|grep rac=|cut -d = -f 2`
image=`cat $base/image.$flag`
cat $base/setfs.$flag | grep storagetype=ASM: > /dev/null 2>&1 && asm=1 || asm=0
hostname=`hostname|cut -d . -f 1`
node1=`cat $base/setconf.$flag|grep ^node1=|cut -d = -f 2`


if [ $rac = 1 ] || [ $hostname = $node1 ]
then
	while true
	do
		if dg=`vxdg list 2>&1|grep oradg[0-9][0-9][0-9][0-9]`
		then
			dg=`echo "$dg"|awk '{print $1}'`
			for i in $dg
			do
				vxinfo -g $i
			done|grep -v Start
			[ $? -ne 0 ] && break
		fi
		sleep 1
	done
else
	sleep 10
	#here need find out a new way
fi
sleep 10
n=`lltstat -nvv active|grep -n " $hostname "|cut -d : -f 1|head -1`
n=`expr $n + 1`
dev=`lltstat -nvv active|sed -n "$n"p|awk '{print $1}'`

ifconfig $dev monitor
[ $? -ne 0 ] && exit 1
if [ $rac = 1 ]
then
	[ $hostname = $node1 ] && nfso -o nfs_use_reserved_ports=1 && mount $image /oraimage || echo 1 > /dev/null 2>&1
	[ $? -ne 0 ] && exit 1
	if [ $asm = 0 ]
	then	
		for vol in ocrvote dbdata archive
		do
        		path=`find /dev/vx/dsk/ -type b|grep $vol`
        		mount -o cluster -V vxfs $path /$vol > /dev/null 2>&1
        		[ $? -ne 0 ] && exit 1
		done
	fi
else
	nfso -o nfs_use_reserved_ports=1 && mount $image /oraimage
	[ $? -ne 0 ] && exit 1
	if [ $hostname = $node1 ]
	then
		for vol in dbdata archive
		do
			path=`find /dev/vx/dsk/ -type b|grep $vol`
			mount -V vxfs $path /$vol > /dev/null 2>&1
			[ $? -ne 0 ] && exit 1
		done
	fi
fi
exit 0
