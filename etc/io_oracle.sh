#!/usr/bin/sh
#functions
GetSeq(){
local i n
n=$1
i=1
while [ $i -le $n ]
do
        echo $i
        i=`expr $i + 1`
done
}

SanityIO(){
local i table sql flag
flag=$RANDOM$RANDOM$RANDOM$RANDOM
table=tb_"$pid"_"$flag"
sql=/tmp/sql.$pid.$flag
echo "connect / as sysdba;" >> $sql
echo "create table $table" >> $sql
echo "(" >> $sql
echo " ID int," >> $sql
echo " DATA varchar2(3000)" >> $sql
echo ");" >> $sql
for i in $lseq
do
	echo "insert into $table values ($i,'$data');" >> $sql
done
echo "commit;" >> $sql
echo "select ID||',,,'||DATA from $table;" >> $sql
echo "drop table $table;" >> $sql
echo "exit;" >> $sql
if [ "$IOKEEP" = 1 ]
then	
	$ORACLE_HOME/bin/sqlplus /nolog @$sql > $logdir/log.$flag 2>&1
else
	$ORACLE_HOME/bin/sqlplus /nolog @$sql > /dev/null 2>&1
fi
rm -f $sql
}

myexit(){
rm -f /tmp/*$pid*
exec 6>&-
exit 1
}


#main code
pid=$$
echo $pid

#check env
user=`whoami`

#check if oracle user
if [ "$user" != "oracle" ]
then
	echo "$0 can only be executed by oracle user!"
	exit 1
fi
if [ -z "$ORACLE_HOME" -o -z "$ORACLE_SID" ]
then
	echo "Please set ORACLE_HOME and ORACLE_SID in shell profile"
	exit 1
fi

#check if oracle is running
if ! echo "select instance_name,status from v\$instance;"|sqlplus / as sysdba 2>&1 |grep OPEN > /dev/null 2>&1
then
	ehco "ERROR: Database is not open!"
	exit 1
fi
	

if echo $*|grep -i "\-h" > /dev/null 2>&1
then
	echo "Usage:"
	echo "      ./io_oracle.sh Thread Piece_of_DataInsert"
	echo "      Default Thread=10 Piece_of_DataInsert=100"
	echo "      execute \"export IOKEEP=1\" could redirect log to local file!"
	echo
	exit 1
fi


pid=$$
date=`date "+%Y-%m-%d_%H:%M:%S"`
fifo=/tmp/fifo.$pid
logdir=/tmp/io_oracle_$date
[ "$IOKEEP" = 1 ] && mkdir -p $logdir
data="y.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded.Ifconfigisusedtoconfigurethekernel-residentnetworkinterfaces.Itisusedatboottimetosetupinterfacesasnecessary.Afterthat,itisusuallyonlyneededwhendebuggingorwhensystemtuningisneeded."

trap myexit SIGHUP SIGINT SIGQUIT SIGTERM



#counts of threads
thread=$1

#counts of pices of data insert into table
dataline=$2

expr $thread + 0 > /dev/null 2>&1
ret1=$?
expr $dataline + 0 > /dev/null 2>&1
ret2=$?

if [ $# -ne 2 -o $ret1 -ne 0 -o $ret2 -ne 0 ]
then
        thread=10
        dataline=100
fi


#generate fifo file
mkfifo $fifo
exec 6<>$fifo
rm -f $fifo

#define limits of threads
tseq=`GetSeq $thread`
lseq=`GetSeq $dataline`

for i in $tseq
do
	echo 
done >&6

#setup sanity io 
while true
do
	read -u6
	{
		SanityIO
		echo >&6
	} &
done

#close fd6
exec 6>&-
exit 0
