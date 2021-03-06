#!/usr/bin/env bash

# turn on debug
exec 1>/tmp/tarsnap-generations_sh_trace.log 2>&1
set -o xtrace

#See README @ https://github.com/bob912/Tarsnap-generations/blob/master/README

#Forked from https://github.com/Gestas/Tarsnap-generations/ then modified for personal use cases.

#########################################################################################
#What day of the week do you want to take the weekly snapshot? Default = Friday(5)	#
WEEKLY_DOW=5 										#
#What hour of the day to you want to take the daily snapshot? Default = 11PM (23)	#
DAILY_TIME=23										#
#Do you want to use UTC time? (1 = Yes) Default = 0, use local time.			#
USE_UTC=0										#
#Path to GNU date binary (e.g. /bin/date on Linux, /usr/local/bin/gdate on FreeBSD)	#
DATE_BIN=`which date`									#
#Make tarsnap binary an absolute path so it works inside cron				#
TARSNAP_BIN='/usr/local/bin/tarsnap'							#
#########################################################################################
usage ()
{
cat << EOF
usage: $0 arguments

This script manages Tarsnap backups

ARGUMENTS:
	 ?   Display this help.    
	-f   Path to a file with a list of folders to be backed up. List should be \n delimited.  
	-h   Number of hourly backups to retain.
	-d   Number of daily backups to retain.
	-w   Number of weekly backups to retain.
	-m   Number of monthly backups to retain.
        -q   Be quiet - only output if something goes wrong

For more information - http://github.com/Gestas/Tarsnap-generations/blob/master/README
EOF
}

cygwin_os=0
openbsd_os=0
slackware_os=0
other_os=0

if [[ `uname -s` = CYGWIN* ]]; then
	cygwin_os=1
	HOSTNAME=`hostname`
	#The last day of the current month. I wish there was a better way to do this, but this seems to work everywhere.
	LDOM=$(echo $(cal -h) | awk '{print $NF}')
elif [[ `uname -s` = OpenBSD* ]]; then
	openbsd_os=1
	HOSTNAME=`hostname -s`
	LDOM=$(echo $(cal) | awk '{print $NF}')
	DADD_BIN=`which dadd`
else
	if [[ `grep '^NAME' /etc/os-release | cut -f2 -d=` = Slackware ]]; then
		slackware_os=1
                HOSTNAME=`hostname -s`
		#The last day of the current month. I wish there was a better way to do this, but this seems to work everywhere.
		LDOM=$(echo $(cal --color=never) | awk '{print $NF}')
	else
		other_os=1
                HOSTNAME=`hostname -s`
		#The last day of the current month. I wish there was a better way to do this, but this seems to work everywhere.
		LDOM=$(echo $(cal -h) | awk '{print $NF}')
	fi
fi

#Declaring helps check for errors in the user-provided arguments. See line #69.
declare -i HOURLY_CNT
declare -i DAILY_CNT
declare -i WEEKLY_CNT
declare -i MONTHLY_CNT
declare -i QUIET

QUIET=0

#Get the command line arguments. Much nicer this way than $1, $2, etc. 
while getopts ":f:h:d:w:m:q" opt ; do
	case $opt in
		f ) PATHS=$OPTARG ;;
		h ) HOURLY_CNT=$(($OPTARG+1)) ;;
		d ) DAILY_CNT=$(($OPTARG+1)) ;;
		w ) WEEKLY_CNT=$(($OPTARG+1)) ;;
		m ) MONTHLY_CNT=$(($OPTARG+1)) ;;
	        q ) QUIET=1 ;;
		\?) echo \n $usage
			exit 1 ;;
		 *) echo \n $usage
			exit 1 ;;	
	esac
done

#Check arguments
if ( [ -z "$PATHS" ] || [ -z "$HOURLY_CNT" ] || [ -z "$DAILY_CNT" ] || [ -z "$WEEKLY_CNT" ] || [ -z "$MONTHLY_CNT" ] ) 
then
	echo "-f, -h, -d, -w, -m are not optional."
	usage
	exit 1
fi

if [ ! -f $PATHS ]
then
        echo "Couldn't find file $PATHS"
        usage
        exit 1
fi

TARSNAP_ARGS=()
if [ $QUIET = "1" ]
then
	# Pass --quiet to suppress harmless tarsnap warnings
	TARSNAP_ARGS+=( --quiet )
	# Prevent stats output
	TARSNAP_ARGS+=( --no-print-stats )
fi

#Check that $HOURLY_CNT, $DAILY_CNT, $WEEKLY_CNT, $MONTLY_CNT are numbers.
if ( [ $HOURLY_CNT = 1 ] || [ $DAILY_CNT = 1 ] || [ $WEEKLY_CNT = 1 ] || [ $MONTHLY_CNT = 1 ] )
then
	echo "-h, -d, -w, -m must all be numbers greater than 0."
	usage
	exit 1
fi

#Set some constants
#The day of the week (Monday = 1, Sunday = 7)
DOW=$($DATE_BIN +%u)
#The calendar day of the month
DOM=$($DATE_BIN +%d)
#We need 'NOW' to be constant during execution, we set it here.
NOW=$($DATE_BIN +%Y%m%d-%H)
CUR_HOUR=$($DATE_BIN +%H)
if [ "$USE_UTC" = "1" ] ; then
	NOW=$($DATE_BIN -u +%Y%m%d-%H)
	CUR_HOUR=$($DATE_BIN -u +%H)
fi

#Find the backup type (HOURLY|DAILY|WEEKLY|MONTHY)
BK_TYPE=HOURLY	#Default to HOURLY
if ( [ "$DOM" = "$LDOM" ] && [ "$CUR_HOUR" = "$DAILY_TIME" ] ) ; then
	BK_TYPE=MONTHLY
else
        if ( [ "$DOW" = "$WEEKLY_DOW" ] && [ "$CUR_HOUR" = "$DAILY_TIME" ] ) ; then
        	BK_TYPE=WEEKLY
	else
                if [ "$CUR_HOUR" = "$DAILY_TIME" ] ; then
			BK_TYPE=DAILY
                fi
        fi
fi

#Take the backup with the right name 
if [ $QUIET != "1" ] ; then
    echo "Starting $BK_TYPE backups..."
fi

# remove space from the field delimiters that are used in the for loops
# this allows to backup directory names with spaces
OLD_IFS=$IFS
IFS=$(echo -en "\n\b")

for dir in $(cat $PATHS) ; do
	$TARSNAP_BIN "${TARSNAP_ARGS[@]}" -c -f $NOW-$BK_TYPE-$HOSTNAME-$(echo ${dir//\//.}) --one-file-system -C / $dir
	if [ $? = 0 ] ; then
	    if [ $QUIET != "1" ] ; then
		echo "$NOW-$BK_TYPE-$HOSTNAME-$(echo ${dir//\//.}) backup done."
	    fi
	else
		errcode=$?
		echo "$NOW-$BK_TYPE-$HOSTNAME-$(echo ${dir//\//.}) backup error. Exiting" ; exit $errcode
	fi
done	

#Check to make sure the last set of backups are OK.
if [ $QUIET != "1" ] ; then
    echo "Verifying backups, please wait."
fi

archive_list=$($TARSNAP_BIN --list-archives)

for dir in $(cat $PATHS) ; do
	case "$archive_list" in
		*"$NOW-$BK_TYPE-$HOSTNAME-$(echo ${dir//\//.})"* )
		if [ $QUIET != "1" ] ; then
		    echo "$NOW-$BK_TYPE-$HOSTNAME-$(echo ${dir//\//.}) backup OK."
		fi ;;
		* ) echo "$NOW-$BK_TYPE-$HOSTNAME-$(echo ${dir//\//.}) backup NOT OK. Check --archive-list."; exit 3 ;; 
	esac
done

#Delete old backups
if [ $openbsd_os = "1" ] ; then
	HOURLY_DELETE_TIME=$($DATE_BIN +%Y%m%d)-$($DADD_BIN -f %H $($DATE_BIN +%H:%M:%S) -${HOURLY_CNT}h)
	DAILY_DELETE_TIME=$($DADD_BIN -f %Y%m%d $($DATE_BIN +%Y-%m-%d) -${DAILY_CNT}d)-$($DATE_BIN +%H)
	WEEKLY_DELETE_TIME=$($DADD_BIN -f %Y%m%d $($DATE_BIN +%Y-%m-%d) -${WEEKLY_CNT}w)-$($DATE_BIN +%H)
	MONTHLY_DELETE_TIME=$($DADD_BIN -f %Y%m%d $($DATE_BIN +%Y-%m-%d) -${MONTHLY_CNT}m)-$($DATE_BIN +%H)
else
	HOURLY_DELETE_TIME=$($DATE_BIN -d"-$HOURLY_CNT hour" +%Y%m%d-%H) 
	DAILY_DELETE_TIME=$($DATE_BIN -d"-$DAILY_CNT day" +%Y%m%d-%H)
	WEEKLY_DELETE_TIME=$($DATE_BIN -d"-$WEEKLY_CNT week" +%Y%m%d-%H)
	MONTHLY_DELETE_TIME=$($DATE_BIN -d"-$MONTHLY_CNT month" +%Y%m%d-%H)
fi

if [ $QUIET != "1" ] ; then
    echo "Finding backups to be deleted."
fi

if [ $BK_TYPE = "HOURLY" ] ; then
	for backup in $archive_list ; do
		case "$backup" in
			 "$HOURLY_DELETE_TIME-$BK_TYPE"* ) 	
					case "$backup" in   #this case added to make sure the script doesn't delete the backup it just took. Case: '-h x' and backup takes > x hours. 
						*"$NOW"* ) echo "Skipped $backup" ;;
						* )  $TARSNAP_BIN "${TARSNAP_ARGS[@]}" -d -f $backup
							if [ $? = 0 ] ; then
							    if [ $QUIET != "1" ] ; then
              							echo "$backup snapshot deleted."
							    fi
     					   		else
								errcode=$?
           							echo "Unable to delete $backup. Exiting" ; exit $errcode
        						fi ;;
					esac ;;
			* ) ;;
		esac
 	done
fi


if [ $BK_TYPE = "DAILY" ] ; then
        for backup in $archive_list ; do
                case "$backup" in
                         "$DAILY_DELETE_TIME-$BK_TYPE"* )
					 case "$backup" in
                                                *"$NOW"* ) echo "Skipped $backup" ;;
                                                * )  $TARSNAP_BIN "${TARSNAP_ARGS[@]}" -d -f $backup
                                       			 if [ $? = 0 ] ; then
							     if [ $QUIET != "1" ] ; then 
                                                		echo "$backup snapshot deleted."
							     fi
                                           		else
								errcode=$?
                                                		echo "Unable to delete $backup. Exiting" ; exit $errcode
                                        		fi ;;
					 esac ;;
                        * ) ;;
                esac
        done
fi

if [ $BK_TYPE = "WEEKLY" ] ; then
        for backup in $archive_list ; do
                case "$backup" in
                         "$WEEKLY_DELETE_TIME-$BK_TYPE"* ) 
					 case "$backup" in
                                                *"$NOW"* ) echo "Skipped $backup" ;;
                                                * ) $TARSNAP_BIN "${TARSNAP_ARGS[@]}" -d -f $backup
                                        		if [ $? = 0 ] ; then
							    if [ $QUIET != "1" ] ; then
                                                		echo "$backup snapshot deleted."
							    fi
                                           		else
								errcode=$?
                                                		echo "Unable to delete $backup. Exiting" ; exit $errcode
                                        		fi ;;
					esac ;;
                        * ) ;;
                esac
        done
fi

if [ $BK_TYPE = "MONTHLY" ] ; then
        for backup in $archive_list ; do
                case "$backup" in
                         "$MONTHLY_DELETE_TIME-$BK_TYPE"* ) 
					 case "$backup" in
                                                *"$NOW"* ) echo "Skipped $backup" ;;
                                                * ) $TARSNAP_BIN "${TARSNAP_ARGS[@]}" -d -f $backup
                                        		if [ $? = 0 ] ; then
							    if [ $QUIET != "1" ] ; then
                                                		echo "$backup snapshot deleted."
							    fi
                                           		else
								errcode=$?
                                                		echo "Unable to delete $backup. Exiting" ; exit $errcode
                                        		fi ;;
					esac ;;
                        * ) ;;
                esac
        done
fi

# restore old IFS value
IFS=$OLD_IFS

if [ $QUIET != "1" ] ; then
    echo "$0 done"
fi

