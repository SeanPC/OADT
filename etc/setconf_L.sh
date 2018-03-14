#!/bin/bash

#functions
SetTime(){
if [ -z "$ntpserver" ] || [ -f /etc/ntp.conf.oradbinst ]
then
	return 0
fi
cp -f /etc/ntp.conf /etc/ntp.conf.oradbinst
cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 
echo "server $ntpserver" >> /etc/ntp.conf 
ntpdate $ntpserver 
if ls -l /usr/bin/systemctl > /dev/null 2>&1
then
	systemctl start ntpd.service
	systemctl enable ntpd.service
else
	service ntpd start
	service ntp start
	chkconfig ntpd on
fi
}
SetSpace(){
local swap root swap0 root0 swapold
echo "tmpfs /dev/shm tmpfs rw,exec 0 0" >> /etc/fstab
root0=20
pmem=`free -g|grep Mem:|awk '{print $2}'|cut -d . -f 1`
if [ "$pmem" -lt 4 ]
then
	swap0=$[$pmem*2]
elif [ "$pmem" -lt 16 ]
then
	swap0=$pmem
else
	swap0=15
fi
swap=`free -g|grep Swap:|awk '{print $2}'`
root=`df -h|sed 1d|xargs -n 6|grep /$|awk '{if ($4 ~ /[Gg]/){print $4}}'|grep -oP "\d+"`
[ -z "$root" ] && root=0
if [ "$swap" -lt $swap0 ] 
then
	if [ "$root" -lt $[$root0+$swap0] ]
	then
		echo "1:    Size of Swap must be larger the 16G!"
		exit 1
	else
		swapold=`cat /etc/fstab|grep -v ^# |grep " swap "|awk '{print $1}'`
		cp /etc/fstab /etc/fstab.oradbinst
		sed -i -r "s/.* swap .*//" /etc/fstab
		swapoff $swapold &&
		dd if=/dev/zero of=/ora_swap bs=1024K count=16386 > /dev/null 2>&1 &&
		mkswap -f /ora_swap &&
		chmod 0600 /ora_swap &&
		swapon /ora_swap &&
		echo "/ora_swap        swap                 swap       defaults              0 0" >> /etc/fstab
		if [ $? -ne 0 ]
		then
			cp -f /etc/fstab.oradbinst /etc/fstab
			echo "1:    Failed to autoConfigure swap!"
			echo "1:    Please manually configure swap,let it be 16G!"
			exit 1
		fi
	fi
elif [ "$root" -lt "$root0" ]
then
	echo "1:    Avaiable Size of / must be larger than 20G!"
	exit 1
fi
}

SetNFS(){
[ $rac = 1 ] && [ "$node1" != "$hostname" ] && return 0
if ls -l /usr/bin/systemctl > /dev/null 2>&1
then
	systemctl start nfs-server.service
	systemctl enable nfs-server.service
else
	service nfs start
	service nfsserver start
	chkconfig nfs on
	chkconfig nfsserver on
fi
exportfs -o rw,sync,no_root_squash *:/var/orainst
}


SetKnownHost(){
[ -f /etc/ssh/ssh_config.oradbinst ] &&  return 0
cp -f /etc/ssh/ssh_config /etc/ssh/ssh_config.oradbinst
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
}

SetHostIP(){
local vip ip node host i j scanip private publicvip privateip0
[ -f /etc/hosts.oradbinst ] && cp -f /etc/hosts.oradbinst /etc/hosts || cp -f /etc/hosts /etc/hosts.oradbinst
[ -f /etc/resolv.conf.oradbinst ] && cp -f /etc/resolv.conf.oradbinst /etc/resolv.conf || cp -f /etc/resolv.conf /etc/resolv.conf.oradbinst
i=0
scanip=`echo "$ips"|cut -d , -f 1`
vip=(`echo "$ips"|awk -F "," '{$1="";print}'`)
for node in `echo $nodes|sed "s/,/ /g"`
do
	if [[ $node =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]
	then
		ip=$node
		host $node > /dev/null 2>&1 && host=`host $node|head -1|awk '{print $NF}'|cut -d . -f 1` || host=`cat /etc/hosts|grep -P "$node "|awk '{print $2}'|cut -d . -f 1|head -1`
		if [ -z "$host"]
		then
			echo "1:    Failed to get hostname by ipaddr \"$node\"!"
			exit 1
		fi
	else
		host=$node
		host $node > /dev/null 2>&1 && ip=`host $node|head -1|awk '{print $NF}'` || ip=`cat /etc/hosts|grep -P " $node | $node$"|awk '{print $1}'`
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
for i in 0 `seq 63`
do
	if [ -z "${private[$i]}" ] 
	then
		break
	else
		echo "${private[$i]}" >> /etc/hosts
	fi
done

echo "#public virtual ip" >> /etc/hosts		
for i in 0 `seq 63`
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

echo "0:	Writting resolv stuff to hosts file on node \"$hostname\"....Passed!"
}

SetPriv(){
local dev n ip privateip0
dev=`lltstat -nvv active|grep -A 1 " $hostname "|tail -1|awk '{print $1}'`
if [[ $nodes =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]
then
	ip=`cat /etc/hosts|grep $hostname|head -1|grep -oP "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ "`
	n=`echo "$nodes"|sed -r "s/,/\n/g"|grep -n ^$ip$|cut -d : -f 1`
else
	n=`echo "$nodes"|sed -r "s/,/\n/g"|grep -nP "^$hostname(\.|$)"|cut -d : -f 1`
fi
privateip0=`echo $privateip|cut -d , -f $n`
if [[ $ostype =~ SUSE ]]
then
	echo -e "BOOTPROTO='static'\nSTARTMODE='auto'\nIPADDR='$privateip0'\nNETMASK='$mask'" > /etc/sysconfig/network/ifcfg-$dev
else
	echo -e "DEVICE=$dev\nBOOTPROTO=static\nONBOOT=yes\nIPADDR=$privateip0\nNETMASK=$mask" > /etc/sysconfig/network-scripts/ifcfg-$dev
fi
ifconfig $dev $privateip0 netmask $mask
if [ $? -eq 0 ]
then
	echo "0:	Setting private ip for \"$dev\" with ipaddr \"$privateip0/$mask\" on node \"$hostname\"....Passed!"
else
	echo "1:	Failed to set private ip on node \"$hostname\"!"
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
if [[ $ostype =~ SUSE ]]
then
	profile=/home/oracle/.profile
else
	profile=/home/oracle/.bash_profile
fi
for group in oinstall dba
do
	cat /etc/group|grep -P "^$group:" > /dev/null 2>&1 || groupadd $group
done
ps -ef|awk '/^oracle/{print}'|awk '{print $2}'|xargs -n1 kill -9 > /dev/null 2>&1
if id oracle > /dev/null 2>&1
then
	userdel oracle
	rm -rf /home/oracle
	rm -rf /var/spool/mail/oracle
fi
useradd -p '$6$yXZhpTkM$K1bgHvHXxIPbSMGuDMEQLNpLcwuR22bYBzooVv1rjgd//tDbWzgPosiMVJgreHu0xef0t/pxH5oMqAlry2gP7/' -g oinstall -G dba -s /bin/bash -d /home/oracle -m oracle
if [ $? -eq 0 ]
then
	echo "0:	Creating Oracle User \"oracle\" with password \"Oracle123\""$opt"....Passed!"
else
	echo "1:	Failed to create Oracle User"$opt"!"
	exit 1
fi

#set the profile for oracle user
echo 'export PS1="[\u@\h \W]\$ "' >> $profile
[ "$rac" = 1 ] && racpf || sipf
echo "0:	Setting oracle user profile"$opt"....Passed!"

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
		echo "0:	Generating pub key for oracle user"$opt"....Passed!"
	else
		echo "1:	Failed to generate pub key for oracle user"$opt"!"
		exit 1
	fi
fi

#set limits for oracle user
echo -e "\n\n#set limits for oracle user" >> $profile
#for limit in c d e f i l m n p q r s t u v x
for limit in c d f m s t v x
do
	echo "ulimit -$limit unlimited" >> $profile
done
echo "0:	Setting oracle user limits"$opt"....Passed!"
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
			echo "1:	Please umount /$vol manually!"
			exit 1
		fi
	fi
	mkdir -p /$vol
	path=`find /dev/vx/dsk/ -type b|grep $vol`
	mount -o cluster -t vxfs $path /$vol > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo "0:	Mounting oracle volume \"$vol\""$opt" ....Passed!"
	else
		echo "1:	Failed to mount oracle volume \"$vol\""$opt"!"
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
echo "0:	Creating directory for oracle binary"$opt"....Passed!"
}

SetKernel(){
local shmall shmmax
if [ -f $nodelog/kernel.$flag ]
then
	#[ $pmem -ge 16 ] && pmem=16
	shmall=`echo $pmem*1024*1024/4|bc`
	shmmax=`echo $pmem*1024*1024*1024/2|bc`
	sed -i "s/_SHMALL_/$shmall/;s/_SHMMAX_/$shmmax/" $nodelog/kernel.$flag
	[ -f /etc/sysctl.conf.oradbinst ] && cp -f /etc/sysctl.conf.oradbinst /etc/sysctl.conf || cp -f /etc/sysctl.conf /etc/sysctl.conf.oradbinst
	cat $nodelog/kernel.$flag >> /etc/sysctl.conf && sysctl -p
	if [ $? -eq 0 ]
	then
		echo "0:	Configruring kernel parameters"$opt"....Passed!"
	else
		echo "1:	Failed to configure kernel parameters"$opt"!"
		exit 1
	fi
else
	echo "1:	Missing kernel paramters config file"$opt"!"
	exit 1
fi
}

SetPkg(){
local pkg
if [[ $ostype =~ SUSE ]]
then
	cmd="zypper -n in"
else
	cmd="yum -y install"
fi
if [ -f $nodelog/pkg.$flag ]
then
        if yum repolist 2>&1 |grep repolist: > /dev/null || zypper ls 2>&1 |grep Yes > /dev/null
        then
                echo "0:	Checking if YUM or Zypper is configured"$opt"....Passed!"
        else
                echo "1:	YUM or Zypper is not configured"$opt"!"
                exit 1
        fi
	for pkg in `cat $nodelog/pkg.$flag`
	do
		rpm -q $pkg > /dev/null 2>&1 || $cmd $pkg > /dev/null 2>&1
	done
	echo "0:	Installing required pakcages"$opt"....Passed!"
else
        echo "1:	Missing package list file"$opt"!"
        exit 1
fi
}

SetPlus(){
if [ -f $nodelog/plus.$flag ]
then
	$nodelog/plus.$flag
	if [ $? -eq 0 ]
	then
		echo "0:	Executing additional script"$opt"....Passed!"
	else
		echo "1:	Failed to execute additional script"$opt"!"
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
if [[ $node1 =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]
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
	SetHostIP
	SetPriv
fi
SetUser
SetBin
SetStorage
SetKernel
SetPkg
SetPlus
