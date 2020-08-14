#!/bin/ksh

#########################################################################################
# Script Name : Install_App.sh                                                                                                #
# Purpose     : This is the main tool to be used for performing Ericsson Mediation              #
#               products installation.                                                                                        #
# Platforms   : RHEL Linux                                                                                                    #
#########################################################################################

#########################################################################################
# DevOps changes:
# 2020/06/11 - eluirub - EditTemplate commented out to avoid user interaction 
#
#########################################################################################

export DEFAULT_SUDO_FILE="/etc/sudoers"
export SUDO="/usr/bin/sudo"
export ECHO="/bin/echo -e"
export CURRENT_HOST=`hostname -s`

rpm -q "cloud-init" >/dev/null 2>&1
if [ $? -eq 0 ];then
        export CLOUD_SETUP="Y"
fi

USER="`id | sed 's/).*//;s/.*(//'`"
if [ "X${USER}" != "Xroot" ];then
        echo -e  "\n[ ERROR ] : ${USER} should have root privileges to run this script\n"
        exit 1
elif [ "X${CLOUD_SETUP}" = "XY" ] && [ "X${SUDO_USER}" = "Xcloud-user" ];then
        echo -e  "\n[ ERROR ] : ${SUDO_USER} can not run this script.\n"
        exit 1
else
        if [ "X${SUDO_USER}" != "X" ];then
                SET=0
                NOPASSWD=0
                grep "^${SUDO_USER}" ${DEFAULT_SUDO_FILE} 2>/dev/null | awk -F\) '{ print $NF }' | grep -o -q ALL
                if [ $? -ne 0 ];then
                        for USER_GROUPS in `groups ${SUDO_USER} | awk -F: '{ print $NF }'`
                        do
                                grep -q "^%${USER_GROUPS}"  ${DEFAULT_SUDO_FILE}
                                if [ $? -eq 0 ];then
                                        grep "%${USER_GROUPS}" ${DEFAULT_SUDO_FILE} 2>/dev/null | awk -F\) '{ print $NF }' | grep -o -q ALL
                                        if [ $? -eq 0  ];then
                                                export SET=1
                                        fi
                                        grep "%${USER_GROUPS}" ${DEFAULT_SUDO_FILE} 2>/dev/null | awk -F\) '{ print $NF }' | grep -q NOPASSWD
                                        if [ $? -eq 0 ];then
                                                export NOPASSWD=1
                                        fi
                                        if [ ${SET} -eq 1 ] && [ ${NOPASSWD} -eq 1 ];then
                                                break
                                        fi
                                fi
                        done
                        if [ "${SET}" -eq 0 ] || [ "${NOPASSWD}" -eq 0 ];then
                                INCLUDE_DIR=`grep -w includedir ${DEFAULT_SUDO_FILE} 2>/dev/null | awk '{ print $NF }'`
                                if [ "X${INCLUDE_DIR}" != "X" ];then
                                        for files in `ls ${INCLUDE_DIR}`
                                        do
                                                grep "^${SUDO_USER}" ${INCLUDE_DIR}/${files} 2>/dev/null | awk -F\) '{ print $NF }' | grep -o -q ALL
                                                if [ $? -ne 0 ];then
                                                        for USER_GROUPS in `groups ${SUDO_USER} | awk -F: '{ print $NF }'`
                                                        do
                                                                grep -q "^%${USER_GROUPS}"  ${INCLUDE_DIR}/${files}
                                                                if [ $? -eq 0 ];then
                                                                        grep "%${USER_GROUPS}" ${INCLUDE_DIR}/${files} 2>/dev/null | awk -F\) '{ print $NF }' | grep -o -q ALL
                                                                        if [ $? -eq 0 ];then
                                                                                export SET=1
                                                                        fi
                                                                        grep "%${USER_GROUPS}" ${INCLUDE_DIR}/${files} 2>/dev/null | awk -F\) '{ print $NF }' | grep -q NOPASSWD
                                                                        if [ $? -eq 0 ];then
                                                                                export NOPASSWD=1
                                                                        fi
                                                                        if [ ${SET} -eq 1 ] && [ ${NOPASSWD} -eq 1 ];then
                                                                                break
                                                                        fi
                                                                fi
                                                        done
                                                else
                                                        export SET=1
                                                        grep "^${SUDO_USER}" ${INCLUDE_DIR}/${files} 2>/dev/null | awk -F\) '{ print $NF }' | grep -q NOPASSWD
                                                        if [ $? -eq 0 ];then
                                                                export NOPASSWD=1
                                                        fi
                                                fi
                                        done
                                fi
                        fi
                        if [ ${SET} -eq 0 ];then
                                ${ECHO} "\n[ ERROR ] : Neither ${SUDO_USER} nor ${SUDO_USER} groups :`groups ${SUDO_USER} | awk -F: '{ print $NF }'` have ALL sudo privileges\n"
                                exit 1
                        fi
                else
                        grep "^${SUDO_USER}" ${DEFAULT_SUDO_FILE} 2>/dev/null | awk -F\) '{ print $NF }' | grep -q NOPASSWD
                        if [ $? -eq 0 ];then
                                export NOPASSWD=1
                        fi
                fi
                if [ ${NOPASSWD} -eq 0 ] && [ "X${SUDO_USER}" != "Xroot" ];then
                        ${ECHO} "\n[ INFO ] : SUDO configuration file ${DEFAULT_SUDO_FILE} on current node doesnot contains NOPASSWD for ${SUDO_USER} user or group"
                fi
        fi
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
export CURRENT_USER_NAME=`printenv SUDO_USER`
[ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"
export SSH="${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
export SCP="${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/scp -q -p -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
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

pathstr="/usr/local/bin"
grep -q $pathstr /etc/profile
if [ $? -ne 0 ];then
        printf 'export PATH=${PATH}:'"$pathstr\n"  >>/etc/profile
        source /etc/profile
fi

if [ "X${SUDO_USER}" != "X" ];then
        Update_Path ${pathstr}
        Update_Path /usr/local/sbin
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
# they can be used in Functions            #
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
# Validating command line args            #
#-----------------------------------------#
/usr/bin/hostnamectl 2>/dev/null | grep "Virtualization:" >/dev/null 2>&1
[ $? -eq 0 ] && export HW_TYPE="VIRTUALIZED" || export HW_TYPE="NATIVE_HARDWARE"

##########################
#Check Cloud Environment #
##########################
/usr/sbin/dmidecode -t System | grep -w "OpenStack" >/dev/null 2>&1
[ $? -eq 0 ] && export HW_TYPE="CLOUD"

[ "X${INSTALLATION_TYPE}" != "XIMAGE" ] && Validate_Command

if [ -t 0 ];then
        if [ "X${SUDO_USER}" = "Xroot" ];then
                ${ECHO} "\n[ WARNING ] : Script is executed with ${SUDO_USER} user. It is recommended to run this scipt with user having sudo privileges (other than root)"
                while true
                do
                        ${ECHO} "\nDo you want to proceed (y/n): \c"
                        read input
                        case ${input} in
                                        n|N) exit 1
                                                ;;
                                        y|Y) break
                                                ;;
                                        *) continue ;;
                        esac
                done
        fi
fi


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
# the command line parameter.                  #
#----------------------------------------------#
if [ "X${MEDIATYPE}" != "X" ] && [ ${MEDIATYPE} = "USB" ];then
        Mount_USB
fi

#----------------------------------------------#
# This will mount the Product ISO's from NFS   #
# server, in case NFS is specified as an option#
# for installation on the command line.        #
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
# file moved to lib_common_App file       #
#-----------------------------------------#
[ "X${SKIPTYPE}" = "X" ] && SKIPTYPE="NONE"

if [ "X${CONFIGMODE}" = "XCLUSTER" ] || [ "X${CONFIGMODE}" = "XADDTOSG" ];then
        ALL_NODES=""
        export HASYS=/opt/VRTS/bin/hasys
        export CURRENT_HOST=`hostname -s`
        for node in `${HASYS} -list SysState=RUNNING 2>/dev/null | grep -vw "^${CURRENT_HOST}$"`
        do
                ALL_NODES="${ALL_NODES} $node"
        done
        export ALL_NODES

        if [ ! -d $HOME/.ssh ];then
                mkdir -p $HOME/.ssh > /dev/null 2>&1
                chmod 700 $HOME/.ssh > /dev/null 2>&1
        else
                chown -R root:root $HOME/.ssh  2>/dev/null
                chmod 700  $HOME/.ssh 2>/dev/null
                if [ -s $HOME/.ssh/id_rsa ];then
                        chmod 600 $HOME/.ssh/id_rsa  >/dev/null 2>&1
                        chmod 644 $HOME/.ssh/id_rsa.pub  >/dev/null 2>&1
                fi
        fi
        if [ ! -s $HOME/.ssh/id_rsa.pub ];then
                yes 'yes' 2>/dev/null | ssh-keygen -q -t rsa -f $HOME/.ssh/id_rsa -P '' > /dev/null 2>&1
        fi

        export CURRENT_USER_HOME_DIR=`getent passwd ${CURRENT_USER_NAME} | awk -F: '{ print $(NF-1) }'`
        export CURRENT_USER_GID=`getent passwd ${CURRENT_USER_NAME} | awk -F: '{ print $(NF-3) }'`

        if [ -d ${CURRENT_USER_HOME_DIR}/.ssh ]; then
                chown -R ${CURRENT_USER_NAME} ${CURRENT_USER_HOME_DIR}/.ssh  2>/dev/null
                chmod 700  ${CURRENT_USER_HOME_DIR}/.ssh 2>/dev/null
                if [ -s ${CURRENT_USER_HOME_DIR}/.ssh/id_rsa ];then
                        chmod 600 ${CURRENT_USER_HOME_DIR}/.ssh/id_rsa  >/dev/null 2>&1
                        chmod 600 ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys >/dev/null 2>&1
                        chmod 644 ${CURRENT_USER_HOME_DIR}/.ssh/id_rsa.pub  >/dev/null 2>&1
                fi
        else
                mkdir ${CURRENT_USER_HOME_DIR}/.ssh 2>/dev/null
                chown ${CURRENT_USER_NAME}:${CURRENT_USER_GID} ${CURRENT_USER_HOME_DIR}/.ssh  2>/dev/null
                chmod 700  ${CURRENT_USER_HOME_DIR}/.ssh 2>/dev/null
        fi

        if [ ! -s ${CURRENT_USER_HOME_DIR}/.ssh/id_rsa.pub ];then
                yes 'yes' 2>/dev/null | ${SUDO} -u ${CURRENT_USER_NAME} ssh-keygen -q -t rsa -f ${CURRENT_USER_HOME_DIR}/.ssh/id_rsa -P '' >/dev/null 2>&1
        fi

        for node in ${ALL_NODES}
        do
                /bin/ping -c 2 ${node} > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                        reTRY=0
                        while true
                        do
                                ${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh -o BatchMode=yes -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${CURRENT_USER_NAME}@${node} "hostname" >/dev/null 2>&1
                                if [ $? -eq 0 ];then
                                        break
                                else
                                        ${ECHO} "\n[ INFO ] : Seems like passwordless ssh is not established between ${CURRENT_USER_NAME}@${CURRENT_HOST} and ${CURRENT_USER_NAME}@${node}"
                                        ${ECHO} "\n[ INFO ] : Setting passwordless ssh now."
                                        if [ $reTRY -eq 5 ];then
                                                ${ECHO} "\nFailed to enable passwordless ssh. Exiting after 5 retries...!!!\nPlease check \n\t1. if ${CURRENT_USER_NAME} exists and login is enabled\n\t2. Correct password is provided" && exit 1
                                        fi
                                        if [ $reTRY -eq 1 ];then
                                                ${ECHO} "\n[ INFO ] : Ensure below directory/files permissions and ownership for setting passwordless ssh on all nodes. Ignore if files doesnot exist.\n"
                                                ${ECHO} "ls -ld /home : drwxr-xr-x."
                                                ${ECHO} "ls -ld ${CURRENT_USER_HOME_DIR} : drwx------."
                                                ${ECHO} "ls -ld ${CURRENT_USER_HOME_DIR}/.ssh : drwx------."
                                                ${ECHO} "ls -la ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys : -rw-------."
                                                ${ECHO} "ls -la ${CURRENT_USER_HOME_DIR}/.ssh/id_rsa : -rw-------."
                                                ${ECHO} "ls -la ${CURRENT_USER_HOME_DIR}/.ssh/id_rsa.pub : -rw-r--r--."
                                                ${ECHO} "chown -R ${CURRENT_USER_NAME}: ${CURRENT_USER_HOME_DIR}"
                                        fi
                                fi

                                [ "X${CURRENT_USER_NAME}" != "Xroot" ] && ${ECHO} "\n[ INFO ] : ${CURRENT_USER_NAME} user should exist on ${node} and must have ALL sudo root privileges\n"
                                ${ECHO} "Enter ${CURRENT_USER_NAME} user password for Node ${node} : "
                                [ -f /var/tmp/ssh-copy-output ] && rm -f /var/tmp/ssh-copy-output >/dev/null 2>&1
                                ${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh-copy-id -i -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${CURRENT_USER_NAME}@${node} >/var/tmp/ssh-copy-output 2>&1
                                if [ -s /var/tmp/ssh-copy-output ];then
                                        grep -q "Password change required" /var/tmp/ssh-copy-output 2>/dev/null
                                        if [ $? -eq 0 ];then
                                                ${ECHO} "\n[ ERROR ] : Password of ${CURRENT_USER_NAME} user on ${node} has expired. Login to ${node} with ${CURRENT_USER_NAME} first and change password.\n"
                                                rm -f /var/tmp/ssh-copy-output  >/dev/null 2>&1
                                                exit 1
                                        fi
                                fi
                                ${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh -o BatchMode=yes -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${CURRENT_USER_NAME}@${node} "hostname" >/dev/null 2>&1
                                if [ $? -ne 0 ];then
                                        ${ECHO} "\n[ ERROR ] : Failed to setup passwordless ssh with ${CURRENT_USER_NAME}@${node}"
                                        ((reTRY++))
                                        continue
                                else
                                        ${ECHO} "\nPasswordless ssh is successfully configured with ${CURRENT_USER_NAME}@${node}"
                                        break
                                fi
                        done

                        ${SSH} ${CURRENT_USER_NAME}@${node} "${SUDO} -nv" >/dev/null 2>&1
                        if [ $? -ne 0 ];then
                                ${ECHO} "\n[ ERROR ] : ${CURRENT_USER_NAME} does not have sudo privileges on ${node}"
                                ${ECHO} "OR"
                                ${ECHO} "[ INFO ] : Ensure NOPASSWD entry in ${DEFAULT_SUDO_FILE} file on ${node}\n"
                                exit 1
                        fi
                        [ -f /var/tmp/sudo_permissions ] && rm -f /var/tmp/sudo_permissions >/dev/null 2>&1
                        ${SSH} ${CURRENT_USER_NAME}@${node} "${SUDO} -l" >>/var/tmp/sudo_permissions
                        if [ $? -eq 0 ];then
                                SET=0
                                PERM=$(grep -E '\(.*\)' /var/tmp/sudo_permissions | awk -F\) '{ print $NF }')
                                for value in ${PERM}
                                do
                                        echo ${value} | grep -qo ALL
                                        if [ $? -eq 0 ];then
                                                SET=1
                                        fi
                                done
                                if [ ${SET} -eq 0 ];then
                                        ${ECHO} "\n[ ERROR ] : User ${CURRENT_USER_NAME} does not have ALL sudo root privileges on ${node}"
                                        exit 1
                                fi
                        fi
                fi
        done

        if [ ! -f ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys ];then
                touch ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys >/dev/null 2>&1
                chmod 600 ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys >/dev/null 2>&1
                chown ${CURRENT_USER_NAME}:${CURRENT_USER_GID} ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys >/dev/null 2>&1
        fi

        for nodes in ${ALL_NODES}
        do
                grep -qw "${CURRENT_USER_NAME}\@${nodes}" ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys
                if [ $? -ne 0 ];then
                        [ -f /var/tmp/${CURRENT_USER_NAME}_pub_key ] && rm -f /var/tmp/${CURRENT_USER_NAME}_pub_key >/dev/null 2>&1
                        ${SSH} ${CURRENT_USER_NAME}@${nodes} "
                        if [ -d \$HOME/.ssh ]; then
                                /usr/bin/chown ${CURRENT_USER_NAME} \$HOME/.ssh
                                /usr/bin/chmod 700 \$HOME/.ssh
                                if [ -s \$HOME/.ssh/id_rsa ];then
                                        /usr/bin/chmod 600 \$HOME/.ssh/id_rsa
                                        /usr/bin/chmod 644 \$HOME/.ssh/id_rsa.pub
                                fi
                        else
                                /usr/bin/mkdir \$HOME/.ssh
                                /usr/bin/chown ${CURRENT_USER_NAME} \$HOME/.ssh
                                /usr/bin/chmod 700 \$HOME/.ssh
                        fi " >/dev/null 2>&1

                        ${SSH} ${CURRENT_USER_NAME}@${nodes} "
                        remoteHOME=\`printenv HOME\`
                        ${SUDO} /usr/bin/test -s \${remoteHOME}/.ssh/id_rsa.pub
                        if [ \$? -ne 0 ]; then
                                yes 'yes' 2>/dev/null | ${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh-keygen -q -t rsa -f \${remoteHOME}/.ssh/id_rsa -P ''
                        fi
                        ${SUDO} cat \${remoteHOME}/.ssh/id_rsa.pub" >>/var/tmp/${CURRENT_USER_NAME}_pub_key
                        if [ -s /var/tmp/${CURRENT_USER_NAME}_pub_key ];then
                                cat /var/tmp/${CURRENT_USER_NAME}_pub_key >> ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys
                                rm -f  /var/tmp/${CURRENT_USER_NAME}_pub_key >/dev/null 2>&1
                        fi
                fi
        done
fi

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
        # Different template will be generated for Prodtype        #
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
        # Opening Template for Editing and Validating              #
        #----------------------------------------------------------#
        #[ "X${SKIPTYPE}" != "XALL" ] && Edittemplate ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
		[ "X${SKIPTYPE}" != "XALL" ] && echo "not openning template"


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
                #[ "X${SKIPTYPE}" != "XALL" ] && Edittemplate ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE}
				[ "X${SKIPTYPE}" != "XALL" ] && echo "not openning template"
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
# by install_order file.                          #
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
#       find / -path /proc -prune -o -path /sys -prune -o -type f -perm -0002 -printf "%p\n" | xargs chmod o-w >/dev/null 2>&1
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
