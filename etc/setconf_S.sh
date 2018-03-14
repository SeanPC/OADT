#!/usr/bin/bash

#functions
SetTime(){
if [ -z "$ntpserver" ] || [ -f /etc/inet/ntp.conf.oradbinst ]
then
	return 0
fi
[ -f /etc/inet/ntp.conf ] && cp -f /etc/inet/ntp.conf /etc/inet/ntp.conf.oradbinst
echo "server $ntpserver" >> /etc/inet/ntp.conf 
ntpdate $ntpserver 
svcadm enable svc:/network/ntp:default
}
SetSpace(){
root0=10
tmp0=2
pmem=`prtconf|grep Memory|awk '{print $3"/1024"}'|bc`
if [ "$pmem" -lt 4 ]
then
        swap0=`expr $pmen * 2`
elif [ "$pmem" -lt 16 ]
then
        swap0=$pmem
else
        swap0=16
fi
root=`df -h|grep /$|awk '{print $4}'|grep G|sed "s/G//"`
swap=`swap -l -h|grep dsk|awk '{print $4}'|sed "s/G//g"|cut -d . -f 1|xargs -n100|sed "s/ /+/g"|bc`
root=`expr $root - $root0`
swap=`expr $swap - $swap0`
if [ $root -lt 0 ]
then
	echo "1:    Avaiable Size of / must be larger than 20G!"
	exit 1
fi
if [ $swap -lt 0 ]
then
	pool=`df -h|grep /$|cut -d / -f 1`
	zfs set volsize=8g $pool/swap
fi
}

SetNFS(){
[ $rac = 1 ] && [ "$node1" != "$hostname" ] && return 0
svcadm enable svc:/network/nfs/server:default
share -F nfs -o rw,anon=0,log /var/orainst
}


SetKnownHost(){
[ -f /etc/ssh/ssh_config.oradbinst ] &&  return 0
cp -f /etc/ssh/ssh_config /etc/ssh/ssh_config.oradbinst
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
}

SetHostIP(){
[ -f /etc/hosts.oradbinst ] && cp -f /etc/hosts.oradbinst /etc/hosts || cp -f /etc/hosts /etc/hosts.oradbinst
[ -f /etc/resolv.conf.oradbinst ] && cp -f /etc/resolv.conf.oradbinst /etc/resolv.conf || cp -f /etc/resolv.conf /etc/resolv.conf.oradbinst
j=0
scanip=`echo "$ips"|cut -d , -f 1`
vips=`echo "$ips"|cut -d , -f 2-3|sed "s/,/ /g"`
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
mask0=`cat /etc/svc/profile/site/profile*|grep static_address|cut -d / -f 2|cut -d \' -f 1`
ifconfig -a|grep $dev > /dev/null 2>&1 || ipadm create-ip $dev 
ifconfig -a|grep $privateip0 > /dev/null 2>&1 && ipadm delete-ip $dev && ipadm create-ip $dev 
ifconfig $dev up && sleep 2 && ipadm create-addr -a $privateip0/$mask0 $dev
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
profile=/export/home/oracle/.bash_profile
for group in oinstall dba
do
	cat /etc/group|grep "^$group:" > /dev/null 2>&1 || groupadd $group
done
ps -ef|awk '$1=="oracle" {print}'|awk '{print $2}'|xargs -n1 kill -9 > /dev/null 2>&1
if id oracle > /dev/null 2>&1
then
	userdel oracle
	rm -rf /export/home/oracle
	mkdir -p /export/home/oracle
fi
useradd -g oinstall -G dba -s /usr/bin/bash -d /export/home/oracle -m oracle &&
chown oracle:oinstall /export/home/oracle &&
perl -i -pe "s/^oracle:.*\n//" /etc/shadow &&
echo 'oracle:$5$b2f5pmPN$LEuhkzcBFyYAWHuSDSvdbdRYTLOVpq.ai2TYDAjWTu7::::::' >> /etc/shadow 
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
[ -f /export/home/oracle/.ssh/known_hosts ] && rm -f /export/home/oracle/.ssh/known_hosts
for node in `echo "$nodes"|sed "s/,/ /g"`
do
expect << EOF > /dev/null 2>&1
spawn su - oracle -c "ssh -o PasswordAuthentication=no $node"
expect "word"
exit 0
expect eof
EOF
done

#Generate pub key for oracle
if [ -f /export/home/oracle/.ssh/id_rsa ] 
then
	echo "0:	Generating pub key for oracle user"$opt"....Passed!"
else
	su - oracle -c "ssh-keygen -q -t rsa -N '' -f /export/home/oracle/.ssh/id_rsa" > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo "0:    Generating pub key for oracle user"$opt"....Passed!"
	else
		echo "1:    Failed to generate pub key for oracle user"$opt"!"
		exit 1
	fi
fi

#set limits for oracle user
echo -e "\n\n#set limits for oracle user\nulimit -n 65536\nulimit -s 32768" >> $profile
echo "0:    Setting oracle user limits"$opt"....Passed!"
}

MountMP(){
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
	mount -o cluster -F vxfs $path /$vol > /dev/null 2>&1
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
	maxshm=`echo "$pmem/2"|bc`gb
	perl -i -pe "s/_MAXSHM_/$maxshm/" kernel.$flag
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
if pkg publisher |grep online > /dev/null 2>&1
then
	pkg=`cat $nodelog/pkg.$flag|xargs -n 1000`
	pkg install $pkg
else
	echo "1:    No valid publisher to install packages"
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
