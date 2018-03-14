#!/bin/bash
#dev by bentley any suggestion please contact bentley.xu@veritas.com

if [ `uname` != "Linux" ]
then
	echo "oradbinst can be only executed on Linux OS!"
	exit 1
fi

if [ `whoami` != root ]
then
	echo "oradbinst can be only executed by root user!"
	exit 1
fi

if [[ $0 =~ ^/ ]]
then
	base=`dirname $0`
else
	base=`dirname $0|sed "s/\.//"`
	[ `pwd` = "/" ] && base="`pwd`$base" || base="`pwd`/$base"
	base=`echo $base|sed "s/\/$//"`
fi


#global varible area
pid=$$
ARGS=$*
TIMEOUT=10
SSH="ssh -q -o ConnectTimeout=$TIMEOUT -o PasswordAuthentication=no"
SCP="scp -r -p -q -o ConnectTimeout=$TIMEOUT"
COPYID="$base/etc/ssh_copy_id"
nodelog=/var/orainst
RAC=DOENV,DOINSTGRID,DOSETGRID,DODBBIN,DODBCA
SI=DOENV,DODBBIN,DONETCA,DODBCA

report=$base/.report
funciton=$base/dbinst.f
conf=$base/para.conf

if [ ! -f "$conf" ]
then
	echo "ERROR! Missing parameter config file!"
	exit 1
fi

#source function file
[ -f $funciton ] && . $funciton

#read config file
conf=`cat $base/para.conf`

#setting ssh env
SetKnownHost

#check args
CheckARG


#define log/script 
node1=`echo ${arg[0]}|cut -d , -f 1`
logdir="/var/orainst/$node1"
locallog=$logdir/log

#check existing pid
if [ -f $locallog/pid ]
then
	pid0=`cat $locallog/pid`
	pidnum=`ps -ef|awk '$2=='$pid0'{print $2}'|wc -l`
	[ "$pidnum" -ge 1 ] && echo "Please kill existing process $pid0 first" && exit 1
fi

#prepare env
if [[ $STEP =~ ^1 ]]
then
	rm -rf $logdir/*
	log=$logdir/log.$node1
else
	log=$logdir/log.$node1.part
	> $log
fi
script=$logdir/script
pubkey=$logdir/pubkey
orainstlog=$logdir/orainstlog
retcode=$logdir/retcode
for subdir in $script $pubkey $orainstlog $locallog
do
	[ -d "$subdir" ] || mkdir -p $subdir
done
echo $pid > $locallog/pid

trap "myexit 255" SIGHUP SIGINT SIGQUIT SIGTERM

#check and setup env.
DOENV(){
#check inputs
CheckNode "${arg[0]}" && CheckComp "${arg[0]}" "${arg[1]}" && CheckRacIP "${arg[0]}" "${arg[2]}" && CheckImage "${arg[0]}" "${arg[1]}" "${arg[3]}" && CheckMount "${arg[0]}" "${arg[4]}"

#copy files and scripts
CopyFile


#check san storage and create relevant FS
[ -z "${arg[4]}" ] && SetORAFS "${arg[0]}" 

#set env,config,image
SetENV "${arg[0]}"
Log "INFO" "STEP $stepno:\"$run:Setting up environment for Oracle ${arg[5]} Installation\"....Passed!"
}

DOINSTGRID(){
Log "INFO" "Installing Grid binary...."
InstallGRID "${arg[0]}" "${arg[1]}"
}

DOSETGRID(){
Log "INFO" "Configuring Grid Service...."
ConfigureGRID "${arg[0]}"
}

#install database binary
DODBBIN(){
local node checknode
Log "INFO" "Installing database binnary to all nodes...."
if [ $rac = 1 ]
then
	InstallDBBin $node1 "${arg[0]}" "${arg[1]}"
elif [ $rac = 0 ]
then
	for node in $NODES
	do
		{
			InstallDBBin $node $node "${arg[1]}"
		} &
	done
	wait
fi
[ $rac = 1 ] && checknode="$node1" || checknode="$NODES"
for node in $checknode
do
	if [ "`cat $log|grep "database binary to $node...."|grep -oP "[0-9]+%"`" != 100% ]
	then
		sed -i -r "s/Installing database binnary to all nodes\.\.\.\./&Failed\!/" $log
		sed -i "/Failed/s/ INFO/ERROR/" $log
		myexit 1
	fi
done
sed -i -r "s/Installing database binnary to all nodes\.\.\.\./&Passed\!/" $log
Log "INFO" "STEP $stepno:\"$run:Installing database binary for Oracle ${arg[5]} Installation\"....Passed!"
}

DONETCA(){
local node
Log "INFO" "Configuring Listener on all nodes...."
for node in $NODES
do
	CreateLSN $node
done
Log "INFO" "STEP $stepno:\"$run:Configuring Listener for Oracle ${arg[5]} Installation\"....Passed!"
}

DODBCA(){
Log "INFO" "Creating database to all nodes...."
if [ $rac = 1 ]
then
	CreateDB $node1 "${arg[0]}"
else
	CreateDB $node1 $node1
fi
}

if [ $rac = 1 ]
then
	for run in `echo "$RAC"|sed -r "s/,/\n/g"|sed -n "$STEP"p`
	do
		stepno=`echo "$RAC"|sed -r "s/,/\n/g"|grep -n $run|cut -d : -f 1`
		$run
	done
elif [ $rac = 0 ]
then
	for run in `echo "$SI"|sed -r "s/,/\n/g"|sed -n "$STEP"p`
	do
		stepno=`echo "$SI"|sed -r "s/,/\n/g"|grep -n $run|cut -d : -f 1`
		$run
	done
fi
myexit 0
