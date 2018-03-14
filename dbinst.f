#!/bin/bash
#dev by bentley any suggestion please contact bentley.xu@veritas.com

#function area
Usage(){
cat << EOF
ERROR!
Usage:
	/orainst/oradbinst -node node1,node2,... -vers Version -type TYPE [-storagetype STTYPE][-step STEP][-racip SCANIP,VIP1,VIP2[,VIP3,xxx]][-image BASE_PATH] [-mount MountPoint]

		Nodes     : node1,node2 means installing Oracle to target
		Version   : 6 digtal like 121020
		TYPE	  : RAC or SI is supported currently.RACONENODE is TBD.
		STTYPE    : Storage Type to store crs/database stuff.Currently it supports below option and default is FS:VCFS.
				FS:VCFS
				ASM:VXVOL
		STEP	  : steps will be done. Default is 1-5
				1: only do step 1
				1-3:do step 1 to step 3
				RAC=1:DOENV,2:DOINSTGRID,3:DOSETGRID,4:DODBBIN,5:DODBCA
				SI=1:DOENV,2:DODBBIN,3:DONETCA,4:DODBCA
		SCANIP	  : single client access name,only for RAC
		VIP	  : public virtual ip for node,only for RAC
		BASE_PATH : the upper level directory of grid,database 
		MountPoint:
			    if you provide mountpoint,oradbinst will not check the fs to store oracle stuff
			    if RAC:need fill 3 mountpoint with the format after OCRVOTE:DB:ARC
			    if  SI:need fill 3 mountpoint with the format after DB:ARC:FA
				OCRVOTE:mountpoint to store ocrdata and votedisk
				DB:mountpoint to store datafile
				ARC:mountpoint to store archivelogs
				FA:mountpoint to store fastrecover

#dev by bentley,any issue/suggestion please contact bentley.xu@veritas.com

EOF
exit 1
}

CheckARG(){
#check args
i=0
opts=`echo "$ARGS"|sed -r "s/ -node | -vers | -racip | -image | -mount | -step | -type | -storagetype /\n&/g"|sed -r "s/^\s+//"`
for opt in node vers racip image mount type step storagetype
do
        arg[$i]=`echo "$opts"|grep "^-$opt"|awk '{print $2}'`
        [ "$i" -le 1 ] && [[ "${arg[$i]}" =~ ^$|^-|,$ ]] && Usage
        i=$[$i+1]
done

if [[ "${arg[0]}" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]
then
        noden0=`echo "${arg[0]}"|awk -F "," '{print NF}'`
        noden1=`echo "${arg[0]}"|grep -oP "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"|wc -l`
        if [ "$noden0" -ne "$noden1" ]
        then
                echo -e "\nYou can not use mixed hostname and ip to be nodename!\n"
                exit 1
        fi
fi

mountn=`echo "${arg[4]}"|sed -r "s/:/\n/g"|grep -v ^$|wc -l`

if [ "${arg[5]}" = RAC ]
then
        rac=1
	echo "${arg[0]}"|grep "," > /dev/null 2>&1 || Usage
        [ -z "${arg[2]}" ] && Usage
        [ $mountn -eq 3 -o $mountn -eq 0 ] || Usage
elif [ "${arg[5]}" = SI ]
then
        rac=0
        echo "$opts"|grep "\-racip" > /dev/null 2>&1 && Usage
        [ $mountn -eq 3 -o $mountn -eq 0 ] || Usage
else
        Usage
fi

if [ -z "${arg[6]}" ]
then
	STEP=1,9
elif echo "${arg[6]}"|grep -P "^[0-9]$|^[0-9]-[0-9]$" > /dev/null 2>&1
then
	STEP=`echo ${arg[6]}|sed "s/-/,/"`
else
	Usage
fi

if [ -z "${arg[7]}" ]
then
	storagetype="FS:VCFS"
else
	storagetype=${arg[7]}
	echo "$storagetype"|grep -P "FS:VCFS|ASM:VXVOL" > /dev/null 2>&1 || Usage
fi

#check compat for type and storagetype
if [ $rac = 0 ]
then
	[ $storagetype = "FS:VCFS" ] || Usage
fi

#check if server is client
SERVER=`hostname|cut -d . -f 1`
if echo "${arg[0]}"|sed -r "s/,/\n/g"|cut -d . -f 1|grep "^$SERVER$" > /dev/null 2>&1 
then
	echo -e "You can not install oracle to the OADT server!\n"
	exit 1
fi

NODES=`echo ${arg[0]}|sed "s/,/ /g"`
NODESN=`echo "$NODES"|awk '{print NF}'`

#echo "node:${arg[0]}"
#echo "vers:${arg[1]}"
#echo "racip:${arg[2]}"
#echo "image:${arg[3]}"
#echo "mount:${arg[4]}"
#echo "type:${arg[5]}"
#echo "step:${arg[6]}"
#echo "storagetype:${arg[7]}"
}

SetKnownHost(){
[ -f /etc/ssh/ssh_config.oradbinst ] &&  return 0
cp -f /etc/ssh/ssh_config /etc/ssh/ssh_config.oradbinst
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
echo "UserKnownHostsFile /dev/null" >> //etc/ssh/ssh_config
}

Report(){
local time ret stime etime exp stime0 etime0
cat $log|grep Configuring > /dev/null 2>&1 || return 0
ret=$1
[ $ret = 0 ] && ret=SUCC || ret=FAIL
exp="^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} "
stime=`cat $log |grep -P "$exp"|head -1|awk '{print $1 " " $2}'`
etime=`cat $log |grep -P "$exp"|tail -1|awk '{print $1 " " $2}'`
stime0=`date -u +%s -d "$stime"`
etime0=`date -u +%s -d "$etime"`
time=$[$etime0-$stime0]
time="`echo $time/60|bc`m`echo $time%60|bc`s"
echo "$stime|${arg[0]}|$OSType|${arg[1]}|${arg[5]}|$ret|$time" >> $report
}

myexit(){
local ret=$1
if [ $ret -ne 255 ]
then
	Report $ret
fi
Log "END"
echo $ret > $retcode
rm -f $locallog/pid
exit $ret
}


Log(){
#to store log
local type des date space
type=$1
des=$2
date=`date "+%Y-%m-%d %H:%M:%S"`
if [ "$type" = ERROR ]
then
	type="  $type"
elif [ "$type" = INFO ]
then
	type="   $type"
elif [ "$type" = END ]
then
	type="    $type"
fi
echo "$date $type $des" >> $log
}

RemoteLog(){
local output type content 
output=$1
echo "$output"|while read line
do
	type=`echo "$line"|cut -d : -f 1`
	content=`echo "$line"|cut -d : -f 2`
	if [ $type = 0 ]
	then
		Log "INFO" "$content"
	elif [ $type = 1 ]
	then
		Log "ERROR" "$content"
		myexit 1
	elif [ $type = 2 ]
	then
		Log "Warning" "$content"
	fi
done
return $?
}

#replaceString key1,key2,key3.. value1,,value2,,value3.. filename
ReplaceString(){
local keys values file i exp
keys=$1
values=$2
file=$3
[ -f $file ] || return 1
keys=(`echo "$keys"|sed "s/,/ /g"`)
values=(`echo "$values"|sed "s/,,/ /g"`)
[ "${#keys[*]}" -ne "${#values[*]}" ] && return 1
for ((i=0;i<${#keys[*]};i++))
do
	exp+="s/${keys[$i]}/${values[$i]}/g;"
done
sed -i "$exp" $file
[ $? -eq 0 ] && return 0 || return 1
}

MaskConvert(){
local m0 n
local mask=$1
if [[ $mask =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
	echo $mask
else
	for n in 0 2 4 8
	do
		m0=${mask:$n:2}
		echo $((16#$m0))
	done|xargs -n1000|sed "s/ /\./g"
fi
}

CopyPubKey(){
local user file target
user=$1
file=$2
target=$3
password=`echo "$conf"|grep ^ORACLEPW=|cut -d = -f 2`
expect << EOF > /dev/null 2>&1
#expect << EOF
set timeout $TIMEOUT
spawn $COPYID -i $file $user@$target
expect {
	"(yes/no)?" {
		send "yes\r";
		exp_continue
		}
	"word:" {
		send "$password\r";
		expect {
			eof {exit 0}
			"word:" {exit 1}
		    	}
		}
	eof     {
		exit 0
		}
	timeout {
		exit 3
		}
}
EOF
}

CheckSshAuthorize(){
local user target
user=$1
target=$2
expect << EOF >/dev/null 2>&1
#expect << EOF
set timeout $TIMEOUT
spawn ssh -l $user $target
expect {
   "*#" {
      exit 0
   }
   "*>" {
      exit 0
   }
   '*$' {
      exit 0
   }
   "*word: " {
      exit 1
   }
   eof {
      exit 2
   }
   timeout {
      exit 3
   }
}
expect eof
EOF
return $?
}


CheckNode(){
#check if node is sshable
local node nodes ip i
nodes=$1
for node in $NODES
do
	if ! nmap -p 22 $node|grep -P "open\s+ssh" > /dev/null 2>&1
	then
		Log "ERROR" "$node is not sshable!"
		myexit 1
	elif ! CheckSshAuthorize root $node
	then
		Log "ERROR" "Failed to login $node with wop-ssh!"
		myexit 1
	fi	
	$base/etc/setssh $node > /dev/null 2>&1
done

#check host resolv
for node in $NODES
do
        if ! ping -c 1 `$SSH $node "hostname"` > /dev/null 2>&1
        then
                Log "ERROR" "Please check hostname on $node!"
                myexit 1
        fi
done

if echo $nodes|grep "," > /dev/null 2>&1
then
	Log "INFO" "Checking if nodes are wop-sshable....Passed!"
else
	Log "INFO" "Checking if node is wop-sshable....Passed!"
fi


#check node's subnets
i=0
privpre=`echo "$conf"|grep "^PRIVPRE="|cut -d = -f 2`
if [ -z "$privpre" ]
then
        Log "ERROR" "Please specify PRIVPRE=xxx in the para.conf,like PRIVPRE=192"
        myexit 1
fi
for node in $NODES
do
        ip=`ping -c 1 $node 2>&1 |grep icmp_seq|grep -oP "\d+\.\d+\.\d+\.\d+"`
        mask=`$SSH $ip "ifconfig -a"|grep -P ":$ip | $ip "|sed -r "s/.*ask[:]*//"|awk '{print $1}'|sed "s/^0x//"`
	if [ -z "$mask" ]
	then
		Log "ERROR" "Failed to get netmask of \"$node\"!"
		myexit 1
	fi
	mask=`MaskConvert "$mask"`
	PRIVATE[$i]=`echo "$ip"|sed -r "s/^[0-9]+/$privpre/"`
	subnet[$i]=`ipcalc -n $ip $mask|cut -d = -f 2`
	IP[$i]=$ip
	i=$[$i+1]
done
PRIVNET=`ipcalc -n ${PRIVATE[0]} $mask|cut -d = -f 2`
PRIVATE=`echo ${PRIVATE[*]}|sed "s/ /,/g"`
NETMASK=$mask
i=`echo ${subnet[*]}|xargs -n1|sort -n|sort -u|wc -l`
if [ $i -ne 1 ]
then
	Log "ERROR" "the nodes \"$nodes\" you sepecified do not belong to the same subnet!"
	myexit 1
fi
Log "INFO" "Checking if nodes belong to the same subnet....Passed!"
return 0
}

CheckTypeKernel(){
#check nodes' if  os type and kernel are the same
local output
i=`echo ${os[*]}|xargs -n1|sort -n|sort -u|wc -l`
if [ $i -eq 1 ]
then
	Log "INFO" "Checking if nodes belong to the same OS Type....Passed!"
else
        Log "ERROR" "the nodes \"$nodes\" you sepecified are not the same OS Type!"
        myexit 1
fi

i=`echo ${oskey[*]}|xargs -n1|sort -n|sort -u|wc -l`
if [[ "${os[0]}" =~ AIX ]]
then
	output="TL and SP"
elif [[ "${os[0]}" =~ Sol ]]
then
	output="update"
elif [[ "${os[0]}" =~ RHEL|SUSE ]]
then
	output="kernel"	
fi
if [ $i -eq 1 ]
then
        Log "INFO" "Checking if nodes belong to the same $output....Passed!"
else
        Log "ERROR" "the nodes \"$nodes\" you sepecified are not the same $output!"
        myexit 1
fi
return 0
}

CheckComp(){
#check support list 
local node nodes type vers os oskey i content kernel pkg image swap free out
nodes=$1
vers=$2
i=0
free=0
for node in $NODES
do
	type=`$SSH $node "uname"|cut -c 1`
	case $type in 
		L)
			os[$i]=`$SSH $node "[ -f /etc/redhat-release ] && echo RHEL || echo SUSE"`
			os[$i]+=`$SSH $node "[ -f /etc/redhat-release ] && cat /etc/redhat-release || cat /etc/SuSE-release"|grep -oP "(?<=release )\d+|(?<=Server )\d+"`
			oskey[$i]=`$SSH $node "uname -r"`
			;;
		A)
			os[$i]="AIX`$SSH $node "oslevel"|cut -c 1-3`"
			oskey[$i]=`$SSH $node "oslevel -s"`
			;;
		S)
			out=`$SSH $node "uname -a"`
			if echo "$out"|grep sparc > /dev/null 2>&1
			then
				os[$i]="Solaris`echo "$out"|awk '{print $3}'|cut -d '.' -f 2`sparc"
				oskey[$i]=`$SSH $node "cat /etc/release"|grep -oP "(?<=_u|11.|12.)[0-9]+"`
				oskey[$i]=${os[$i]}u${oskey[$i]}
			else
				echo "Solaris Sparc is supported only"
				exit 1
			fi
			;;
		*)
			Log "ERROR" "Invalid OS or the OS is not in support list"
			myexit 1
	esac
	i=$[$i+1]
done

OSType=${os[0]}
OS=$type

if echo $nodes|grep "," > /dev/null 2>&1
then
	CheckTypeKernel
fi
content=`GetContent "$OSType -- $vers"`
kernel=`echo "$content"|grep ^kernel|head -1`
pkg=`echo "$content"|grep ^pkg|head -1`
image=`echo "$content"|grep ^image|head -1`
gridrsp=`echo "$content"|grep ^gridrsp|head -1`
dbbinrsp=`echo "$content"|grep ^dbbinrsp|head -1`
netcarsp=`echo "$content"|grep ^netcarsp|head -1`
dbcarsp=`echo "$content"|grep ^dbcarsp|head -1`

if [ -z "$kernel" ] || [ `GetContent "$kernel"|wc -l` = 0 ] 
then
	Log "ERROR" "$OSType -- $vers not supported:missing kernel parameters in the config file!"
	myexit 1
fi

if [ -z "$pkg" ] || [ `GetContent "$pkg"|wc -l` = 0 ]
then
        Log "ERROR" "$OSType -- $vers not supported:missing necessary package list in the config file!"
        myexit 1
fi

if [ -z "$image" ] || [ `GetContent "$image"|wc -l` = 0 ]
then
        Log "ERROR" "$OSType -- $vers not supported:missing necessary image path in the config file!"
        myexit 1
fi

if [ -z "$gridrsp" ] || [ `GetContent "$gridrsp"|wc -l` = 0 ]
then
        Log "ERROR" "$OSType -- $vers not supported:missing clusterware responsefile in the config file!"
        myexit 1
fi

if [ -z "$dbbinrsp" ] || [ `GetContent "$dbbinrsp"|wc -l` = 0 ]
then
        Log "ERROR" "$OSType -- $vers not supported:missing database binary responsefile in the config file!"
        myexit 1
fi

if [ -z "$netcarsp" ] || [ `GetContent "$netcarsp"|wc -l` = 0 ]
then
        Log "ERROR" "$OSType -- $vers not supported:missing listener responsefile in the config file!"
        myexit 1
fi

if [ -z "$dbcarsp" ] || [ `GetContent "$dbcarsp"|wc -l` = 0 ]
then
        Log "ERROR" "$OSType -- $vers not supported:missing database responsefile in the config file!"
        myexit 1
fi

Log "INFO" "Checking if the combination $OSType -- $vers in support list....Passed!"
return 0
}

CheckRacIP(){
#check if rac ip is valid
local nodes ip ips sub n n0 n1
nodes=$1
ips=$2
n0=`echo "$nodes"|sed -r "s/,/\n/g"|sort -n|sort -u|wc -l`
n1=$[$n0+1]
[ -z "$ips" ] && return 0
n=`echo "$ips"|sed -r "s/,/\n/g"|sort -n|sort -u|wc -l`
if [ "$n" = "$n1" ]
then
	Log "INFO" "Checking if amount of SCANIP and VIP is right....Passed!"
else
	Log "ERROR" "There must be 1 SCAIP and $n0 VIPs!"
	myexit 1
fi

for ip in `echo "$ips"|sed -r "s/,/\n/g"`
do
	sub=`ipcalc -n $ip $mask|cut -d = -f 2`
	if [ "$sub" != "${subnet[0]}" ] 
	then
		Log "ERROR" "SCANIP or VIP must belong to subnet \"$subnet\"!"
		myexit 1
	fi
	
done
Log "INFO" "Checking if SCANIP or VIP belong to subnet \"$subnet\"....Passed!"

for ip in `echo "$ips"|sed -r "s/,/\n/g"`
do
        if ping -c 1 $ip > /dev/null 2>&1
        then
                Log "ERROR" "$ip is in use!"
                myexit 1
        fi
done
Log "INFO" "Checking if SCANIP or VIP are usable....Passed!"

return 0
}

CheckImage(){
return 0
#check if image exist
local nodes path vers n dbver crsver
nodes=$1
vers=$2
path=$3
[ -z "$path" ] && return 0
n=`$SSH $node1 "ls $path/*/runInstaller"|xargs -n1|wc -l`
dbver=`$SSH $node1 "cat $path/*/stage/products.xml"|grep -oP "(?<=NAME=\"oracle.server\" VER=\")[\w.]+"|sed "s/\.//g"`
if echo $nodes|grep "," > /dev/null 2>&1
then
	crsver=`$SSH $node1 "cat $path/*/stage/products.xml"|grep -oP "(?<=NAME=\"oracle.crs\" VER=\")[\w.]+"|sed "s/\.//g"`
	if [ $n -eq 2 -a "$dbver" = "$vers" -a "$crsver" = "$vers" ]
	then
		Log "INFO" "Checking if image under the Path \"$path\" is valid....Passed!"
	else
		Log "ERROR" "The image under the Path \"$path\" is invalid!"
		myexit 1
	fi
else
	if [ $n -ge 1 -a "$dbver" = "$vers" ]
	then
		Log "INFO" "Checking if image under the Path \"$path\" is valid....Passed!"
	else
		Log "ERROR" "The image under the Path \"$path\" is invalid!"
		myexit 1
	fi
fi
return 0

}
CheckMount(){
return 0
#need check if mountpoint exist and file size is right
local node nodes mount fs exp mountn
nodes=$1
mount=$2
mountn=`echo "$mount"|sed -r "s/:/\n/g"|sort -n|sort -u|wc -l`
exp=`echo $mount|sed -r "s/\///g;s/:/\$|\//g"`
[ -z "$mount" ] && return 0
for node in $NODES
do
	if [[ "$OSType" =~ RHEL|SUSE|Solaris ]]
	then
		fs=`timeout 60 $SSH $node "df -h|sed 1d|xargs -n6"` 
	elif [[ "$OSType" =~ AIX ]]
	then
		fs=`timeout 60 $SSH $node "df -g"`
	fi
	mountn0=`echo "$fs"|grep -P "/$exp$"|wc -l`
	if [ $mountn0 -ne $mountn ]
	then
		Log "ERROR" "Please check the mount points you specified!"
		myexit 1
	fi
done
}

GetContent(){
local n n0 n1 key
key=$1
n=`echo "$conf"|grep -nP "^$key{"|cut -d : -f 1`	
[ -z "$n" ] && return 1
n1=`echo "$conf"|grep -n "^}"|cut -d : -f 1`
n0=`echo "$n $n1"|xargs -n1|sort -n|grep -A 1 "^$n$"|tail -1`
n=$[$n+1]
n0=$[$n0-1]
echo "$conf"|sed -n "$n,$n0"p
}

gzopen1(){
local file1 file2 line
file1=$1
file2=$2
line=`head -4 $file1|grep -oP "(?<=skip=)\d+"`
tail -n +$line $file1 > $file2.gz
gunzip $file2.gz
}
gzopen(){
local file1 file2
file1=$1
file2=$2
cat $file1 > $file2
}

#copy scripts and files to target
CopyFile(){
local vers image mount ips i j node nodeip nodevip nodevip0 pubcard privcard networks mountmp ocrdata votedisk fastrecover archive
[ -z "${arg[3]}" ] && image=0 || image=1
[ -z "${arg[4]}" ] && mount=0 || mount=1
[ -z "${arg[2]}" ] && ips=0 || ips=${arg[2]}
if [ "${arg[1]}" = 121020 ]
then
	vers=12.1.0
elif [ "${arg[1]}" = 112040 ]
then
	vers=11_2_0
fi	
mountmp=(`echo "${arg[4]}"|sed -r "s/:/ /g"|sed "s/\///g"`)
mountmpn=${#mountmp[*]}
dbname=`echo "$conf"|grep ^dbname=|cut -d = -f 2|head -1`
if [ -z "$dbname" ]
then
	Log "ERROR" "Please specify dbname=xxx in the para.conf,like dbname=orcl!"
	myexit 1
fi
flag=`echo "$RANDOM"00|cut -c 1-2;echo "$RANDOM"00|cut -c 1-2`
flag=`echo $flag|sed "s/ //g"`
ntp=`echo "$conf"|grep "^NTP="|cut -d = -f 2`
clusname=rac
for node in `echo "${arg[0]}"|sed "s/,/ /g"`
do
	if [[ "$node" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]
	then	
		clusname+=`echo $node|cut -d . -f 4`	
		nodevip0=`host $node|head -1|awk '{print $NF}'|cut -d . -f 1` || nodevip0=`cat /etc/hosts|grep -P "$node "|awk '{print $2}'|cut -d . -f 1|head -1`
		if [ -z "$nodevip0" ]
		then
			Log "ERROR" "Failed to get hostname by ipaddr \"$node\"!"
			myexit 1
		fi
	else
		host $node > /dev/null 2>&1 && nodeip=`host $node|head -1|awk '{print $NF}'` || nodeip=`cat /etc/hosts|grep -P " $node | $node$"|awk '{print $1}'`
		if [ -z "$nodeip" ]
		then
			Log "ERROR" "Failed to get IP by hostname \"$node\"!"
			myexit 1
		fi
		clusname+=`echo $nodeip|cut -d . -f 4`
		nodevip0=`echo $node|cut -d . -f 1`
	fi
	nodevip+=$nodevip0:$nodevip0-vip,
	hostname+=$nodevip0,
done
hostname=`echo $hostname|sed "s/,$//"`
if [ $rac = 1 ]
then
	nodevip=`echo $nodevip|sed "s/,$//"`
	pubcard=`$SSH $node1 "ifconfig -a" 2>&1|grep -B 1 "${IP[0]}"|grep -oP "^\w+"|head -1`
	privcard=`$SSH $node1 "lltstat -nvv active" 2>&1|grep -A 1 OPEN|tail -1|awk '{print $1}'`
	networks=$pubcard:${subnet[0]}:1,$privcard:$PRIVNET:2
fi
if [ $mount = 0 ]
then
       	ocrdata=ocrvote
       	votedisk=ocrvote
	case $storagetype in 
		FS:VCFS)
			dbdata=dbdata
			fastrecover=archive
			archive=archive
			;;
		ASM:VXVOL)
			dbdata=+dbarchasm
			fastrecover=+dbarchasm
			archive=+dbarchasm
			;;
		*)
			Log "ERROR" "Invalid Storage Type!"
			myexit 1
	esac
else
       	dbdata=${mountmp[0]}
	fastrecover=${mountmp[$mountmpn-2]}
	archive=${mountmp[$mountmpn-1]}
fi
#generate list file for kernel pkg plus
for i in `GetContent "$OSType -- ${arg[1]}"`
do
	j=`echo $i|sed -r "s/[0-9]+$//"`
	GetContent "$i" > $script/$j.$flag
done
cd $script
for i in `ls|grep rsp`
do
	mv $i $i.rsp
done

#generate setfs,setconf,rsp
gzopen $base/etc/io_oracle.sh $script/io_oracle.sh
if [ "$OS" = L ]
then
	sed -i "1s/.*/#\!\/bin\/bash/" $script/io_oracle.sh
fi
case $OS in 
	L|A|S)
		gzopen $base/etc/setfs_$OS.sh $script/setfs.$flag
		gzopen $base/etc/setconf_$OS.sh $script/setconf.$flag
		gzopen $base/etc/setdb_$OS.sh $script/setdb.$flag
		;;
	*)
		myexit 1
esac

#replace the upper case VAR
ReplaceString _RAC_,_FLAG_,_STTYPE_ $rac,,$flag,,"$storagetype" $script/setfs.$flag
if [ $? -ne 0 ]
then
	Log "ERROR" "Failed to replace String for file \"$script/setfs.$flag\"!"
	myexit 1
fi
ReplaceString _FLAG_,_IPS_,_NODE1_,_NODES_,_NTP_,_PRIVIP_,_MASK_,_RAC_,_OSTYPE_,_MOUNT_,_CLUSNAME_,_STTYPE_ "$flag",,"$ips",,"$node1",,"${arg[0]}",,"$ntp",,"$PRIVATE",,"$NETMASK",,"$rac",,"$OSType",,"$mount",,"$clusname",,"$storagetype" $script/setconf.$flag &&
#below is for aix only
ReplaceString CAP_BYPASS1VMM CAP_BYPASS_RAC_VMM $script/setconf.$flag
ReplaceString CAP_BYPASS0VMM CAP_BYPASS_RAC_VMM $script/setconf.$flag
if [ $? -ne 0 ]
then
	Log "ERROR" "Failed to replace String for file \"$script/setconf.$flag\"!"
	myexit 1
fi

ReplaceString _OSTYPE_,_DBNAME_,_RAC_ "$OSType",,"$dbname",,"$rac" $script/setdb.$flag
if [ $? -ne 0 ]
then
	Log "ERROR" "Failed to replace String for file \"$script/setdb.$flag\"!"
	myexit 1
fi
#special operation for oracle 11g
[[ "${arg[1]}" =~ ^11 ]] && sed -i -r "s/.*srvctl.*/\t\/oracle\/orahome\/bin\/srvctl stop database -d \$dbname -o immediate -f > \/dev\/null 2>\&1/" $script/setdb.$flag

ReplaceString _VERSION_,_NODE1_,_HOSTNAMES_ "$vers",,"$node1",,"$hostname" $script/dbbinrsp.$flag.rsp
if [ $? -ne 0 ]
then
	Log "ERROR" "Failed to replace String for file \"$script/dbbinrsp.$flag.rsp\"!"
	myexit 1

fi

ReplaceString _VERSION_,_DBNAME_,_TYPE_,_DBDATA_,_FASTRECOVER_,_ARCHIVE_ "$vers",,"$dbname",,"${arg[5]}",,"$dbdata",,"$fastrecover",,"$archive" $script/dbcarsp.$flag.rsp
if [ $? -ne 0 ]
then
	Log "ERROR" "Failed to replace String for file \"$script/dbcarsp.$flag.rsp\"!"
	myexit 1
fi

#replace string for netcarsp
ReplaceString _VERSION_ "$vers" $script/netcarsp.$flag.rsp

if [ $rac = 1 ]
then
	ReplaceString _VERSION_,_NODE1_,_CLUSNAME_,_NODEVIP_,_NETWORKS_,_VOTEDISK_,_OCRDATA_,_FLAG_ "$vers",,"$node1",,"$clusname",,"$nodevip",,"$networks",,"$votedisk",,"$ocrdata",,"$flag" $script/gridrsp.$flag.rsp
	if [ $? -ne 0 ]
	then
		Log "ERROR" "Failed to replace String for file \"$script/gridrsp.$flag.rsp\"!"
		myexit 1
	fi
	case $storagetype in
		FS:VCFS)
			sed -i "/BEGINVXVOL/,/ENDVXVOL/"d $script/gridrsp.$flag.rsp
			;;
		ASM:VXVOL)
			sed -i "/BEGINVCFS/,/ENDVCFS/"d $script/gridrsp.$flag.rsp 
			sed -i "s/FS/ASM/" $script/gridrsp.$flag.rsp
			[ $OS = A ] && sed -i "s/LOCAL_ASM_STORAGE/ASM_STORAGE/" $script/gridrsp.$flag.rsp
			;;
		*)
			Log "ERROR" "Invalid Storage Type!"
			myexit 1
	esac
	sed -r -i "/BEGIN|END/"d $script/gridrsp.$flag.rsp
else
	cat $script/dbcarsp.$flag.rsp|grep -vP "^CREATESERVERPOOL|^SERVERPOOLNAME|^CARDINALITY|^FORCE" > $script/dbcarsp.$flag.rsp1
	mv $script/dbcarsp.$flag.rsp1 $script/dbcarsp.$flag.rsp
	cat $script/dbbinrsp.$flag.rsp|grep -v CLUSTER_NODES > $script/dbbinrsp.$flag.rsp1
	mv $script/dbbinrsp.$flag.rsp1 $script/dbbinrsp.$flag.rsp
fi

#ASM only
[[ $storagetype =~ ^ASM ]] && sed -i "s/\///g" $script/dbcarsp.$flag.rsp
		
#scp to remote nodes
cd $script
#ls|grep ^set|xargs -n1 gzexe > /dev/null 2>&1
#gzexe io_oracle.sh
#rm -f *~
chmod 777 * 
for node in `echo ${arg[0]}|sed "s/,/ /g"`
do
	$SSH $node "mkdir -p $nodelog" > /dev/null 2>&1 &&
	$SCP * $node:$nodelog/ > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		Log "INFO" "Copying scripts and files to Node \"$node\"....Passed!"
	else
		Log "ERROR" "Failed to copy scripts and files to Node \"$node\"!"
		myexit 1
	fi	
done
}

#check avaiable san disk and create fs
SetORAFS(){
local node nodes noden output
nodes=$1
noden=`echo "$nodes"|sed -r "s/,/\n/g"|wc -l`
if [ $rac = 1 ]
then
	if [ `$SSH $node1 "/opt/VRTS/bin/hagrp -state" 2>&1|grep cvm|grep ONLINE|wc -l` -eq $noden ]
	then
		Log "INFO" "Checking if CVM are online....Passed!"
	else
		Log "ERROR" "CVM of Nodes \"$nodes\" are not all online!"
		myexit 1
	fi
elif [ $rac = 0 ]
then
	for node in $NODES
	do
		if $SSH $node "ls -l /opt/VRTS/bin/vxdisk" > /dev/null 2>&1
		then
			Log "INFO" "Checking if SF is installed on node \"$node\"....Passed!"
		else
			Log "ERROR" "SF is not installed on node \"$node\"!"
			myexit 1
		fi
	done
fi
Log "INFO" "Configuring filesystem for Oracle Installation...."
#clean if exist mount point and dg
for node in $NODES
do
        $SSH $node "umount /archive;umount /dbdata;umount /ocrvote" > /dev/null 2>&1
	mp=`timeout 60 $SSH $node "df"|grep -P "/ocrvote$|/dbdata$|/archive$"|awk '{print $NF}'|xargs -n 100`
	if [ -n "$mp" ]
	then
        	Log ERROR "Please umount $mp manually before install oracle on \"$node\"!"
        	myexit 1
	fi
done
for node in $NODES
do
	dgs=`$SSH $node "vxdg list"|grep -P "^oradg[0-9]{4}"|awk '{print $1}'|xargs -n1000`
	[ -n "$dgs" ] && $SSH $node "for i in $dgs; do vxdg destroy \$i; done"
done
#get avaiable share disk among nodes
if [ $NODESN = 1 ]
then
	disks=`/orainst/etc/getdisk ${arg[0]} local`
else
	disks=`/orainst/etc/getdisk ${arg[0]} share`
fi
if [ $? -ne 0 ]
then
	Log ERROR "Failed to get share disk among nodes \"${arg[0]}\"!"
	myexit 1
fi
echo "$disks"| $SSH $node1 "cat > $nodelog/disks"

output=`$SSH $node1 "$nodelog/setfs.$flag" 2>&1 |grep -P "^[0-9]:"`
RemoteLog "$output"
if [ $? -eq 0 ]
then
	sed -i -r "s/\.\.\.\.$/&Passed\!/" $log
else
	sed -i -r "s/\.\.\.\.$/&Failed\!/" $log
	sed -i "/Failed/s/ INFO/ERROR/" $log
	exit 1
fi
}

MountImage(){
local type
type=`$SSH $node "uname"|cut -c 1`
[ $type = A ] && $SSH $node "nfso -o nfs_use_reserved_ports=1"
timeout 60 $SSH $node "! df|grep /oraimge && mkdir -p /oraimage && mount $path /oraimage" > /dev/null 2>&1
timeout 60 $SSH $node "df|grep /oraimage" > /dev/null 2>&1
if [ $? -eq 0 ]
then
	Log "INFO" "Mounting oracle iamge to /oraimage on the node \"$node\"....Passed!"
else
	Log "ERROR" "Failed to mount oracle image on the node \"$node\"!"
	myexit 1
fi
}

#set env and config 
SetENV(){
local output nodes node path image i j
nodes=$1
#execute setconf
for node in $NODES
do
	Log "INFO" "Configuring required stuff and install required packages on node \"$node\"...."
	output=`$SSH $node "$nodelog/setconf.$flag" 2>&1 |grep -P "^[0-9]:"`
	RemoteLog "$output"
	if [ $? -eq 0 ]
	then
		sed -i -r "s/\.\.\.\.$/&Passed\!/" $log
	else
		sed -i -r "s/\.\.\.\.$/&Failed\!/" $log
		sed -i "/Failed/s/ INFO/ERROR/" $log
		exit 1
	fi
done

#clean /tmp directory
for node in $NODES
do
	$SSH $node "rm -rf /tmp/CVU* /tmp/Ora*" > /dev/null 2>&1
done

#mount image path
image=`GetContent "$OSType -- ${arg[1]}"|grep image|head -1`
path=`GetContent "$image"`
if [ -z "${arg[3]}" ]
then
	for node in $NODES
	do
		MountImage
		[ $rac = 1 ] && break
	done
fi

#set oracle authorization among each

if CheckSshAuthorize oracle $node1
then
	Log "INFO" "Configuring oracle user equivalence....Passed!"
	return 0
fi
[ $OS = S ] && sshbase=/export/home/oracle/.ssh || sshbase=/home/oracle/.ssh
for node in $NODES
do
	$SCP $node:$sshbase/id_rsa.pub $pubkey/id_rsa.pub.$node > /dev/null 2>&1
done
for node in $NODES
do
	CopyPubKey oracle /root/.ssh/id_rsa.pub $node
	if [ $? -ne 0 ]
	then
		Log "ERROR" "Failed to configure oracle user equivalence from Install Server to node \"$node\"!"
		myexit 1
	fi
	for i in `cd $pubkey;ls id_rsa.pub*`
	do
		j=`echo $i|sed "id_rsa.pub.//"`
		CopyPubKey oracle $pubkey/$i $node
		if [ $? -ne 0 ]
		then
			Log "ERROR" "Failed to configure oracle user equivalence from node \"$j\" to node \"$node\"!"
			myexit 1
		fi
	done
done
Log "INFO" "Configuring oracle user equivalence....Passed!"
[ $OS = A ] && RebootNodes
return 0
}

RebootNode(){
local node status device
node=$1
status=0
>$locallog/reboot.$node.log
Log "INFO" "    Rebooting node $node...."
$SSH $node "sync;sync;sync;nohup reboot -n > /dev/null 2>&1 &"
for i in {1..720}
do
	if nmap -p 22 $node 2>&1 |grep " open " > /dev/null 2>&1 
	then
		echo "`date "+%Y-%m-%d %H:%M:%S"` SSH of $node is open" >> $locallog/reboot.$node.log
		[ $status = 1 ] && status=2
	else
		echo "`date "+%Y-%m-%d %H:%M:%S"` SSH of $node is closed" >> $locallog/reboot.$node.log
		status=1
	fi
	sleep 5
	[ $status = 2 ] && break
done
sleep 10
device=`cat $logdir/log.$node1|grep -oP "(?<=private ip for \")\w+"|head -1`
gzopen $base/etc/bootenv.sh /tmp/bootenv.sh
(cat /tmp/bootenv.sh;rm -rf /tmp/bootenv.sh) | $SSH $node "cat > /tmp/bootenv.sh;sh -x /tmp/bootenv.sh" > $locallog/bootenv.$node.log 2>&1
if [ $? -eq 0 ]
then
	sed -i -r "s/Rebooting node $node\.\.\.\./&Passed\!/" $log
	echo "reboot action is finished" >> $locallog/reboot.$node.log
else
	sed -i -r "s/Rebooting node $node\.\.\.\./&Failed\!/" $log
	sed -i "/Failed/s/ INFO/ERROR/" $log
	echo "reboot action is failed" >> $locallog/reboot.$node.log
fi
}

RebootNodes(){
local node
Log "INFO" "Rebooting all nodes to make settings effictive...."
for node in $NODES
do
	{
		RebootNode $node
	} &
done
wait
if cat $log|grep Rebooting|grep -i error > /dev/null 2>&1 
then
	sed -i -r "s/settings effictive\.\.\.\./&Failed\!/" $log 
	sed -i "/Failed/s/ INFO/ERROR/" $log
	myexit 1
else
	sed -i -r "s/settings effictive\.\.\.\./&Passed\!/" $log
fi
}


TypeLog(){
logtype=remote
return 0
local node=$1
[ -d $orainstlog/$node ] || mkdir -p $orainstlog/$node
if timeout 60 df | grep /orainstlog/$node$ > /dev/null 2>&1
then
	logtype=local
	return 0
else
	mount -o rw,vers=3 $node:/var/orainst $orainstlog/$node
	if [ $? -eq 0 ]
	then
		logtype=local
		Log "INFO" "    Mounting oracle installation log from the node \"$node\"....Passed!"
	else
		logtype=remote
		Log "WARNING" "    Failed to mount oracle installation log from the node \"$node\"!"
	fi
fi
}

UmountLog(){
return 0
local node=$1
timeout 60 df|grep $orainstlog/$node$ > /dev/null || return 0
umount $orainstlog/$node > /dev/null 2>&1
if [ $? -eq 0 ]
then
	Log "INFO" "    Umounting oracle installation log....Passed!"
else
	Log "WARNING" "    Failed to umount oracle installation log!"
fi
}

ReadLog(){
local file node
node=$1
file=$2
file=`basename $file`
if [ "$logtype" = local ]
then
	cat $orainstlog/$node/$file 2>&1
else
	$SSH $node "cat /var/orainst/$file" 2>&1
fi
return $?
}

FetchLog(){
local node file
node=$1
file=$2
file=`basename $file`
if [ "$logtype" = local ]
then
	cp -f $orainstlog/$node/$file $locallog/
else
        $SCP $node:/var/orainst/$file $locallog/ 2>&1
fi
return $?
}

InstallGRID(){
local output log0 log1 node per time0 time time1 installer vers n i suf
node=$1
vers=$2

#check if private ip pingable from each node
#for i in `cat $logdir/log.$node1|grep -oP "(?<=with ipaddr \")[0-9\.]+"`
#do
#	$SSH $node1 "ping -c 1 $i" > /dev/null 2>&1
#	if [ $? -ne 0 ]
#	then
#		Log "ERROR" "    Please check private ip for each node....!"
#		myexit 1
#	fi
#done

#begin stuff for grid
installer=/oraimage/grid/runInstaller
log0=/var/orainst/gridinst.log
$SSH $node1 "ls -l $installer" 2>&1|grep -oP "^[\w-]+x" > /dev/null
if [ $? -ne 0 ]
then
        Log "ERROR" "    Missing installation file \"runInstaller\" or it is not executable!"
        myexit 1
fi
if [ -z "$flag" ]
then
	flag=`$SSH oracle@$node1 "ls -lrt /var/orainst/*" 2>&1|grep gridrsp|awk '{print $NF}'|tail -1|cut -d . -f 2`
	if [ -z "$flag" ]
	then
		Log "ERROR" "    Missing Grid response file....!"
		myexit 1
	fi
fi

#get the log type
TypeLog $node1

time0=`date -u +%s`
time1=$[$time0+3600]
$SSH oracle@$node1 "rm -f $log0;echo y|$installer -showProgress -silent -ignoreSysPrereqs -ignorePrereq -responseFile /var/orainst/gridrsp.$flag.rsp >> $log0 2>&1"
Log "INFO" "    Installing grid binary to $node....0%"
for i in {1..1000}
do
	output=`ReadLog $node1 $log0`
	per=`echo "$output"|grep -oP "[0-9]+%"|tail -1`
	[ -z "$per" ] && per=0%
	sed -i -r "s/grid binary to $node\.\.\.\.[0-9]+%/grid binary to $node....$per/" $log
	time=`date -u +%s`
	if [ "$per" = 100% ]
	then
		break
	elif [ $time -ge $time1 ] || echo "$output"|grep -iP "fatal|error" > /dev/null 2>&1
	then
		sed -i -r "s/grid binary to $node\.\.\.\.[0-9]+%/grid binary to $node....Failed/" $log
		sed -i "/Failed/s/ INFO/ERROR/" $log
		break
	fi
	sleep 5
done
for log1 in `echo "$output"|grep -oP "/orainst.*\.log"`
do
	$SSH $node1 "cp $log1 /var/orainst/;chmod 777 /var/orainst/*" > /dev/null 2>&1
	FetchLog $node1 $log1
done
FetchLog $node1 $log0
UmountLog $node1
if [ "`cat $log|grep "grid binary to $node...."|grep -oP "[0-9]+%"`" = 100% ]
then
	sed -i -r "s/Installing Grid binary\.\.\.\./&Passed\!/" $log
	Log "INFO" "STEP $stepno:\"$run:Installing Grid binary for Oracle ${arg[5]} Installation\"....Passed!"
else
	sed -i -r "s/Installing Grid binary\.\.\.\./&Failed\!/" $log
	sed -i "/Failed/s/ INFO/ERROR/" $log
	myexit 1
fi

#fix the bug of ohasd for redhat 7
[ -z "$OSType" ] && OSType=`cat $logdir/log.$node1|grep -oP "(?<=combination )\w+"`
[[ "${arg[1]}" =~ ^11 ]] && [ $OSType = RHEL7 ] && TSORA11GRHEL7
}

CRSRoot(){
local node ret log0
node=$1
$SSH $node "/crs/crshome/root.sh" > $locallog/crs_root.sh.$node.log 2>&1
ret=$?
log0=`cat $locallog/crs_root.sh.$node.log|grep -oP "/crs.*\.log"`
[ -n "$log0" ] && $SSH $node "cat $log0" > $locallog/crs_root.sh.$node.log 2>&1
if [ $ret -eq 0 ]
then
	Log "INFO" "    Running \"/crs/crshome/root.sh\" on the node \"$node\"....Passed!"
else
	Log "ERROR" "    Failed to run \"/crs/crshome/root.sh\" on the node \"$node\"!"
	myexit 1
fi
}

CRSRoot_A(){
local node ret log0 i
node=$1
echo -e "/crs/crshome/root.sh\necho ret=\$?\nchown root:system /.." | $SSH $node "cat > /tmp/AIXCRSROOT.sh;nohup sh /tmp/AIXCRSROOT.sh > /var/orainst/crs_root.sh.$node.log 2>&1 &"
sleep 300
for i in {1..1000}
do
	$SSH $node "cat /var/orainst/crs_root.sh.$node.log"|grep "ret=" > /dev/null 2>&1 && break
	sleep 5
done
log0=`$SSH $node "cat /var/orainst/crs_root.sh.$node.log"|grep -oP "/crs.*\.log"`
[ -n "$log0" ] && $SSH $node "cat $log0" > $locallog/crs_root.sh.$node.log 2>&1
if $SSH $node "cat /var/orainst/crs_root.sh.$node.log"|grep "ret=0" > /dev/null 2>&1
then
        Log "INFO" "    Running \"/crs/crshome/root.sh\" on the node \"$node\"....Passed!"
else
        Log "ERROR" "    Failed to run \"/crs/crshome/root.sh\" on the node \"$node\"!"
        myexit 1
fi
}

ConfigureGRID(){
local node nodes ret log0 crscmd
nodes=$1
for node in $NODES
do
	$SSH $node "/orainst/oraInventory/orainstRoot.sh" > $locallog/crs_orainstRoot.sh.$node.log 2>&1
	if [ $? -eq 0 ]
	then
		Log "INFO" "    Running \"/orainst/oraInventory/orainstRoot.sh\" on the node \"$node\"....Passed!"
	else
		Log "ERROR" "    Failed to run \"/orainst/oraInventory/orainstRoot.sh\" on the node \"$node\"!"	
		myexit 1
	fi
done
[ -z "$OS" ] && OS=`$SSH $node1 "uname"|cut -c 1`
[ "$OS" = A ] && crscmd=CRSRoot_A || crscmd=CRSRoot
$crscmd $node1
for node in `echo "$nodes"|sed -r "s/,/\n/g"|grep -v $node1`
do
	{
		$crscmd $node
	} &
done
wait
if cat $log|grep -i error > /dev/null 2>&1
then
	sed -i -r "s/Configuring Grid Service\.\.\.\./&Failed\!/" $log
	sed -i "/Failed/s/ INFO/ERROR/" $log 
	myexit 1
else
	sed -i -r "s/Configuring Grid Service\.\.\.\./&Passed\!/" $log
	Log "INFO" "STEP $stepno:\"$run:Configuring Grid service for Oracle ${arg[5]} Installation\"....Passed!"
fi

#do special operation for oracle 11g
[[ "${arg[1]}" =~ ^11 ]] && TSORA11G
}

InstallDBBin(){
local output log0 log1 i node0 node per time0 time time1 installer vers ret
node0=$1
node=$2
vers=$3
installer=/oraimage/database/runInstaller
log0=/var/orainst/dbbininst.log
$SSH $node1 "ls -l $installer" 2>&1|grep -oP "^[\w-]+x" > /dev/null
if [ $? -ne 0 ]
then
	Log "ERROR" "    Missing installation file \"runInstaller\" or it is not executable!"
	myexit 1
fi
if [ -z "$flag" ]
then
        flag=`$SSH oracle@$node1 "ls -lrt /var/orainst/*" 2>&1|grep dbbinrsp|awk '{print $NF}'|tail -1|cut -d . -f 2`
        if [ -z "$flag" ]
        then
                Log "ERROR" "    Missing database binary response file....!"
                myexit 1
        fi
fi

#get the log type
TypeLog $node0

time0=`date -u +%s`
time1=$[$time0+3600]
$SSH oracle@$node0 "rm -f $log0;echo y|$installer -showProgress -silent -ignoreSysPrereqs -ignorePrereq -responseFile /var/orainst/dbbinrsp.$flag.rsp >> $log0 2>&1"
Log "INFO" "    Installing database binary to $node....0%"
for i in {1..1000}
do
	output=`ReadLog $node0 $log0`
	per=`echo "$output"|grep -oP "[0-9]+%"|tail -1`
	[ -z "$per" ] && per=0%
	sed -i -r "s/database binary to $node\.\.\.\.[0-9]+%/database binary to $node....$per/" $log
	time=`date -u +%s`
	if [ "$per" = 100% ]
	then
		break
	elif [ $time -ge $time1 ] || echo "$output"|grep -iP "fatal|error" > /dev/null 2>&1
	then
		sed -i -r "s/database binary to $node\.\.\.\.[0-9]+%/database binary to $node....Failed/" $log
		sed -i "/Failed/s/ INFO/ERROR/" $log
		break
	fi
	sleep 5
done

for log1 in `echo "$output"|grep -oP "/orainst.*\.log"`
do
        $SSH $node0 "cp $log1 /var/orainst/;chmod 777 /var/orainst/*" > /dev/null 2>&1
        FetchLog $node0 $log1
done
FetchLog $node0 $log0
UmountLog $node0

if [ "`cat $log|grep "database binary to $node...."|grep -oP "[0-9]+%"`" = 100% ]
then
	for node0 in `echo $node|sed "s/,/ /g"`
	do
		$SSH $node0 "/oracle/orahome/root.sh" > $locallog/ora_root.sh.$node0.log 2>&1
		ret=$?
		log0=`cat $locallog/ora_root.sh.$node0.log|grep -oP "/oracle.*\.log"`
        	[ -n "$log0" ] && $SSH $node0 "cat $log0" > $locallog/ora_root.sh.$node0.log 2>&1
		if [ $ret -eq 0 ]
		then
			Log "INFO" "    Running \"/oracle/orahome/root.sh\" on the node \"$node0\"....Passed!"
		else
			Log "ERROR" "    Failed to run \"/oracle/orahome/root.sh\" on the node \"$node0\"!"
			myexit 1
		fi
	done
else
	myexit 1
fi
}

CreateLSN(){
local node netca log0
node=$1
netca=/oracle/orahome/bin/netca
log0=$locallog/netca_$node.log
$SSH oracle@$node "$netca -silent -responseFile /var/orainst/netcarsp.$flag.rsp && echo "Stopping Listener" && /oracle/orahome/bin/lsnrctl stop" >> $log0 2>&1
if [ $? -eq 0 ]
then
	Log "INFO" "    Configuring Listener on the node \"$node\"....Passed!"
else
	Log "ERROR" "    Faile to configure Listener on the node \"$node\"!"
	myexit 1
fi
}

CreateDB(){
local output log0 log1 i node0 node per time0 time time1 dbca vers sid
node0=$1
node=$2
log0=$locallog/dbca.log
dbca=/oracle/orahome/bin/dbca
> $log0
if [ -z "$flag" ]
then
        flag=`$SSH oracle@$node0 "ls -lrt /var/orainst/*" 2>&1|grep dbcarsp|awk '{print $NF}'|tail -1|cut -d . -f 2`
        if [ -z "$flag" ]
        then
                Log "ERROR" "    Missing database creatation response file....!"
                myexit 1
        fi
fi

#check if need create asm dg
[ $storagetype = ASM:VXVOL ] && CreateASM $node0 dbarchasm /dev/vx/rdsk/oradg"$flag"_dbarchasm/dbarchvol

time0=`date -u +%s`
time1=$[$time0+5000]
nohup $SSH oracle@$node0 "$dbca -silent -continueOnNonFatalErrors true -responseFile /var/orainst/dbcarsp.$flag.rsp" >> $log0 2>&1 &
Log "INFO" "    Creating database on $node....0%"
for i in {1..1000}
do
        output=`cat $log0`
        per=`echo "$output"|grep -oP "[0-9]+%"|tail -1`
        [ -z "$per" ] && per=0%
        sed -i -r "s/database on $node\.\.\.\.[0-9]+%/database on $node....$per/" $log
        time=`date -u +%s`
        if [ "$per" = 100% ]
        then
                break
        #elif [ $time -ge $time1 ] || echo "$output"|grep -iP "fatal|error" > /dev/null 2>&1 || echo "$output" |grep -n further | grep ^1: > /dev/null 2>&1
        elif [ $time -ge $time1 ] || echo "$output" |grep -n further | grep ^1: > /dev/null 2>&1
        then
                sed -i -r "s/database on $node\.\.\.\.[0-9]+%/database on $node....Failed/" $log
		sed -i "/Failed/s/ INFO/ERROR/" $log
                break
        fi
        sleep 5
done

#copy dbca detail log
dbca_detail_log=`cat $log0|grep further|grep -oP "(?<=\")[^\" ]+"`
rm -rf $locallog/dbca_detail.log
$SCP $node0:$dbca_detail_log $locallog/dbca_detail.log

if [ "`cat $log|grep "database on $node...."|grep -oP "[0-9]+%"`" = 100% ]
then
	for node0 in `echo $node|sed "s/,/ /g"`
	do
		[ -z "$dbname" ] && dbname=`echo "$conf"|grep ^dbname=|cut -d = -f 2|head -1`
		if [ $rac = 1 ]
		then
			sid=`$SSH $node0 "ls /oracle/orahome/dbs"|grep init$dbname|grep -oP "$dbname[^.]*"`
		else
			sid=$dbname
		fi
		$SSH oracle@$node0 "/var/orainst/setdb.$flag $sid" > $locallog/setdb.$node0.log 2>&1
		if [ $? -eq 0 ]
		then
			Log "INFO" "    Finishing oracle database settings on the node \"$node0\"....Passed!"
		else
			Log "WARNING" "    Failed to run \"/var/orainst/setdb.$flag $sid\" on the node \"$node0\"!"
			Log "WARNING" "    Please manually run \"/var/orainst/setdb.$flag $sid\" on the node \"$node0\"!"
		fi
	done
	[ $rac = 0 ] && CopyPFILE "${arg[0]}"
	sed -i -r "s/Creating database to all nodes\.\.\.\./&Passed\!/" $log
	Log "INFO" "STEP $stepno:\"$run:Creating database for Oracle ${arg[5]} Installation\"....Passed!"
	Log "INFO" "Congratulations!!! You have got Oracle ${arg[5]} installed on ${arg[0]}!"
	myexit 0
else
	sed -i -r "s/Creating database to all nodes\.\.\.\./&Failed\!/" $log
	sed -i "/Failed/s/ INFO/ERROR/" $log
	myexit 1
fi
}
CopyPFILE(){
local node nodes 
nodes=$1
[ -z "$dbname" ] && dbname=`echo "$conf"|grep ^dbname=|cut -d = -f 2|head -1`
for node in `echo "$nodes"|sed -r "s/,/\n/g"|grep -v $node1`
do
	$SCP -rp oracle@$node1:/oracle/orahome/dbs/orapw$dbname oracle@$node1:/oracle/orahome/dbs/spfile$dbname.ora oracle@$node:/oracle/orahome/dbs/ > /dev/null 2>&1 &&
	$SSH oracle@$node "mkdir -p /oracle/admin/$dbname/adump /oracle/fast_recovery_area/$dbname" > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		Log "INFO" "    Generating pfiles for the node \"$node\"....Passed!"
	else
		Log "Warning" "    Failed to genearate pfiles for the node \"$node\"!"
	fi >> $locallog/copypfile.$node.log
	[[ "${arg[1]}" =~ ^11 ]] && TSORA11GSI $node
done
}
TSORA11G(){
local node
echo 'perl -i -pe "s/IDX=\"1\"/IDX=\"1\" CRS=\"true\"/" inventory.xml'|$SSH oracle@$node1 "cat > /tmp/crstrue.sh && cd /orainst/oraInventory/ContentsXML && cat inventory.xml|grep CRS= > /dev/null 2>&1 ||(cp -p inventory.xml inventory.xml.oradbinst && sh /tmp/crstrue.sh && rm -f /tmp/crstrue.sh)"
$SSH oracle@$node1 "/crs/crshome/bin/netca -silent -responseFile /var/orainst/netcarsp.$flag.rsp;/crs/crshome/bin/lsnrctl status" > $locallog/TSORA11G_netca_$node1.log 2>&1
}
TSORA11GRHEL7(){
local node
for node in $NODES
do
	echo -e "echo \"/etc/init.d/init.ohasd run > /dev/null 2>&1 &\" >> /etc/rc.local\nchmod +x /etc/rc.local\nwhile true\ndo\n\t[ -f /etc/init.d/init.ohasd ] && break\n\tsleep 1\ndone\n/etc/init.d/init.ohasd run"|$SSH $node "cat > /tmp/TSORA11GRHEL7.sh;nohup sh /tmp/TSORA11GRHEL7.sh > /dev/null 2>&1 &"
done
}
TSORA11GSI(){
local nodesi dbdata
nodesi=$1
dbdata=`$SSH $node1 "strings /oracle/orahome/dbs/spfile$dbname.ora"|grep -oP "(?<=control_files='/)\w+"|sed -r "s/^/\//"` 
echo "get dbdata value:$dbdata" >> $locallog/copypfile.$node.log
$SSH oracle@$node1 "[ -f $dbdata/$dbname/control02.ctl ] || (echo "make link file of control02 for node1" && ls -l /oracle/fast_recovery_area/$dbname/* && mv /oracle/fast_recovery_area/$dbname/control02.ctl $dbdata/$dbname/control02.ctl && ln -s $dbdata/$dbname/control02.ctl /oracle/fast_recovery_area/$dbname/control02.ctl)" >> $locallog/copypfile.$nodesi.log 2>&1
$SSH oracle@$nodesi "echo "make link file of control02 for $nodesi" && mkdir -p /oracle/fast_recovery_area/$dbname && ln -s $dbdata/$dbname/control02.ctl /oracle/fast_recovery_area/$dbname/control02.ctl"  >> $locallog/copypfile.$nodesi.log 2>&1
}
CreateASM(){
local node dgname disk
node=$1
dgname=$2
disk=$3
$SSH oracle@$node "/crs/crshome/bin/crsctl status resource -t |grep -i dbarchasm || /crs/crshome/bin/asmca -silent -createDiskGroup -diskGroupName $dgname -disk $disk -redundancy EXTERNAL" > $locallog/createasm.log 2>&1
if [ $? -ne 0 ]
then
	Log "ERROR" "    Failed to create ASM disk group....!"
	myexit 1
fi
}
