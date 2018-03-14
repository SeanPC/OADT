#!/usr/bin/sh

#functions
SetTime(){
if [ -z "$ntpserver" ] || [ -f /etc/ntp.conf.oradbinst ]
then
	return 0
fi
cp -f /etc/ntp.conf /etc/ntp.conf.oradbinst
echo "server $ntpserver" >> /etc/ntp.conf 
ntpdate $ntpserver 
startsrc -s xntpd
}
SetSpace(){
local swap tmp root swap0 tmp0 root0 pmen 
root0=30
tmp0=2
pmem=`lsattr -E -l sys0 -a realmem|awk '{print $2 "/1024/1024"}'|bc`
if [ "$pmem" -lt 4 ]
then
        swap0=`expr $pmen * 2`
elif [ "$pmem" -lt 16 ]
then
        swap0=$pmem
else
        swap0=16
fi
root=`df -g|sed 1d|xargs -n 7|grep /$|awk '{print $3}'|cut -d . -f 1`
tmp=`df -g|sed 1d|xargs -n 7|grep /tmp$|awk '{print $3}'|cut -d . -f 1`
swap=`lsps -a|grep hd6|sed "s/MB//"|awk '{print $4"/1024"}'|bc`
root=`expr $root - $root0`
tmp=`expr $tmp - $tmp0`
swap=`expr $swap - $swap0`
if [ $root -lt 0 ]
then
        size=`echo $root|sed "s/-//"`
        chfs -a size=+"$size"G / > /dev/null 2>&1
        if [ $? -ne 0 ]
        then
                echo "1:    Please manually increase filesystem of /,keeping avaiable size be 20G at least!"
                exit 1
        fi
fi
if [ $tmp -lt 0 ]
then
        size=`echo $tmp|sed "s/-//"`
        chfs -a size=+"$size"G /tmp
        if [ $? -ne 0 ]
        then
                echo "1:    Please manually increase filesystem of /tmp,keeping avaiable size be 2G at least!"
                exit 1
        fi
fi
if [ $swap -lt 0 ]
then
        size=`echo $swap|sed "s/-//"`
        if ! lsvg rootvg|grep "PP SIZE: "|grep meg > /dev/null 2>&1
        then
                echo "1:    Please manually increase swap size,letting total size be "$swap0"G at least!"
                exit 1
        fi
        size=`lsvg rootvg|grep "PP SIZE: "|awk '{print "'$size'*1024/"$6}'|bc`
        chps -s $size hd6
        if [ $? -ne 0 ]
        then
                echo "1:    Please manually increase swap size,letting total size be "$swap0"G at least!"
                exit 1
        fi
fi
}

SetNFS(){
[ $rac = 1 ] && [ "$node1" != "$hostname" ] && return 0
startsrc -g nfs > /dev/null 2>&1
cat /etc/exports |grep orainst > /dev/null 2>&1 || echo "/var/orainst -rw" >> /etc/exports
exportfs -a > /dev/null 2>&1
}


SetKnownHost(){
[ -f /etc/ssh/ssh_config.oradbinst ] &&  return 0
cp -f /etc/ssh/ssh_config /etc/ssh/ssh_config.oradbinst
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
}

SetHostIP(){
local vip vips ip node host i j scanip private publicvip
[ -f /etc/hosts.oradbinst ] && cp -f /etc/hosts.oradbinst /etc/hosts || cp -f /etc/hosts /etc/hosts.oradbinst
[ -f /etc/resolv.conf.oradbinst ] && cp -f /etc/resolv.conf.oradbinst /etc/resolv.conf || cp -f /etc/resolv.conf /etc/resolv.conf.oradbinst
j=0
scanip=`echo "$ips"|cut -d , -f 1`
vips=`echo "$ips"|awk -F "," '{$1="";print}'`
for i in $vips
do
	vip[$j]=$i
	j=`expr $j + 1`	
done
i=0
for node in `echo $nodes|sed "s/,/ /g"`
do
	if echo $node|grep "[0-9]\.[0-9]" > /dev/null 2>&1
	then
		ip=$node
		host=`host $node|head -1|awk '{print $NF}'|cut -d . -f 1` || host=`cat /etc/hosts|grep "^$node "|awk '{print $2}'|cut -d . -f 1|head -1`
		if [ -z "$host"]
		then
			echo "1:    Failed to get hostname by ipaddr \"$node\"!"
			exit 1
		fi
	else
		host=$node
		host $node > /dev/null 2>&1 && ip=`host $node|head -1|awk '{print $NF}'` || ip=`cat /etc/hosts|grep " $node | $node$"|awk '{print $1}'`
		if [ -z "$ip" ]
		then
			echo "1:    Failed to get IP by hostname \"$node\"!"
			exit 1
		fi
	fi
	cat /etc/hosts|grep $ip > /dev/null 2>&1 || echo "$ip        $host" >> /etc/hosts
	j=`expr $i + 1`
	privateip0=`echo $privateip|cut -d , -f $j`
	private[$i]="$privateip0        $host-priv"
	publicvip[$i]="${vip[$i]}        $host-vip"
	i=`expr $i + 1`
done
#rm -f /etc/resolv.conf

echo "#private ip" >> /etc/hosts
for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63
do
	if [ -z "${private[$i]}" ] 
	then
		break
	else
		echo "${private[$i]}" >> /etc/hosts
	fi
done

echo "#public virtual ip" >> /etc/hosts		
for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63
do
        if [ -z "${publicvip[$i]}" ]
	then
		break
	else
		echo "${publicvip[$i]}" >> /etc/hosts
	fi
done

echo "#Single Client Access Name" >> /etc/hosts
echo "$scanip        $clusname-scan" >> /etc/hosts

echo "0:    Writting resolv stuff to hosts file on node \"$hostname\"....Passed!"
}

SetPriv(){
local dev n ip privateip0
n=`lltstat -nvv active|grep -n " $hostname "|cut -d : -f 1|head -1`
n=`expr $n + 1`
dev=`lltstat -nvv active|sed -n "$n"p|awk '{print $1}'`
if echo $nodes|grep "[0-9]\.[0-9]" > /dev/null 2>&1
then
	ip=`cat /etc/hosts|grep "$hostname "|head -1|awk '{print $1}'`
	n=`echo "$nodes"|tr "," "\n"|grep -n ^$ip$|cut -d : -f 1`
else
	n=`echo "$nodes"|tr "," "\n"|egrep -n "^$hostname(\.|$)"|cut -d : -f 1`
fi
privateip0=`echo $privateip|cut -d , -f $n`
ifconfig $dev monitor &&
mktcpip -h $hostname -a $privateip0 -m $mask -i $dev > /dev/null 2>&1
if [ $? -eq 0 ]
then
	echo "0:    Setting private ip for \"$dev\" with ipaddr \"$privateip0/$mask\" on node \"$hostname\"....Passed!"
else
	echo "1:    Failed to set private ip on node \"$hostname\"!"
	exit 1
fi
}

racpf(){
echo '
export ORACLE_BASE=/oracle
export ORACLE_HOME=/oracle/orahome
export CRS_HOME=/crs/crshome
export ORACLE_SID=orcl
export PATH=$PATH:$ORACLE_HOME/bin:$CRS_HOME/bin:$ORACLE_HOME/jdk/jre/bin
' >> $profile
}
sipf(){
echo '
export ORACLE_BASE=/oracle
export ORACLE_HOME=/oracle/orahome
export ORACLE_SID=orcl
export PATH=$PATH:$ORACLE_HOME/bin:$ORACLE_HOME/jdk/jre/bin
' >> $profile
}

SetUser(){
local group profile node
profile=/home/oracle/.profile
for group in oinstall dba
do
	cat /etc/group|grep "^$group:" > /dev/null 2>&1 || mkgroup $group
done
ps -ef|awk '/^oracle/{print}'|awk '{print $2}'|xargs -n1 kill -9 > /dev/null 2>&1
if id oracle > /dev/null 2>&1
then
	userdel oracle
	rm -rf /home/oracle
fi
useradd -g oinstall -G dba -s /usr/bin/ksh -d /home/oracle -m oracle &&
echo "oracle:Oracle123"|chpasswd
pwdadm -c oracle
if [ $? -eq 0 ]
then
	echo "0:    Creating Oracle User \"oracle\" with password \"Oracle123\""$opt"....Passed!"
else
	echo "1:    Failed to create Oracle User"$opt"!"
	exit 1
fi

#set the profile for oracle user
echo 'export PS1="[$LOGNAME@`uname -n` ]\$ "' >> $profile
[ "$rac" = 1 ] && racpf || sipf
echo "0:    Setting oracle user profile"$opt"....Passed!"

#Generate ECDSA in knownhost file
[ -f /home/oracle/.ssh/known_hosts ] && rm -f /home/oracle/.ssh/known_hosts
for node in `echo "$nodes"|sed "s/,/ /g"`
do
	su - oracle -c "ssh -o PasswordAuthentication=no $node" > /dev/null 2>&1
done

#Generate pub key for oracle
if [ -f /home/oracle/.ssh/id_rsa ] 
then
	echo "0:	Generating pub key for oracle user"$opt"....Passed!"
else
	su - oracle -c "ssh-keygen -q -t rsa -N '' -f /home/oracle/.ssh/id_rsa" > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo "0:    Generating pub key for oracle user"$opt"....Passed!"
	else
		echo "1:    Failed to generate pub key for oracle user"$opt"!"
		exit 1
	fi
fi

#set limits for oracle user
chuser cpu='-1' fsize='-1' data='-1' stack='-1' core='-1' rss='-1' nofiles='-1' capabilities=CAP_NUMA_ATTACH,CAP_BYPASS_RAC_VMM,CAP_PROPAGATE oracle
if [ $? -eq 0 ]
then 
	echo "0:    Setting oracle user limits"$opt"....Passed!"
else
	echo "1:    Failed to set oracle user limits"$opt"!"
	exit 1
fi
}

MountMP(){
local vol path
for vol in ocrvote dbdata archive
do
	if df|grep /$vol > /dev/null 2>&1
	then
		umount /$vol > /dev/null 2>&1
		if [ $? -ne 0 ]
		then
			echo "1:    Please umount /$vol manually!"
			exit 1
		fi
	fi
	mkdir -p /$vol
	path=`find /dev/vx/dsk/ -type b|grep $vol`
	mount -o cluster -V vxfs $path /$vol > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo "0:    Mounting oracle volume \"$vol\""$opt" ....Passed!"
	else
		echo "1:    Failed to mount oracle volume \"$vol\""$opt"!"
		exit 1
	fi
done
}

SetMP(){
if [ "$rac" = 1 ]
then
	if [ "$node1" = "$hostname" ]
	then
		chown -R oracle:oinstall /ocrvote /dbdata /archive
	else
		MountMP
	fi
else
	if [ "$node1" = "$hostname" ]
	then
		chown -R oracle:oinstall /dbdata /archive
	else
		mkdir -p /dbdata /archive
	fi
fi
}

SetVXVOL(){
local dg vol
[ "$node1" = "$hostname" ] || return 0
vxedit -g oradg"$flag"_gridasm set user=oracle group=oinstall mode=660 gridvol > /dev/null 2>&1 &&
vxedit -g oradg"$flag"_dbarchasm set user=oracle group=oinstall mode=660 dbarchvol > /dev/null 2>&1
if [ $? -eq 0 ]
then
        echo "0:    Setting Owner of volume \"gridvol,dbarchvol\" for ASM....Passed!"
else
        echo "0:    Failed to set Owner of volume \"gridvol,dbarchvol\" for ASM!"
        exit 1
fi
}

SetStorage(){
local dg vol
case $storagetype in
        FS:VCFS)
                [ "$mount" = 0 ] && SetMP
                ;;
        ASM:VXVOL)
                SetVXVOL
                ;;
        *)
                echo "1:    Invalid Storage Type!"
                exit
esac
}

SetBin(){
if [ "$rac" = 1 ]
then
	mkdir -p /oracle/orahome /crs/crshome /orainst
	chown -R oracle:oinstall /oracle /crs /orainst
else
	mkdir -p /oracle/orahome /orainst
	chown -R oracle:oinstall /oracle /orainst
fi
chown -R oracle:oinstall $nodelog
echo "0:    Creating directory for oracle binary"$opt"....Passed!"
}

SetKernel(){
if [ -f $nodelog/kernel.$flag ]
then
	$nodelog/kernel.$flag > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo "0:    Configruring kernel parameters"$opt"....Passed!"
	else
		echo "1:    Failed to configure kernel parameters"$opt"!"
		exit 1
	fi
else
	echo "1:    Missing kernel paramters config file"$opt"!"
	exit 1
fi
}

SetPkg(){
local pkg
if [ -f $nodelog/pkg.$flag ]
then
	for pkg in `cat $nodelog/pkg.$flag`
	do
		if ! lslpp -l $pkg > /dev/null 2>&1
		then
        		echo "2:    Missing package \"$pkg\""$opt",need you manually install it!"
		fi
	done
else
	echo "1:    Missing package list file"$opt"!"
	exit 1
fi
}

SetPlus(){
if [ -f $nodelog/plus.$flag ]
then
	$nodelog/plus.$flag
	if [ $? -eq 0 ]
	then
		echo "0:    Executing additional script"$opt"....Passed!"
	else
		echo "1:    Failed to execute additional script"$opt"!"
		exit 1
	fi
fi
}


#main code
flag=_FLAG_
ips=_IPS_
node1=_NODE1_
nodes=_NODES_
ntpserver=_NTP_
privateip=_PRIVIP_
mask=_MASK_
rac=_RAC_
ostype=_OSTYPE_
mount=_MOUNT_
clusname=_CLUSNAME_
storagetype=_STTYPE_
nodelog=/var/orainst
if echo "$node1"|grep ^[0-9] > /dev/null 2>&1
then
        node1=`cat /etc/hosts|grep $node1|awk '{print $2}'|head -1|cut -d . -f 1`
else
	node1=`echo $node1|cut -d . -f 1`
fi
hostname=`hostname|cut -d . -f 1`
opt=" on the node \"$hostname\""

SetTime
SetSpace
SetNFS
SetKnownHost
if [ "$rac" = 1 ]
then
	SetPriv
	SetHostIP
fi
SetUser
SetBin
SetStorage
SetKernel
SetPkg
SetPlus
