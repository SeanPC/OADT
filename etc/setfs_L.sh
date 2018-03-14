#!/bin/bash
#dev by bentley any suggestion please contact bentley.xu@veritas.com


#create vg
createvg(){
local vgopt=$1
local dgname=$2
local dgdisk=$3
vxdg $vgopt init $dgname $dgdisk > /dev/null 2>&1
if [ $? -eq 0 ]
then
        echo "0:    Creating oracle dg \"$dgname\"....Passed!"
else
        echo "1:    Failed to create oracle dg \"$dgname\"!"
        exit 1
fi
}
#create/mount volume
createmountvol(){
local dgname=$1
local vols=$2
local mopt=$3
local des=$4
for vol in $vols
do
	volsize=9g
	vxassist -g $dgname make $vol $volsize > /dev/null 2>&1 &&
	mkfs -t vxfs /dev/vx/rdsk/$dgname/$vol > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo "0:    Creating oracle volume \"$vol\"....Passed!"
	else
		echo "1:    Failed to create oracle volume \"$vol\"!"
		vxdg destroy $dgname
		exit 1
	fi
	mkdir -p /$vol
	mount $mopt -t vxfs /dev/vx/dsk/$dgname/$vol /$vol > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo "0:    Mounting oracle volume \"$vol\"$des....Passed!"
	else
		echo "1:    Failed to mount oracle volume \"$vol\"$des!"
		mp=`df|grep -P "/ocrvote$|/dbdata$|/archive$"|awk '{print $NF}'`
		[ -n "$mp" ] && umount $mp > /dev/null 2>&1
		vxdg destroy $dgname > /dev/null 2>&1
		exit 1
	fi
done
}

GetDisk(){
local size0 size1 i j
size0=$1
j=$2
adiskn=`echo "$adisk"|wc -l`
size1=0
for i in `seq $adiskn`
do
        size2=`echo "$adisk"|sed -n "$i"p|awk '{print $2}'|sed "s/g//"`
        size1=`echo "$size1+$size2"|bc`
        [ `echo "$size1>=$size0"|bc` = 1 ] && break
done
if [ `echo "$size1<$size0"|bc` = 1  ]
then
        echo "1:    There are not enough disks to make dg!"
        exit 1
else
        disk[$j]=`echo "$adisk"|sed -n "1,$i"p|awk '{print $1}'`
        adisk=`echo "$adisk"|sed "1,$i"d`
fi
}

MakeVCFS(){
if [ "$rac" = 1 ]
then
        GetDisk 10 0 
        GetDisk 19 1
        createvg "-s" oradg"$flag"_ocrvote "${disk[0]}"
        createvg "-s" oradg"$flag"_dbarch "${disk[1]}"
        createmountvol oradg"$flag"_ocrvote "ocrvote" "-o cluster" " on node \"$hostname\""
        createmountvol oradg"$flag"_dbarch "dbdata archive" "-o cluster" " on node \"$hostname\""
else
        GetDisk 19 1
        createvg "" oradg"$flag"_dbarch "${disk[1]}"
        createmountvol oradg"$flag"_dbarch "dbdata archive" "" " on node \"$hostname\""
fi
}

MakeVXVOL(){
local size dg vol
echo -e "10 oradg"$flag"_gridasm gridvol\n19 oradg"$flag"_dbarchasm dbarchvol"|while read size dg vol
do
	GetDisk $size 0
	createvg "-s" $dg "${disk[0]}"
	vxassist -g $dg make $vol "$size"g > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo "0:    Prepare volume \"$vol\" for ASM....Passed!"
	else
		echo "1:    Failed to prepare volume for ASM!"
		vxdg destroy $dg
		exit 1
	fi
done
}

#main code
path=/opt/VRTS/bin
rac=_RAC_
flag=_FLAG_
storagetype=_STTYPE_
hostname=`hostname|cut -d . -f 1`
adisk=`cat /var/orainst/disks`
[ -z "$adisk" ] && echo "1:    Failed to get avaiable disks" && exit 1

#make the storage to store oracle stuff
case $storagetype in 
	FS:VCFS)
		MakeVCFS
		;;
	ASM:VXVOL)
		MakeVXVOL
		;;
	*)
		echo "1:   Invalid Storage Type!"
		exit 1
esac
exit 0
