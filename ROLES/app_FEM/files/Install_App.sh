#!/bin/ksh

####################################################################
# Script Name : Install_App.sh					   #
# Purpose     : This is the main tool to be used for performing MM #
#	        products installation.				   #
# Platforms   : RHEL Linux					   #	
####################################################################

USER="`id | sed 's/).*//;s/.*(//'`"
if [ "${USER}" != "root" ]
then
	echo
	echo "You have to be root user to run this script."
	echo "Login as root."
	echo "Exiting....."
	exit 1
fi

echo "$@" | grep debug >/dev/null 2>&1
[ $? -eq 0 ] && {
#-------------------------------#
#Defining Debug function        #
#-------------------------------#
	export PS4="Executing -->   "
	set -x
}

export TOOL_DIR=`pwd`/`dirname $0`
chmod -R 755 ${TOOL_DIR}
export TMOUT=0
CONF_DIR=${TOOL_DIR}/conf
MISC_DIR=${TOOL_DIR}/misc_files
LIB_DIR=${TOOL_DIR}/lib/`uname -s`
SKIPTYPE=NONE
#-------------------------#
# Sourcing LIB functions  #
#-------------------------#

. ${LIB_DIR}/libfunc_common_App.sh
. ${LIB_DIR}/libfunc_install_App.sh
. ${LIB_DIR}/libfunc_FEM_App.sh
. ${LIB_DIR}/libfunc_OLM_App.sh
. ${LIB_DIR}/libfunc_pg.sh

grep -q "\/usr\/local\/bin" /etc/profile
if [ $? -ne 0 ];then
	printf 'export PATH=${PATH}:'"/usr/local/bin\n"  >>/etc/profile
	source /etc/profile
fi

if [ -f ~/.bash_profile ];then
	grep -q "\/opt\/VRTSob\/bin" ~/.bash_profile
	[ $? -eq 0 ] && sed -i -e 's#:/opt/VRTSob/bin##g' ~/.bash_profile
	grep -q ':$HOME/bin' ~/.bash_profile
	[ $? -eq 0 ] && sed -i -e 's#:$HOME/bin##g' ~/.bash_profile
fi
umask 022 >/dev/null 2>&1
#
#Calling log function
#
export INSTALL_APP_LOG="/var/adm/MM_LOGS/App/MM_App.log"

#------------------------------------------------------
# MAIN LOGIC
#------------------------------------------------------
export AWK="/usr/bin/awk"
export ECHO="/bin/echo -e"
#------------------------------------------#
# Exporting command line arguments, so that# 
# they can be used in Functions		   #
#------------------------------------------#
export cmd_args="$@"

#--------------------------------------------------#
# creating /var/adm dir as it does not exist in Linux #
#--------------------------------------------------#
[ ! -f ${INSTALL_APP_LOG} ] && mkdir -p `dirname ${INSTALL_APP_LOG}` >/dev/null 2>&1

export ERROR_EXIT_LOG="/var/adm/MM_LOGS/error_exit_install.txt"
export WARN_NEXIT_LOG="/var/adm/MM_LOGS/warn_nexit_install.txt"
export SUCCESS_LOG="/var/adm/MM_LOGS/success_install.txt"

[ -f ${ERROR_EXIT_LOG} ] && rm -rf ${ERROR_EXIT_LOG}
[ -f ${WARN_NEXIT_LOG} ] && rm -rf ${WARN_NEXIT_LOG}
[ -f ${SUCCESS_LOG} ] && rm -rf ${SUCCESS_LOG}

while getopts "P:C:M:S:L:I:U:Hh" OPTION
do
	case $OPTION in
	h)
		clear
		Usage
		exit 1
		;;
	H)
		clear
		cat ${TOOL_DIR}/templates/`uname -s`/commands.readme | more 
		exit 1
		;;

	C)
		case ${OPTARG} in
		STDALONE|CLUSTER|ADDTOSG)
			export CONFIGMODE="${OPTARG}"
			;;
		*)
			Usage
			Highlighter  "[ ERROR ] - Invalid Argument Value specified with -C option"
			exit 1
			;;
		esac
		;;

	L)
		case ${OPTARG} in
		debug)
			export DEBUG_LEVEL="${OPTARG}"
			;;
		*)
			Usage
			Highlighter  "[ ERROR ] - Invalid Argument Value specified with -L option"
			exit 1
			;;
		esac
	;;

	S)
		if [ "${OPTARG}" = "precheck" ] || [ "${OPTARG}" = "ALL" ]
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
		image|IMAGE)
			export SKIPTYPE="ALL"
			export PRODTYPE=MGR
			export INSTALLATION_TYPE="IMAGE"
			;;
		*)
			Usage
			Highlighter  "[ ERROR ] - Invalid Argument Value specified with -I option"
			exit 1
			;;
		esac
	;;

	M)
		export MEDIATYPE=CDROM
		if [ ${OPTARG} = "USB" ] || [ ${OPTARG} = "NFS" ] || [ ${OPTARG} = "LOCAL" ]
		then
			export MEDIATYPE=${OPTARG}
		else
			Usage
			Highlighter  "[ ERROR ] - Invalid parameter specified with -M option."
			exit 1
		fi
	;;

	U)
		[ "X${OPTARG}" = "X" ] && {
			Usage
			Highlighter  "[ ERROR ] - Argument to -U can not be blank."
			exit 1
		}
	#-------------------------------#
	# Check for valid choices       #
	#-------------------------------#
	
	if [ "X${OPTARG}" = "XUPGRADE" ]
	then
		export ACTIVITY_TYPE=${OPTARG}
	else
		Usage
		Highlighter  "[ ERROR ] - Invalid parameter specified with -U option."
		exit 1
	fi
	;;

	P)
		case ${OPTARG} in
			FEM|OLM|MGR)
			export PRODTYPE=${OPTARG}
		;;
		
		*)
			clear
			Usage
			Highlighter "[ ERROR ] - Invalid parameter ${OPTARG} specified with -P option."
			exit 1
		;;
		esac
	;;


	?)
		clear
		Usage
		${ECHO}  "\n[ ERROR ] - Invalid OPTION specified"
		exit
		;;
	esac
done

if [ "X${PRODTYPE}" = "X" ];then
	Usage
	${ECHO}  "\n[ ERROR ] - -P OPTION is not specified"
	exit
fi

#-----------------------------------------#
# Validating command line args		  #
#-----------------------------------------#
/usr/bin/hostnamectl 2>/dev/null | grep "Virtualization:" >/dev/null 2>&1
[ $? -eq 0 ] && export HW_TYPE="VIRTUALIZED" || export HW_TYPE="NATIVE_HARDWARE"

##########################
#Check Cloud Environment #
##########################
/usr/sbin/dmidecode -t System | grep -w "OpenStack" >/dev/null 2>&1
[ $? -eq 0 ] && export HW_TYPE="CLOUD"

[ "X${INSTALLATION_TYPE}" != "XIMAGE" ] && Validate_Command


. ${CONF_DIR}/`uname -s`/definations_App.sh
. ${LIB_DIR}/libfunc_${PRODTYPE}_App.sh

export PATH=${PATH}:/usr/sbin:/usr/bin:/usr/local/bin:/etc/vx/bin:/opt/VRTSvcs/bin:/opt/VRTSllt:/opt/VRTS/bin

#----------------------------------------------#
# Setting Mediatype as CDROM in case of blank  #
#----------------------------------------------#
[ -z ${MEDIATYPE} ] && export MEDIATYPE=CDROM

#----------------------------------------------#
# This will mount the Product ISO's in case USB#
# is specified as an option for installation on#
# the command line parameter.		       #
#----------------------------------------------#
if [ "X${MEDIATYPE}" != "X" ] && [ ${MEDIATYPE} = "USB" ];then
 	Mount_USB
fi
 
#----------------------------------------------#
# This will mount the Product ISO's from NFS   #
# server, in case NFS is specified as an option#
# for installation on the command line.	       #
#----------------------------------------------#
if [ "X${MEDIATYPE}" != "X" ] && [ ${MEDIATYPE} = "NFS" ];then
 	Mount_NFS
fi

#----------------------------------------------#
# This will mount the Product ISO's from Local #
# Path, in case LOCAL is specified as an option#
# for installation on the command line.        #
#----------------------------------------------#
if [ "X${MEDIATYPE}" != "X" ] && [ ${MEDIATYPE} = "LOCAL" ];then
	Mount_Local
fi


#-----------------------------------------#
# All code for genrating MM_INSTALL_STATUS#
# file moved to lib_common_App file	  #
#-----------------------------------------#
[ "X${SKIPTYPE}" = "X" ] && SKIPTYPE="NONE"

[ "X${SKIPTYPE}" = "XNONE" ] && prereq_App

if [ "X${INSTALLATION_TYPE}" = "XIMAGE" ];then
	export CONFIGMODE=STDALONE
	PRODUCT_INSTALL_STATUS_FILE=/var/tmp/app_sw_install

	rm -f ${PRODUCT_INSTALL_STATUS_FILE}
	for funcname in `cat ${CONFIG_TEMPLATE_SRC_PATH}/install_order_App | grep -v "^#" | grep "1" | awk -F":" '{print $2}'`
	do
		${ECHO} "${funcname}=N" >> ${PRODUCT_INSTALL_STATUS_FILE}
	done

	Steps_Calculator
	instctr=0
	for func in `cat ${PRODUCT_INSTALL_STATUS_FILE} | grep -v "^#" | awk -F"=" '{print $1}'` 
	do
		instctr=`expr ${instctr} + 1`

		if [ "X`grep "^${func}" ${PRODUCT_INSTALL_STATUS_FILE} | awk -F'=' '{ print $2 }'`" = "XN" ]
		then
			${func} ${instctr} ${totsteps}
		fi
	done

	rm -f ${PRODUCT_INSTALL_STATUS_FILE}
	exit 0
else
	Generate_Status_File
fi

if [ "${CONFIGMODE}" != "ADDTOSG" ];then
	#----------------------------------------------------------#
	# Different template will be generated for Prodtype	   #
	#----------------------------------------------------------#
	if [ ! -s ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} ]
	then
		cp -rp ${CONFIG_TEMPLATE_SRC_PATH}/config_template_${PRODTYPE}.eric ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
		export UPDATE_TEMPLATE="Y"
	fi
fi

MYHOST=`hostname -s`
MYHOST_IP=$(/usr/bin/gethostip -d `hostname -s` 2>/dev/null)
if [ -s ${MM_CONFIG_FILE} ]; then
	MGRDBPORT=`sed -n "/^\[Database\ mgrdb\]/,/^\[/s/^[^[]/&/p" ${MM_CONFIG_FILE} | grep -v "#" | grep "PGDBPORT=" | awk -F"=" '{print $2}'`
fi

if [ "X${CONFIGMODE}" = "XCLUSTER" ];then

	ONM_NIC=`${HARES} -list | grep ONM | awk '{print $1}' | sort -u | head -1`
	[ "X${ONM_NIC}" != "X" ] && NETMASK=`${HARES} -value ${ONM_NIC} NetMask`

	[ "X${NETMASK}" != "X" ] && {
		sed -e "/_Netmask=/ s/^#//g; s/_Netmask=.*/_Netmask=\"${NETMASK}\"/g" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} > ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}.1
		mv -f ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}.1 ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
	}

	if [ "X${PRODTYPE}" != "XMGR" ];then 
		MGR_IP_RESOURCE=`${HARES} -list Type=IPMultiNIC MultiNICAResName=MM_ONM_NIC Group=${MANAGER_SG} | head -1 | awk '{print $1}'`

		[ "X${MGR_IP_RESOURCE}" != "X" ] && MANAGER_IP=`${HARES} -value ${MGR_IP_RESOURCE} Address`
		[ "X${MANAGER_IP}" != "X" ] && perl -pi -e "s/Manager_IP=.*/Manager_IP=\"${MANAGER_IP}\"/" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
		[ "X${MGRDBPORT}" != "X" ] && perl -pi -e "s/MANAGER_PG_DB_Port=.*/MANAGER_PG_DB_Port=\"${MGRDBPORT}\"/" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
	fi

	[ "X${PRODTYPE}" = "XOLM" ] && perl -pi -e "s/^#OLMTracer_IP=/OLMTracer_IP=/" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}

	#----------------------------------------------------------#
	# Opening Template for Editing and Validating		   #
	#----------------------------------------------------------#
	[ "X${SKIPTYPE}" != "XALL" ] && echo "No template open"


elif [ "X${CONFIGMODE}" = "XSTDALONE" ];then

	[ "X${UPDATE_TEMPLATE}" = "XY" ] && {
		sed -e "s/LIC_IP=.*/LIC_IP=\"${MYHOST_IP}\"/g" \
		-e "s/Manager_IP=.*/Manager_IP=\"${MYHOST_IP}\"/g" \
		-e "s/FMServer_IP=.*/FMServer_IP=\"${MYHOST_IP}\"/g" \
		-e "s/OLMServer_IP=.*/OLMServer_IP=\"${MYHOST_IP}\"/g" \
		-e "s/VIP/IP/g" \
		${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} > ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}.1
		mv -f ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}.1 ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
		
		if [ "X${PRODTYPE}" != "XMGR" ];then 
			[ "X${MGRDBPORT}" != "X" ] && perl -pi -e "s/MANAGER_PG_DB_Port=.*/MANAGER_PG_DB_Port=\"${MGRDBPORT}\"/" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
		fi
	}

	if [ "X${INSTALLATION_TYPE}" = "XDEFAULT" ]; then
		perl -pi -e "s/<password>/thule/g" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
	else
		[ "X${SKIPTYPE}" != "XALL" ] && Edittemplate ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
	fi
fi



if [ "${CONFIGMODE}" != "ADDTOSG" ]; then
	cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep -v "^#" | grep '=.*<.*>' >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		Error "\n\n Configuration Template validation failed !!! Following parameter is not defined properly"
		grep -v "^#" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep '=.*<.*>'
		exit 1
	fi

	Validate_Config_Template_${PRODTYPE}
fi

[ "X$loggingStarted" = "X" ] && {
	clear
	# Calling log here just to avoid junk char issue in log file
	Start_Log
	# Calling log crrection function to remove junk chars
	trap "Log_Correction" EXIT  # Set trap in case of premature exit
}

#--------------------------------#
# Caluctaling the total steps    #
#--------------------------------#
Steps_Calculator

#-------------------------------------------------#
# Installation order of different sw is controlled#
# by install_order file.			  #
#-------------------------------------------------#
already_executed=0
instctr=0
for func in `cat ${PRODUCT_INSTALL_STATUS_FILE} | grep -v "^#" | awk -F"=" '{print $1}'` 
do
	instctr=`expr ${instctr} + 1`

	if [ `grep "^${func}" ${PRODUCT_INSTALL_STATUS_FILE} | awk -F'=' '{ print $2 }'` = "N" ]
	then
		${func} ${instctr} ${totsteps}
	else
		${ECHO} " "
		${ECHO} "======================================================================================================================="
		${ECHO} " Not Applicable         Date: `date`          ** Skipping Step : ${instctr} of ${totsteps} **"
		${ECHO} "======================================================================================================================="
		${ECHO} "--> `grep ${func} ${CONFIG_TEMPLATE_SRC_PATH}/install_order_App ${CONFIG_TEMPLATE_SRC_PATH}/config_order_App.${PRODTYPE} | awk -F":" '{print $NF}'` was already done or not required"
		already_executed=1
	fi
done

#if [ "${CONFIGMODE}" != "ADDTOSG" ];then
#	find / -path /proc -prune -o -path /sys -prune -o -type f -perm -0002 -printf "%p\n" | xargs chmod o-w >/dev/null 2>&1
#fi

## CIS-CAT : To Ensure sticky bit is set on all world-writable directories
timeout 150 df --local -P 2>/dev/null | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -type d -perm -0002 2>/dev/null | xargs chmod a+t >/dev/null 2>&1

trap - EXIT


if [ "X${INSTALLATION_TYPE}" = "XDEFAULT" ]; then
	[ $already_executed -eq 0 ] && {
		Highlighter "\n[ INFO ] : All the Database User's password has been set to \"thule\""
		${ECHO} "\t The database password can be changed using MM_UTILITY"
	}
fi

if [ "${PRODTYPE}"X = "X" ];then
	${ECHO} "-----------------------------------------------------------------------------"
	${ECHO} "\nPlease find the log file at : ${INSTALL_APP_LOG}\n" | tee -a ${INSTALL_APP_LOG}
	${ECHO} "-----------------------------------------------------------------------------"
else
	Stop_Log
	Log_Correction
fi
