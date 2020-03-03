#!/bin/ksh 

####################################################################
# Script Name : Install_Platform.sh				   #
# Purpose     : This script is used for installing Platform Layer  #
#	        for MM component installation.			   #
# Platforms   : RHEL Linux					   #
####################################################################

echo "$@" | grep debug >/dev/null 2>&1
[ $? -eq 0 ] && {
	export PS4="Executing -->   "
	set -x
}

USER="`id | sed 's/).*//;s/.*(//'`"
if [ "${USER}" != "root" ]
then
	echo
	echo "You have to be root user to run this script."
	echo "Login as root."
	echo "Exiting....."
	exit 1
fi


export TOOL_DIR=`pwd`/`dirname $0`
export CONF_DIR=${TOOL_DIR}/conf
export LIB_DIR=${TOOL_DIR}/lib/`uname -s`
export DCG_DIR=${TOOL_DIR}/data_collection/`uname -s`
export TEMPLATE_DIR=${TOOL_DIR}/templates/`uname -s`
MISC_DIR="${TOOL_DIR}/misc_files"
export REBOOT="yes"

SKIPTYPE=NONE
unalias cp
unalias mv
export TMOUT=0
umask 022 >/dev/null 2>&1

#-------------------------#
# Sourcing LIB functions  #
#-------------------------#
. ${LIB_DIR}/libfunc_common_platform.sh
. ${LIB_DIR}/libfunc_mm_platform.sh
. ${LIB_DIR}/libfunc_other_platform.sh
. ${LIB_DIR}/libfunc_cfs_platform.sh
. ${LIB_DIR}/libfunc_cps_platform.sh
. ${LIB_DIR}/libfunc_nfs_platform.sh

export PATH=${PATH}:/usr/sbin:/usr/bin:/usr/local/bin:/etc/vx/bin:/opt/VRTSvcs/bin:/opt/VRTSllt:/opt/VRTS/bin

rpm -q "cloud-init" >/dev/null 2>&1
if [ $? -eq 0 ];then
        export CLOUD_SETUP="Y"
fi


#------------------------------------------------------
# MAIN LOGIC
#------------------------------------------------------
export AWK="/usr/bin/awk"

if [ -f /dev/shm/reboot_immediate ]; then
	Highlighter "\n--> Please reboot the machine before re-executing the command"
	exit 111
fi


#------------------------------------------#
# Exporting command line arguments, so that# 
# they can be used in Functions		   #
#------------------------------------------#
export cmd_args="$@"
[ -z ${cmd_args} ] && {
	Usage
	Highlighter "\n[Usage Error] : Mandatory parameter(s) is missing. Please check !!!\n"
	exit 1
}

while getopts "L:E:F:I:C:S:O:Hh" OPTION
do
	case $OPTION in
	h)
		clear
		Usage
		exit 0
		;;
	H)
		clear
		cat ${TOOL_DIR}/templates/`uname -s`/platform_commands.readme | more 
		exit 0
		;;
	E)
		[ "X${OPTARG}" = "X" ] && {
			Usage
			Highlighter  "[ ERROR ] - Argument to -E can not be blank."
			exit 1
		}
		#-------------------------------#
		# Check for valid choices       #
		#-------------------------------#

		if [ ${OPTARG} = "internal" ] || [ ${OPTARG} = "external" ]
		then
			export EXT_STORAGE=${OPTARG}
			[ "${EXT_STORAGE}" = "external" ] && export EXT_STORAGE="other"
		else
			Usage
			Highlighter  "[ ERROR ] - Invalid parameter specified with -E option."
			exit 1
		fi
		;;
	C)
		[ "X${OPTARG}" = "X" ] && {
			Usage
			Highlighter  "[ ERROR ] - Argument to -C can not be blank."
			exit 1
		}
			
		if [ "${OPTARG}" = "STDALONE" ] || [ ${OPTARG} = "CLUSTER" ] || [ ${OPTARG} = "ADDNODE" ] || [ ${OPTARG} = "CPS" ]
		then
			export CONFIGMODE=${OPTARG}
			[ "X${CONFIGMODE}" = "XCPS" ] && export EXT_STORAGE=internal
		else
			Highlighter  "[ ERROR ] - Invalid parameter specified with -C option."
		fi
		;;

	F)
		if [ ${OPTARG} = "EXT4" ] || [ ${OPTARG} = "XFS" ] || [ ${OPTARG} = "VRTS" ] || [ ${OPTARG} = "NFS" ]
		then
			export FSTYPE=${OPTARG}
			export FSTOCREATE=`echo ${FSTYPE} | tr '[A-Z]' '[a-z]'`
			[ "X${FSTOCREATE}" = "Xvrts" ] && export FSTOCREATE=vxfs
		else
			if [ "${EXT_STORAGE}" != "internal" ]; then
				Usage
				Highlighter  "[ ERROR ] - Invalid parameter specified with -F option."
				exit 1
			fi
		fi
		;;
	O)
		[ "X${OPTARG}" = "X" ] && {
			Usage
			Highlighter  "[ ERROR ] - Argument to -O can not be blank."
			exit 1
		}
		#-------------------------------#
		# Check for valid choices       #
		#-------------------------------#

		if [ "X${OPTARG}" = "XNODG" ]
		then
			export CONFIG_DG=${OPTARG}
		else
			Usage
			Highlighter  "[ ERROR ] - Invalid parameter specified with -O option."
			exit 1
		fi
		;;

	L)

		[ "X${OPTARG}" = "X" ] && {
			Usage
			Highlighter  "[ ERROR ] - Argument to -L can not be blank."
			exit 1
		}

		if [ "X${OPTARG}" = "Xdebug" ];then
			export DEBUG_LEVEL=${OPTARG}
		else 
			Usage
			Highlighter "Invalid Option specified with -L option"
			exit 1
		fi
		;;

	S)
		if [ ${OPTARG} = "precheck" ] || [ ${OPTARG} = "ALL" ]
		then
			export SKIPTYPE=${OPTARG}
		fi
		;;

	I)
		[ "X${OPTARG}" = "X" ] && {
			Usage
			Highlighter  "[ ERROR ] - Argument to -I can not be blank."
			exit 1
		}

		case ${OPTARG} in
		default|DEFAULT)
			export SKIPTYPE="ALL"
			export INSTALLATION_TYPE="DEFAULT"
			;;
		*)
			Usage
			Highlighter  "[ ERROR ] - Invalid Argument Value specified with -I option"
			exit 1
			;;
		esac
		;;

	?)
		clear
		Usage
		Highlighter  "[ ERROR ] - Invalid OPTION specified"
		exit
		;;
	esac
done

#-----------------------------------------#
# Validating command line args		  #
#-----------------------------------------#

Validate_Command

#-------------------------#
# Sourcing LIB functions  #
#-------------------------#

. ${CONF_DIR}/`uname -s`/definations_Platform.sh

[ "X${EXT_STORAGE}" = "Xinternal" ] && export CONFIG_DG="NODG"

if [ "X${CONFIGMODE}" = "XSTDALONE" ]; then
	[ "X${CONFIG_DG}" != "XNODG" ] && [ "X${EXT_STORAGE}" = "Xother" ] && check_default_mount_point
fi

#--------------------------------------------------#
# creating /var/adm dir as it does not exist in Linux #
#--------------------------------------------------#
[ ! -f ${INSTALL_LOG_FILE} ] && mkdir -p `dirname ${INSTALL_LOG_FILE}` >/dev/null 2>&1


[ "X${SKIPTYPE}" = "X" ] && SKIPTYPE="NONE"

/usr/bin/hostnamectl 2>/dev/null | grep "Virtualization:" >/dev/null 2>&1
[ $? -eq 0 ] && export HW_TYPE="VIRTUALIZED" || export HW_TYPE="NATIVE_HARDWARE"

##########################
#Check Cloud Environment #
##########################
/usr/sbin/dmidecode -t System | grep -w "OpenStack" >/dev/null 2>&1
[ $? -eq 0 ] && export HW_TYPE="CLOUD"

[ "X${SKIPTYPE}" != "Xprecheck" ] && Validate_prereq

Generate_Status_File

#------------------------------------------------------------------------#
# Opening Platform.ini file for Platform installation and configuration  #
#------------------------------------------------------------------------#

[ ! -s ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} ] && {
	cp ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}.eric ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
	Collect_info ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
}

if [ "X${SKIPTYPE}" != "XALL" ];then
#	cp -f ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}_priv >/dev/null 2>&1
	#Edittemplate ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
        echo "not openning template"
fi

cp -f ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}_orig >/dev/null 2>&1
#diff ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}_priv >/dev/null 2>&1
#if [ $? -ne 0 ];then

cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}_orig | grep -v "^\ " | grep -v "^$" > ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
Validate_platform_template ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
mv -f ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}_orig ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}

[ "${CONFIGMODE}" = "CPS" ] && Validate_CPS_Template ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
[ "${CONFIGMODE}" = "ADDNODE" ] && Validate_Template_Add_Node ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
[ "${CONFIGMODE}" = "CLUSTER" ] && Validate_CFS_Template ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}

echo "================Following template was validated=======================" >> ${INSTALL_LOG_FILE}
cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} >> ${INSTALL_LOG_FILE}
echo "=======================================================================" >> ${INSTALL_LOG_FILE}
#fi

#rm -f ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}_priv >/dev/null 2>&1

Start_Log_Platform

[ "X${HW_TYPE}" = "XNATIVE_HARDWARE" ] && export MTEXT=" multipathed pseudo devices" || export MTEXT="disk devices"

#-------------------------------#
# Opening  Templates ...        # 
#-------------------------------#
stdluns=`echo ${DATADG} | awk '{ print NF }'`
clusluns=`expr ${stdluns} + 3`

case ${CONFIGMODE} in

CLUSTER)

	case ${FSTYPE} in
	NFS)
		if [ "X${IO_FENCING_TYPE}" = "XCPS" ]; then
			Get_And_Validate_Input_CPS ${Cluster_Name}
			perl -pi -e "s/^Other_Setup_DG/#Other_Setup_DG/g" ${PRODUCT_INSTALL_STATUS_FILE}
			ASK_LUN="N"
		else
			${VXDISK} -o alldgs list | grep cdsdisk | grep -w ${IOFENDG} >/dev/null 2>&1
			if [ $? -ne 0 ]; then 
				clear
				${ECHO} "\n**************************************************************************"
				${ECHO} "For Basic Cluster setup (I/O Fencing) No of ${MTEXT} required = 3"
				${ECHO} "**************************************************************************\n"
				yorn "Requisite Number of ${MTEXT} exposed to the Cluster Node(s) for DISK based I/O Fencing ? (y/n) : "
				ASK_LUN="Y"
				export oDGS_single="${IOFENDG}"
			else
				perl -pi -e "s/^Other_Setup_DG/#Other_Setup_DG/g" ${PRODUCT_INSTALL_STATUS_FILE}
			fi
		fi
	;;
	VRTS)
		if [ "X${IO_FENCING_TYPE}" = "XCPS" ]; then
			if [ "X${CONFIG_DG}" != "XNODG" ];then
				if [ `${VXDISK} -o alldgs list 2>/dev/null | grep "online" | egrep "sliced|cdsdisk" | egrep -w "mmdatadg|mmdbdg" | wc -l` -lt 2 ];then
					clear
					${ECHO} "\n**************************************************************************"
					${ECHO} "For Cluster setup No of ${MTEXT} required = ${stdluns}"
					${ECHO} "**************************************************************************\n"
					yorn "Requisite Number of ${MTEXT} exposed to the Cluster Node(s) for CPS based I/O Fencing ? (y/n) : "
					ASK_LUN="Y"
					export oDGS_single="${DATADG}"
				fi
			else
				perl -pi -e "s/^Other_Setup_DG/#Other_Setup_DG/g" ${PRODUCT_INSTALL_STATUS_FILE}
				ASK_LUN="N"
			fi

			if [ ! -s /etc/cp_server_ip ]; then
				Get_And_Validate_Input_CPS ${Cluster_Name}
			else
				source /etc/cp_server_ip >/dev/null 2>&1
				export CPS1 CPS2 CPS3
			fi

		else
			if [ "X${CONFIG_DG}" != "XNODG" ];then
				[ `${VXDISK} -o alldgs list 2>/dev/null | grep "online" | egrep "sliced|cdsdisk" | egrep -w "mmdatadg|mmdbdg|${IOFENDG}" | wc -l` -lt 5 ] && {
					clear
					${ECHO} "\n**************************************************************************"
					${ECHO} "For Cluster setup No of ${MTEXT} required = ${clusluns}"
					${ECHO} "**************************************************************************\n"
					yorn "Requisite Number of ${MTEXT} exposed to the Cluster Node(s) for DISK based I/O Fencing ? (y/n) : "
					ASK_LUN="Y"
					export oDGS_single="${DATADG} ${IOFENDG}"
				}
			else
				${VXDISK} -o alldgs list | grep cdsdisk | grep -w ${IOFENDG} >/dev/null 2>&1
				if [ $? -ne 0 ]; then 
					clear
					${ECHO} "\n**************************************************************************"
					${ECHO} "For Basic Cluster setup (IO Fencing) No of ${MTEXT} required = 3"
					${ECHO} "**************************************************************************\n"
					yorn "Requisite Number of ${MTEXT} exposed to the Cluster Node(s) for DISK based I/O Fencing ? (y/n) : "
					ASK_LUN="Y"
					export oDGS_single="${IOFENDG}"
				fi
			fi
		fi
	;;
	esac
;;	
STDALONE)

	if [ "X${CONFIG_DG}" != "XNODG" ];then
		case ${FSTYPE} in
		VRTS)
			if [ `${VXDISK} -o alldgs list 2>/dev/null | egrep "sliced|online"| egrep -w "mmdatadg|mmdbdg" | wc -l` -lt 2 ]; then
				clear
				${ECHO} "\n**************************************************************************"
				${ECHO} "For Standalone setup No of ${MTEXT} required = ${stdluns}"
				${ECHO} "**************************************************************************\n"
				yorn "Requisite Number of ${MTEXT} exposed to the host - `hostname` ? (y/n) : "
				ASK_LUN="Y"
				export oDGS_single="${DATADG}"
			else
				vxdg -Cf import mmdatadg >/dev/null 2>&1
				vxdg -Cf import mmdbdg >/dev/null 2>&1
				export oDGS_single="${DATADG}"
			fi
		;;
		EXT4|XFS)
			if [ `vgs 2>/dev/null | egrep -w "mmdatavg|mmdbvg" |wc -l` -lt 2 ];then
				clear
				${ECHO} "\n**************************************************************************"
				${ECHO} "For Standalone setup No of ${MTEXT} required = ${stdluns}"
				${ECHO} "**************************************************************************\n"
				yorn "Requisite Number of ${MTEXT} exposed to the host - `hostname` ? (y/n) : "
				ASK_LUN="Y"
				export oVGS_single="${DATAVG}"
			else
				export oVGS_single="${DATAVG}"
			fi
		;;
		esac
	fi
;;

ADDNODE)
	ASK_LUN="N"
	[ "${FSTYPE}" = "VRTS" ] || [ "X${IO_FENCING_TYPE}" = "XDISK" ] && validate_addnode_luns_exposed
	if [ "X${IO_FENCING_TYPE}" = "XCPS" ]; then
		if [ ! -s /etc/cp_server_ip ]; then
			Get_And_Validate_Input_CPS ${Cluster_Name}
		else
			source /etc/cp_server_ip >/dev/null 2>&1
			export CPS1 CPS2 CPS3
		fi
	fi
;;

CPS)
	ASK_LUN="N"
;;
esac


if [ "X${IO_FENCING_TYPE}" = "XDISK" ];then

	if [ ! -s /usr/sbin/vxdisk ];then
		log "[ERROR] : For Disk based I/O fencing installation of Veritas package VRTSvxvm is required.\nPlease install this package first"
		exit 1
	fi
fi

if [ "X${ASK_LUN}" = "XY" ];then
	case ${FSTYPE} in
	VRTS|NFS)
		export FSTOCREATE=vxfs
		Get_additional_input_VxVM
		perl -pi -e "s/^#Other_Setup_DG/Other_Setup_DG/g" ${PRODUCT_INSTALL_STATUS_FILE}
		perl -pi -e "s/^Other_Setup_DG.*/Other_Setup_DG=N/g" ${PRODUCT_INSTALL_STATUS_FILE}
	;;
	EXT4|XFS)
		Get_additional_input_LVM
	;;
	esac
fi



#--------------------------------#
# Caluctaling the total steps    #
#--------------------------------#
Steps_Calculator
clear

#-------------------------------------------------#
# Installation order of different sw is controlled#
# by install_order_platform file.		  #
#-------------------------------------------------#

instctr=0
for func in `cat ${PRODUCT_INSTALL_STATUS_FILE} | grep -v "^#" | awk -F"=" '{print $1}'` 
do
	instctr=`expr ${instctr} + 1`

	if [ "`grep "^${func}" ${PRODUCT_INSTALL_STATUS_FILE} | awk -F'=' '{ print $2 }'`" = "N" ]
	then
		${func} ${instctr} ${totsteps}
	else
		${ECHO} " "
		log "=============================================================================================================="
		log " Not Applicable         Date: `date`          ** Skipping Step : ${instctr} of ${totsteps} **"
		log "=============================================================================================================="
		log "--> `grep -w ${func} ${INSTALL_ORDER_PLATFORM} | awk -F":" '{print $3}'` was already done or not required"
	fi

	if [ -f /dev/shm/reboot_immediate ]; then
		MSG_TXT1="Reboot is required to proceed further with configuration of Platform. After reboot, re-execute the same command again"
		MSG_TXT2="$0 $*"
		Highlighter "\n*** LOG FILE LOCATION : ${INSTALL_LOG_FILE}"
		Highlighter "\n*** ${MSG_TXT1}"
		Highlighter "\n\n ${MSG_TXT2}"
	
		Highlighter "\n--> A Graceful System Restart is Required for Applying the Configuration Changes"
		input="invalid"
		while  [ "$input" != "valid" ]
		do
			${ECHO} " Restart System Now ? (y/n) : \c"
			read choice
			case ${choice} in
			y|Y)
				rm -f /dev/shm/reboot_immediate >/dev/null 2>&1
				input="valid"
				Stop_Log_Platform
				restart_mm_node
				break
			;;
				n|N)
				input="valid"
				Highlighter "\n--> Please reboot the system manually before proceeding"
				Stop_Log_Platform
				exit 1 ;;
			*) continue ;;
			esac
		done
	fi
done

if [ -f /tmp/reboot_now ]; then

	if [ "${CONFIGMODE}" != "STDALONE" ];then
		MSG_TXT="Congrats! Platform Installation and Configuration on Cluster Node `hostname` has been Completed Successfully."
	else
		MSG_TXT="Congrats! Platform Installation and Configuration on Standalone server `hostname` has been Completed Successfully."
	fi
	Highlighter "\n*** LOG FILE LOCATION : ${INSTALL_LOG_FILE}"
else
	MSG_TXT="System `hostname` was Already Configured"
fi

grep -v "^#" ${PRODUCT_INSTALL_STATUS_FILE} | grep -q "=N$" >/dev/null 2>&1
[ $? -ne 0 ] && {
	Highlighter "\n[INFO] : Removing Platform Install Status File"
	rm -f ${PRODUCT_INSTALL_STATUS_FILE} >/dev/null 2>&1
}

Start_Log_Platform >/dev/null 2>&1
Highlighter "\n*** ${MSG_TXT}"

systemctl stop xprtld >/dev/null 2>&1
systemctl disable xprtld >/dev/null 2>&1


[ "X${SKIPTYPE}" = "XALL" ] && exit 0

if [ "X${CLOUD_SETUP}" = "XY" ];then
	/usr/bin/ipcalc -4c ${bonding_interface_ip_Traffic} >/dev/null 2>&1
	if [ $? -eq 0 ];then
		export REBOOT=no
		restart_mm_node
		Highlighter "\n[INFO] : Execute configure_source_route.sh present at path ${TOOL_DIR}/misc_files/ and reboot the system by following command :"
		Highlighter "\nsystemctl reboot\n"
		rm -f /tmp/reboot_now >/dev/null 2>&1
		Stop_Log_Platform
		exit 0
	fi
fi

if [ -f /tmp/reboot_now ]; then
	Highlighter "\n--> A Graceful System Restart is Required for Applying the Configuration Changes"
	choice=""
	input="invalid"
	while  [ "$input" != "valid" ]
	do
		${ECHO} " Restart System Now ? (y/n) : \c"
		read choice
		case ${choice} in
			y|Y)
				rm -f /tmp/reboot_now >/dev/null 2>&1
				input="valid"
				Stop_Log_Platform
				restart_mm_node
				break ;;
			n|N)
				input="valid"
				Stop_Log_Platform
				break ;;
			*) continue ;;
		esac
	done
fi
