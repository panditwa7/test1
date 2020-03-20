#!/bin/ksh

#-------------------------------#
# This function will create VCS #
# response file.                #
#-------------------------------#
create_vcs_respfile()
{

        ### Reading Cluster section
        log "\n--> Generating response file"
        sed -n "/^\[.*\<Cluster\>\]/,/^\[/s/^[^[]/&/p" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} > /var/tmp/cluster_vcs.ini
        source /var/tmp/cluster_vcs.ini
        rm -f /var/tmp/cluster_vcs.ini
        sed -e "s/<HOSTNAME>/`hostname`/g" \
        -e "s/<CLUSTERNAME>/`hostname`-cps/g" \
        -e "s/<VRTS_PROD_TYPE>/${VRTS_PROD_TYPE}/g" \
        -e "s/<VER>/${VER}/g" \
        ${VCS_Template_File}.eric > ${VCS_Template_File}

        if [ ! -f ${VCS_Template_File} ]; then
                log " [ERROR] : Could not create response file for vcs Setup. Exiting!!"
                exit 2002
        fi
}


#-------------------------------#
# This function will create CPS #
# response file.                #
#-------------------------------#
create_cps_respfile()
{

        ### Reading Cluster section
        log "\n--> Generating response file"
        sed -n "/^\[.*\<Cluster\>\]/,/^\[/s/^[^[]/&/p" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} > /var/tmp/cluster_cps.ini
        source /var/tmp/cluster_cps.ini
        rm -f /var/tmp/cluster_cps.ini

        sed -e "s/<HOSTNAME>/`hostname`/g" \
        -e "s/<CLUSTERNAME>/`hostname`-cps/g" \
        -e "s/<VIRTUALIP>/${cps_virtual_IP}/g" \
        -e "s/<OTHERHOST>/${other_hosts_ONM}/g" \
        -e "s/<VRTS_PROD_TYPE>/${VRTS_PROD_TYPE}/g" \
        ${CPS_Template_File}.eric > ${CPS_Template_File}

        netmask_CPS=`grep "^netmask_ONM=" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | awk -F = '{print $2}'`
        sed -i "s/<NETMASK>/${netmask_CPS}/g" ${CPS_Template_File}

        if [ ! -f ${CPS_Template_File} ]; then
                log " [ERROR] : Could not create response file for vcs Setup. Exiting!!"
                exit 2002
        fi
}

#------------------------------------#
# This Function will configure CPS   #
# taking responsile as an input      #
#------------------------------------#
Configure_VCS_cps()
{
        Func_Header "Configure VCS" ${1} ${2}

        getent passwd root | awk -F: '{ print $NF }' | grep -q nologin
        if [ $? -eq 0  ];then
                usermod -s /bin/bash root >/dev/null 2>&1
        fi

        ${HASYS} -state 2>/dev/null | grep RUNNING | grep `hostname` >/dev/null 2>&1
        [ $? -ne 0 ] && {
                ## Call response file function
                create_vcs_respfile

                if [ -s ${VCS_Template_File} ];then
                        log "\n--> Please wait while VCS configuration is started"
                        [ -s /var/tmp/Platform_LOGS.txt ] && rm -f /var/tmp/Platform_LOGS.txt > /dev/null 2>&1

                        (set -o pipefail && ${INSTALLVCS} -responsefile ${VCS_Template_File} -noipc | tee /var/tmp/Platform_LOGS.txt)
                        if [ $? -ne 0 ];then
                                ${ECHO} "\n[ERROR] : Configuration for CPS failed. Refer the log for more details"
                                sed -i "/V-9-40-6798/d" /var/tmp/Platform_LOGS.txt
                                exit 1
                        else
                                sed -i "/V-9-40-6798/d" /var/tmp/Platform_LOGS.txt
                        fi
                fi
        }

        [ -s /var/tmp/Platform_LOGS.txt ] && rm -f /var/tmp/Platform_LOGS.txt > /dev/null 2>&1

        count=0
        while [ 1 ]; do
                ${HASYS} -state 2>/dev/null | grep RUNNING | grep `hostname` >/dev/null 2>&1
                if [ $? -ne 0 ]; then
                        if [ "${count}" -gt 60 ]; then
                                log "\n\n CPS Cluster Daemon is not ONLINE on node ${node}."
                                log "\n Configuration for <CPS Single node Cluster> FAILED."

                                exit 1
                        else
                                count=`expr ${count} + 1`
                                sleep 1
                        fi
                else
                        break
                fi
        done

        flog "Please check the configuration logs under : /opt/VRTS/install/logs/`ls -tr /opt/VRTS/install/logs | tail -1` directory."
        update_status "Configure_VCS_cps=Y"
}

#------------------------------------#
# This Function will configure VCS   #
# taking responsile as an input      #
#------------------------------------#
Configure_cps()
{
        Func_Header "Configuring Co-Ordination Point Server" ${1} ${2}

        ${HAGRP} -state 2>/dev/null  | grep "CPSSG.*ONLINE" >/dev/null 2>&1
        [ $? -ne 0 ] && {
                ## Call response file function
                create_cps_respfile

                if [ -s ${CPS_Template_File} ];then
                        log "\n--> Please wait while CPS configuration is started"
                        [ -s /var/tmp/Platform_LOGS.txt ] && rm -f /var/tmp/Platform_LOGS.txt > /dev/null 2>&1

                        (set -o pipefail && ${INSTALLVCS} -responsefile ${CPS_Template_File} -noipc | tee /var/tmp/Platform_LOGS.txt)
                        if [ $? -ne 0 ];then
                                ${ECHO} "\n[ERROR] : Configuration for CPS failed. Refer the log for more details"
                                sed -i "/V-9-40-6798/d" /var/tmp/Platform_LOGS.txt
                                exit 1
                        else
                                sed -i "/V-9-40-6798/d" /var/tmp/Platform_LOGS.txt
                        fi
                fi
        }

        count=0
        while [ 1 ]; do
                ${HAGRP} -state 2>/dev/null | grep CPSSG >/dev/null 2>&1
                if [ $? -ne 0 ]; then
                   if [ "${count}" -gt 60 ]; then
                        log "\n\n CPSSG Service group is not ONLINE on node ${node}.\n Make sure that CPSSG Service Group is up on ${node}."
                        log "\n Configuration for <CPS Cluster> failed."

                        exit 1
                  else
                        count=`expr ${count} + 1`
                        sleep 1
                  fi
                else
                        break
                fi
        done

        Stop_telemetry_service_veritas

        touch -f /tmp/reboot_now

        update_status "Configure_cps=Y"

}

#-----------------------------------#
# Function to validate CFS template #
#-----------------------------------#
Validate_CPS_Template()
{

        DGW_IP=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^default_gateway_ip_ONM=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
        OTH_HOST_ONM=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^other_hosts_ONM=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
        BONDING_IP_ONM=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^bonding_interface_ip_ONM=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
        HTTPS_VIRTUAL_IP=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^cps_virtual_IP=" | awk -F"=" '{print $NF}' | sed 's/"//g'`

        if [ "X${DGW_IP}" = "X${OTH_HOST_ONM}" ]; then
                ${ECHO} "\n [ ERROR ] : IP Address for default_gateway_ip_ONM and other_hosts_ONM parameters can not be same. Please check .."
                exit 1
        fi

        if [ "X${BONDING_IP_ONM}" = "X${OTH_HOST_ONM}" ]; then
                ${ECHO} "\n [ ERROR ] : IP Address for bonding_interface_ip_ONM and other_hosts_ONM parameters can not be same. Please check .."
                exit 1
        fi

        /bin/ping -c 2 ${OTH_HOST_ONM} > /dev/null 2>&1
        if [ $? -ne 0 ];then
                /bin/ping -c 2 ${DGW_IP} > /dev/null 2>&1
                if [ $? -ne 0 ]; then
                        ${ECHO} "\n [ ERROR ] : IP Address ${OTH_HOST_ONM} is not reachable.\n\t     Make sure the IP Address specified for other_hosts_ONM parameter is pingable from the system. Please check .."
                        exit 1
                else
                        ${ECHO} "\n [ WARNING ] : IP Address ${OTH_HOST_ONM} is not reachable. Assuming that the ONM Other Host is shutdown or will be configured later"
                        export other_host_exception="y"
                        sleep 3
                fi
        fi

        /bin/ping -c 2 ${HTTPS_VIRTUAL_IP} > /dev/null 2>&1
        if [ $? -eq 0 ];then
                 log "\n [ INFO ] IP : ${HTTPS_VIRTUAL_IP} is reachable. Assuming, already being used by another host assign another free IP"
                 exit 1
        fi
}

##################################################################
# Function to validate the IP entered for CPS servers            #
##################################################################
validate_cps_vip()
{
        cp_vip=$1
        if [ "X${CONFIGMODE}" = "X" ];then
                export CONFIGMODE="NOTSET"
        fi
        export CURRENT_USER_NAME=`printenv SUDO_USER`
        [ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"

        ${ECHO} "\nChecking connectivity and health of CP Server ${cp_vip}"
        touch /var/tmp/all_cps
        grep -q "\@${cp_vip}$" /var/tmp/all_cps
        if [ $? -eq 0 ];then
                Error "IP ${cp_vip} was already provided"
                return 1
        fi

        regex="^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|1?[0-9][0-9]?)$"
        #--------------------------------#
        # Validations on Input Value     #
        #--------------------------------#
        if [ X"${cp_vip}" = "X" ];then
                Error "Can not be left empty"
                return 1
        fi

        ${ECHO} ${cp_vip} | egrep ${regex} > /dev/null 2>&1
        if [ $? -ne 0 ];then
                Error "Invalid Address Format : ${cp_vip}"
                return 1
        fi

        /bin/ping -c 2 ${cp_vip} > /dev/null 2>&1
        if [ $? -ne 0 ];then
                Error "IP: ${cp_vip} is not reachable. Make sure Virtual IP Address specified is reachable and CPSSG Service Group is running with same VIP."
                return 1
        fi

        ip addr | grep -w ${cp_vip} >/dev/null 2>&1
        if [ $? -eq 0 ];then
                Error "IP: ${cp_vip} is configured on Current System. CPSSG Service Group IP should not be from Current System "
                return 1
        fi

        telnet ${cp_vip} 443 </dev/null 2>/dev/null | grep -i connected >/dev/null
        if [ $? -ne 0 ];then
                Error "Unable to connect IP ${cp_vip} using CPS port 443. Make sure Virtual IP Address specified is reachable and CPSSG Service Group is running with same VIP."
                return 1
        fi

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

        export CURRENT_HOST=`hostname -s`

        ${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh -o BatchMode=yes -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${CURRENT_USER_NAME}@${cp_vip} "hostname" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
                [ "X${CURRENT_USER_NAME}" != "Xroot" ] &&  ${ECHO} "\n[ INFO ] : ${CURRENT_USER_NAME} user should exist on CPS ${cps_vip} and must have ALL sudo root privileges"
                ${ECHO} "\nEnter ${CURRENT_USER_NAME} user password of the Host where CPS Service Group IP ${cp_vip} is configured"
                [ -f /var/tmp/ssh-copy-output ] && rm -f /var/tmp/ssh-copy-output >/dev/null 2>&1
                ${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh-copy-id -i -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${CURRENT_USER_NAME}@${cp_vip} >/var/tmp/ssh-copy-output 2>&1
                if [ -s /var/tmp/ssh-copy-output ];then
                        grep -q "Password change required" /var/tmp/ssh-copy-output 2>/dev/null
                        if [ $? -eq 0 ];then
                                ${ECHO} "\n[ ERROR ] : Password of ${CURRENT_USER_NAME} user on ${cp_vip} has expired. Login to ${cp_vip} with ${CURRENT_USER_NAME} first and change password.\n"
                                rm -f /var/tmp/ssh-copy-output  >/dev/null 2>&1
                                exit 1
                        fi
                fi
                ${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh -o BatchMode=yes -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${CURRENT_USER_NAME}@${cp_vip} "hostname" >/dev/null 2>&1
                if [ $? -ne 0 ];then
                        Error "Unable to setup ssh connectivity with CPS Server. Ensure that ${CURRENT_USER_NAME} exists and has valid password, Network Connectivity or provide different Virtual IP"
                        return 1
                else
                        ${ECHO} "\nPasswordless ssh is successfully configured with ${CURRENT_USER_NAME}@${cp_vip}"
                fi
        fi

        ${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh -o BatchMode=yes -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} -nv" >/dev/null 2>&1
        if [ $? -ne 0 ];then
                Error "User ${CURRENT_USER_NAME} does not have sudo privileges on ${cp_vip}"
                ${ECHO} "OR"
                ${ECHO} "[INFO] : Ensure NOPASSWD entry in ${DEFAULT_SUDO_FILE} file on ${cp_vip}\n"
                exit 1
        fi
        [ -f /var/tmp/sudo_permissions ] && rm -f /var/tmp/sudo_permissions >/dev/null 2>&1
        ${SUDO} -u ${CURRENT_USER_NAME} /usr/bin/ssh -o BatchMode=yes -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} -l" >> /var/tmp/sudo_permissions
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
                        ${ECHO} "\n[ ERROR ] : User ${CURRENT_USER_NAME} does not have ALL sudo root privileges on ${cp_vip}"
                        exit 1
                fi
        fi

        if [ "X${CONFIGMODE}" != "XADDNODE" ];then
                [ -f /var/tmp/remote_pub_key ] && rm -f /var/tmp/remote_pub_key >/dev/null 2>&1
                [ -f /var/tmp/sshd_status ] && rm -f /var/tmp/sshd_status >/dev/null 2>&1
                [ -f /var/tmp/securetty_out ] && rm -f /var/tmp/securetty_out >/dev/null 2>&1
                [ -f /var/tmp/securetty ] && rm -f /var/tmp/securetty >/dev/null 2>&1

                /usr/bin/ssh -o BatchMode=yes -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${cp_vip} "hostname" >/dev/null 2>&1
                if [ $? -ne 0 ]; then
                        CP_PERMIT_ROOT_LOGIN=`${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO}  grep -w ^PermitRootLogin  /etc/ssh/sshd_config" |  awk '{ print $NF }'` 2>/dev/null
                        if [ "X${CP_PERMIT_ROOT_LOGIN}" = "X" ];then
                                ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} echo \"PermitRootLogin  yes\" | ${SUDO} tee -a /etc/ssh/sshd_config" >/dev/null 2>&1
                                ${ECHO} "${cp_vip}:PermitRootLogin:yes:entry" >>/var/tmp/cp_sysfiles_info
                        else
                                if [ "X${CP_PERMIT_ROOT_LOGIN}" = "Xno" ];then
                                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} sed -i -e 's@^PermitRootLogin.*@PermitRootLogin yes@g' /etc/ssh/sshd_config" 2>/dev/null
                                        ${ECHO} "${cp_vip}:PermitRootLogin:yes" >>/var/tmp/cp_sysfiles_info
                                fi
                        fi

                        grep -qw "${cp_vip}:PermitRootLogin:yes" /var/tmp/cp_sysfiles_info 2>/dev/null
                        if [ $? -eq 0 ];then
                                ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} /usr/bin/systemctl restart sshd" 2>/dev/null
                                sleep 5
                                ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} /usr/bin/systemctl status sshd" >>/var/tmp/sshd_status
                                grep -q "Active: active" /var/tmp/sshd_status
                                if [ $? -ne 0 ];then
                                        ${ECHO} "\n[ ERROR ] : sshd service is not running/active on ${cp_vip}"
                                        exit 1
                                fi
                        fi

                        [ -f /var/tmp/misc_securetty ] && rm -f /var/tmp/misc_securetty >/dev/null 2>&1
                        tar -cf /var/tmp/misc_securetty.tar -C ${MISC_DIR}/ securetty >/dev/null 2>&1
                        chmod o+r /var/tmp/misc_securetty.tar >/dev/null 2>&1
                        ${SCP} /var/tmp/misc_securetty.tar ${CURRENT_USER_NAME}@${cp_vip}:/var/tmp/ >/dev/null 2>&1

                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "
                        ${SUDO} /usr/bin/test -f /var/tmp/cp_sysfiles_info
                        if [ \$? -eq 0 ];then
                                ${SUDO} /usr/bin/rm -f /var/tmp/cp_sysfiles_info
                        fi
                        ${SUDO} /usr/bin/wc -w /etc/securetty | grep -q '^0'
                        if [ \$? -eq 0 ];then
                                ${SUDO} /usr/bin/test -s /etc/.securetty
                                if [ \$? -eq 0 ];then
                                        ${SUDO} /usr/bin/mv -f /etc/.securetty /etc/securetty
                                else
                                        ${SUDO} /usr/bin/tar -xf /var/tmp/misc_securetty.tar -C /etc/
                                fi
                                ${SUDO} ${ECHO} \"${cp_vip}:securetty:moved\" | ${SUDO} /usr/bin/tee -a /var/tmp/cp_sysfiles_info >/dev/null 2>&1
                        fi
                        ${SUDO} /usr/bin/test -s /var/tmp/cp_sysfiles_info
                        if [ \$? -eq 0 ];then
                                ${SUDO} /usr/bin/cat /var/tmp/cp_sysfiles_info
                        fi" >> /var/tmp/securetty_out

                        [ -s /var/tmp/securetty_out ] && cat /var/tmp/securetty_out >> /var/tmp/cp_sysfiles_info

                        CP_ROOT_SHELL=`${SSH} ${CURRENT_USER_NAME}@${cp_vip} " /usr/bin/getent passwd root | awk -F: '{ print $NF }'"`
                        echo ${CP_ROOT_SHELL} 2>/dev/null | grep -q nologin
                        if [ $? -eq 0 ];then
                                ${SSH} ${CURRENT_USER_NAME}@${cp_vip}  "${SUDO} /usr/sbin/usermod -s /bin/bash root" 2>/dev/null
                        fi

                        LOCAL_ROOT_PUB_KEY_COMPLETE=`cat ${HOME}/.ssh/id_rsa.pub`
                        LOCAL_ROOT_PUB_KEY=`echo ${LOCAL_ROOT_PUB_KEY_COMPLETE} | awk '{ print $2 }'`
                        CURRENT_HOSTNAME=`hostname -s`
                        KEY_EXIST=N
                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} /usr/bin/grep -w "root@${CURRENT_HOSTNAME}" \`sudo printenv HOME\`/.ssh/authorized_keys " >> /var/tmp/remote_pub_key 2>/dev/null

                        for KEY in `cat /var/tmp/remote_pub_key | awk '{ print $2 }'`
                        do
                                if [ "X${KEY}" = "X${LOCAL_ROOT_PUB_KEY}" ];then
                                        KEY_EXIST=Y
                                fi
                        done

                        if [ "X${KEY_EXIST}" = "XN" ];then
                                ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "
                                remoteHOME=\`${SUDO} printenv HOME\`
                                ${SUDO} /usr/bin/test -d \${remoteHOME}/.ssh/
                                if [ \$? -ne 0 ]; then
                                        ${SUDO} /usr/bin/mkdir -p \${remoteHOME}/.ssh/
                                        ${SUDO} /usr/bin/chown -R root:root \${remoteHOME}/.ssh/
                                        ${SUDO} /usr/bin/chmod 700 \${remoteHOME}/.ssh/
                                fi
                                ${SUDO} /usr/bin/test -f /root/.ssh/authorized_keys
                                if [ \$? -ne 0 ]; then
                                        ${SUDO} /usr/bin/touch \${remoteHOME}/.ssh/authorized_keys
                                        ${SUDO} /usr/bin/chmod 600 \${remoteHOME}/.ssh/authorized_keys
                                        ${SUDO} /usr/bin/chown root:root \${remoteHOME}/.ssh/authorized_keys
                                fi
                                ${SUDO} echo ${LOCAL_ROOT_PUB_KEY_COMPLETE} | ${SUDO} /usr/bin/tee -a /root/.ssh/authorized_keys >/dev/null 2>&1
                                ${SUDO} /usr/bin/chmod 600 /root/.ssh/authorized_keys" >/dev/null 2>&1
                                ${ECHO} "${cp_vip}:public_key:authorized_keys:copied" >>/var/tmp/cp_sysfiles_info
                        fi
                fi
        fi

        grep -w "${cps_vip}" ${CURRENT_USER_HOME_DIR}/.ssh/known_hosts >/dev/null 2>&1
        if [ $? -ne 0 ];then
                ssh-keyscan ${cps_vip} 2>/dev/null >> ${CURRENT_USER_HOME_DIR}/.ssh/known_hosts
                chown ${CURRENT_USER_NAME}:${CURRENT_USER_GID} ${CURRENT_USER_HOME_DIR}/.ssh/known_hosts >/dev/null 2>&1
        fi

        CURRENT_NODE_TIMEZONE=`timedatectl status 2>/dev/null | grep "Time zone:" | awk -Fzone: '{print $2}' | awk -F"(" '{print $1}' | sed "s/^\ //"`
        REMOTE_NODE_TIMEZONE=""
        REMOTE_NODE_TIMEZONE=`${SSH} ${CURRENT_USER_NAME}@${cp_vip} " /usr/bin/timedatectl status 2>/dev/null" | grep "Time zone:" | awk -Fzone: '{print $2}' | awk -F"(" '{print $1}' | sed "s/^\ //"`

        if [ "X${CURRENT_NODE_TIMEZONE}" != "X${REMOTE_NODE_TIMEZONE}" ]; then
                ${ECHO} "\n [ ERROR ] : Timezone mismatch found between Current Node and CP Server ${cp_vip}"
                ${ECHO} "\n Current Node Timezone : ${CURRENT_NODE_TIMEZONE}"
                ${ECHO} " ${cp_vip} Node Timezone : ${REMOTE_NODE_TIMEZONE}"
                ${ECHO} "\n For Cluster setup the timezone of the Cluster nodes and CP Servers should be same"
                ${ECHO} "\n Update the timezone of the respective node(s) using following command:"
                ${ECHO} "    sudo timedatectl set-timezone <correct_time_zone>"
                exit 1
        fi

        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -a ping_cps" | grep "CP\ server\ successfully\ pinged" >/dev/null 2>&1
        if [ $? -ne 0 ];then
                Error "CPSSG Service Group is not running on ${CURRENT_USER_NAME}@${cp_vip}. Make sure CPSSG Service Group is running with same VIP."
                return 1
        fi

        curr_clus_regnodes=0
        curr_clus_regnodes=`${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -a list_nodes 2>/dev/null" | grep -w "^${clustername}" | wc -l`
        if [ ${curr_clus_regnodes} -ne 0 ];then

                all_clus_nodes=""
                if [ -s /etc/llthosts ];then
                        all_clus_nodes=`cat /etc/llthosts | awk '{print $2}'`
                        all_clus_nodes=`echo ${all_clus_nodes} |sed 's/ /$|^/'`

                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a list_nodes 2>/dev/null" | grep -w "^${clustername}" | awk '{print $3}' | awk -F"(" '{print $1}' | egrep -w "^${all_clus_nodes}$" >/dev/null 2>&1
                        if [ $? -ne 0 ]; then

                                cps_clus_regnodes=0
                                cps_clus_regnodes=`${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a list_nodes 2>/dev/null" | grep -w "^${clustername}" | awk '{print $3}' | tr -cd '[a-zA-Z0-9][\012]' | wc -l`
                                if [ ${cps_clus_regnodes} -ne 0 ];then
                                        Error "Another Cluster with same Name ${clustername} is already registered on ${cp_vip}"
                                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a list_nodes 2>/dev/null" | egrep -v "Local|assuming"

                                        ${ECHO} "\nPlease use a different CP Server for I/O FENCING"
                                        return 1
                                fi
                        fi

                        i=0
                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a list_nodes 2>/dev/null" | grep -w "^${clustername}" | while read line
                        do
                                ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a unreg_node -n${i}" >/dev/null 2>&1
                                ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a rm_node -n${i}" >/dev/null 2>&1
                                i=`expr $i + 1`
                        done
                else
                        cps_clus_regnodes=0
                        cps_clus_regnodes=`${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a list_nodes 2>/dev/null" | grep -w "^${clustername}" | awk '{print $3}' | grep -v "^${CURRENT_HOST}("| tr -cd '[a-zA-Z0-9][\012]' | wc -l`
                        if [ ${cps_clus_regnodes} -ne 0 ];then
                                Error "Another Cluster with same Name ${clustername} is already registered on ${cp_vip}"
                                ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a list_nodes 2>/dev/null" | egrep -v "Local|assuming"

                                ${ECHO} "\nPlease use a different CP Server for I/O FENCING"
                                ${ECHO} "  -- OR --"
                                ${ECHO} "Change the Cluster_Name parameter value defined in template. Terminate the script by pressing Ctrl+c and then re-run the script"
                                return 1
                        else
                                i=0
                                ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a list_nodes 2>/dev/null" | grep -w "^${clustername}" | while read line
                                do
                                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a unreg_node -n${i}" >/dev/null 2>&1
                                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -c ${clustername} -a rm_node -n${i}" >/dev/null 2>&1
                                        i=`expr $i + 1`
                                done
                        fi

                fi

        fi

        CP_CLUS_NODE=`${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} ${CPSADM} -s ${cp_vip} -a list_nodes 2>/dev/null" | egrep -vw "assuming|CP|ClusterName|WARNING|=|^${clustername}" | grep -v "^$" | wc -l`
        if [ ${CP_CLUS_NODE} -eq 0 ]; then

                ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} /usr/bin/ntpstat 2>/dev/null" | grep -q "^synchronised"
                if [ $? -eq 0 ];then
                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "
                        ${SUDO} /usr/bin/timedatectl set-ntp no
                        ${SUDO} /usr/bin/systemctl restart ntpd.service
                        sleep 2
                        ${SUDO} exit" >/dev/null 2>&1

                        my_date=`timedatectl | grep "Local time:" | cut -d":" -f2- | tr -d '[a-zA-Z]'`
                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "
                        ${SUDO} /usr/bin/timedatectl set-time \"${my_date}\"
                        ${SUDO} /usr/sbin/hwclock --systohc
                        exit" >/dev/null 2>&1
                else
                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "${SUDO} /usr/bin/timedatectl set-ntp no" >/dev/null 2>&1
                        my_date=`timedatectl | grep "Local time:" | cut -d":" -f2- | tr -d '[a-zA-Z]'`
                        ${SSH} ${CURRENT_USER_NAME}@${cp_vip} "
                        ${SUDO} /usr/bin/timedatectl set-time \"${my_date}\"
                        ${SUDO} /usr/bin/hwclock --systohc" >/dev/null 2>&1
                fi
        fi

        return 0
}

##################################################################
# Function to gather/fetch the IP entered for CPS servers        #
##################################################################
Get_And_Validate_Input_CPS() {
        export CURRENT_HOST=`hostname -s`
        export CURRENT_HOSTIP=$(/usr/bin/gethostip -d `hostname -s` 2>/dev/null)

        export clustername=$1
        [ "X${clustername}" = "X" ] && clustername=NA
        export clustername

        [ -f /var/tmp/cp_sysfiles_info ] && rm -f /var/tmp/cp_sysfiles_info >/dev/null 2>&1

        if [ -s /etc/cp_server_ip ];then
                chmod 755 /etc/cp_server_ip >/dev/null 2>&1
                rm -f /var/tmp/all_cps >/dev/null 2>&1
                for cp_server_ip in `cat /etc/cp_server_ip | awk -F= '{ print $2 }'`
                do
                        validate_cps_vip  ${cp_server_ip}
                        if [ $? -ne 0 ];then
                                exit 1
                        fi
                done
                cp -f /etc/cp_server_ip /var/tmp/all_cps >/dev/null 2>&1
        else
                ${ECHO} "\n*** Virtual IP selection for CPS Based I/O Fencing ***\n"
                [ -s /var/tmp/all_cps ] && rm -f /var/tmp/all_cps >/dev/null 2>&1
				input=`find . -name cps.txt`
                for i in {1,2,3}; do
                        case $i in
                        1) cps_name_i="1st" ;;
                        2) cps_name_i="2nd" ;;
                        3) cps_name_i="3rd" ;;
                        esac

                        while true
                        do
                                ${ECHO} "\nEnter Virtual IP Address of ${cps_name_i} CP Server : \c"
                                read cps_vip

                                validate_cps_vip ${cps_vip}
                                [ $? -eq 0 ] && {
                                        eval CPS${i}=${cp_vip}
                                        echo "CPS${i}=${cp_vip}" >> /var/tmp/all_cps
                                        export CPS${i}
                                        break
                                }
                        done < "$input"
                done
        fi

        for CPS in `cat /var/tmp/all_cps | awk -F= '{ print $2 }'`
        do
                [ "X${CURRENT_NODE_AS_NTP}" = "XN" ] && check_ntp_mispatch ${CPS}
                [ "X${CONFIG_OPTION}" = "XCUSTOM" ] && check_time_mispatch ${CPS}
        done

        check_ntp_mismatch_cps

        mv -f /var/tmp/all_cps /etc/cp_server_ip >/dev/null 2>&1
        chmod 755 /etc/cp_server_ip >/dev/null 2>&1
        source /etc/cp_server_ip >/dev/null 2>&1

        for IP in ${CPS1} ${CPS2} ${CPS3}
        do
                ${SSH} ${CURRENT_USER_NAME}@${IP} "${SUDO} /usr/sbin/usermod -s /bin/bash root" >/dev/null 2>&1
        done

        [ "X${CONFIGMODE}" = "XCLUSTER" ] && {
                my_date=`${SSH} ${CURRENT_USER_NAME}@${CPS1} "/usr/bin/timedatectl 2>/dev/null" | grep "Local time:" | cut -d":" -f2- | tr -d '[a-zA-Z]'`
                timedatectl set-ntp no >/dev/null 2>&1
                timedatectl set-time "${my_date}" >/dev/null 2>&1
        }
}


#-------------------------------------------------------------------#
# Function to check what type of NTP (internal/external) configured #
# in CPS Nodes and find any mismatch                                #
#-------------------------------------------------------------------#
check_ntp_mismatch_cps()
{
        [ -s /var/tmp/check_ntp_mismatch_cps ] && rm -f /var/tmp/check_ntp_mismatch_cps
        [ -s /var/tmp/ntp_cps_info ] && rm -f /var/tmp/ntp_cps_info
        [ -s /var/tmp/ntp_cps_running ] && rm -f /var/tmp/ntp_cps_running
        [ -s /var/tmp/ntp_cps_not_running ] && rm -f /var/tmp/ntp_cps_not_running

        ${ECHO} "\nVerifying NTP configuration on CP Servers"

        cps_ntp_configured=0
        cps_ntp_not_configured=0
        ntp_service_running=0
        ntp_service_not_running=0
        for CPS_NODE in `cat /var/tmp/all_cps | awk -F= '{ print $2 }'`
        do
                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/ntpstat 2>/dev/null" | grep "^synchronised" >/dev/null 2>&1
                if [ $? -eq 0 ];then

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/cat /etc/ntp.conf" | egrep -v "[0-9].rhel.pool.ntp.org|127.127.1.0" | grep "^server" >> /var/tmp/check_ntp_mismatch_cps

                        ${ECHO} "\nNTP Service configured in ${CPS_NODE}:" >> /var/tmp/ntp_cps_info
                        ${ECHO}   "-----------------------------------------------------\n" >> /var/tmp/ntp_cps_info
                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/cat /etc/ntp.conf" | egrep -v "[0-9].rhel.pool.ntp.org|127.127.1.0" | grep "^server" >> /var/tmp/ntp_cps_info
                        if [ $? -ne 0 ];then
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/cat /etc/ntp.conf" | egrep -v "[0-9].rhel.pool.ntp.org" | grep "127.127.1.0" | grep "^server"  >> /var/tmp/ntp_cps_info
                                if [ $? -eq 0 ];then
                                        cps_ntp_configured=`expr ${cps_ntp_configured} + 1`
                                        /usr/sbin/ntpq -c "timeout 600" -pn ${CPS_NODE} 2>/dev/null | grep -iw remote >/dev/null 2>&1
                                        [ $? -eq 0 ] && {
                                                ntp_service_running=`expr ${ntp_service_running} + 1`
                                                echo "${CPS_NODE}" >> /var/tmp/ntp_cps_running
                                        } || {
                                                 ntp_service_not_running=`expr ${ntp_service_not_running} + 1`
                                                 echo "${CPS_NODE}" >> /var/tmp/ntp_cps_not_running
                                        }

                                else
                                        cps_ntp_not_configured=`expr ${cps_ntp_not_configured} + 1`
                                fi
                        else
                                cps_ntp_configured=`expr ${cps_ntp_configured} + 1`

                                /usr/sbin/ntpq -c "timeout 600" -pn ${CPS_NODE} 2>/dev/null | grep -iw remote >/dev/null 2>&1
                                [ $? -eq 0 ] && {
                                        ntp_service_running=`expr ${ntp_service_running} + 1`
                                        echo "${CPS_NODE}" >> /var/tmp/ntp_cps_running
                                } || {
                                        ntp_service_not_running=`expr ${ntp_service_not_running} + 1`
                                        echo "${CPS_NODE}" >> /var/tmp/ntp_cps_not_running
                                }
                        fi
                else

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/cat /etc/ntp.conf" | egrep -v "[0-9].rhel.pool.ntp.org" | grep "^server" >> /var/tmp/check_ntp_mismatch_cps
                        if [ $? -ne 0 ];then
                                ${ECHO} "\nNTP Service not configured in ${CPS_NODE}" >> /var/tmp/ntp_cps_info
                                ${ECHO}   "-----------------------------------------------------\n" >> /var/tmp/ntp_cps_info
                                cps_ntp_not_configured=`expr ${cps_ntp_not_configured} + 1`
                        else
                                ${ECHO} "\nNTP Service configured in ${CPS_NODE} (But NTP Service is not RUNNING):" >> /var/tmp/ntp_cps_info
                                ${ECHO} "-----------------------------------------------------\n" >> /var/tmp/ntp_cps_info
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/cat /etc/ntp.conf" | egrep -v "[0-9].rhel.pool.ntp.org" | grep "^server" >> /var/tmp/ntp_cps_info
                                cps_ntp_configured=`expr ${cps_ntp_configured} + 1`
                        fi

                        /usr/sbin/ntpq -c "timeout 600" -pn ${CPS_NODE} 2>/dev/null | grep -iw remote >/dev/null 2>&1
                        [ $? -eq 0 ] && {
                                ntp_service_running=`expr ${ntp_service_running} + 1`
                                echo "${CPS_NODE}" >> /var/tmp/ntp_cps_running
                        } || {
                                ntp_service_not_running=`expr ${ntp_service_not_running} + 1`
                                echo "${CPS_NODE}" >> /var/tmp/ntp_cps_not_running
                        }
                fi
        done

        if [ ${cps_ntp_not_configured} -ne 0 ];then
                if [ ${cps_ntp_not_configured} -ne 3 ];then
                        Error "NTP Configuration is not same in all the CP Servers"
                        ${ECHO} "Please use same NTP Configuration for all the CP Servers"
                        cat /var/tmp/ntp_cps_info
                        rm -f /var/tmp/check_ntp_mismatch_cps /var/tmp/check_ntp_mismatch_cps_test /var/tmp/ntp_cps_info /var/tmp/ntp_cps_not_running /var/tmp/ntp_cps_running >/dev/null 2>&1
                        exit 1
                fi
        fi

        if [ ${cps_ntp_configured} -ne 0 ];then
                if [ ${cps_ntp_configured} -ne 3 ];then
                        Error "NTP Configuration is not same in all the CP Servers"
                        ${ECHO} "Please use same NTP Configuration for all the CP Servers"
                        cat /var/tmp/ntp_cps_info
                        rm -f /var/tmp/check_ntp_mismatch_cps /var/tmp/check_ntp_mismatch_cps_test /var/tmp/ntp_cps_info /var/tmp/ntp_cps_not_running /var/tmp/ntp_cps_running >/dev/null 2>&1
                        exit 1

                fi
        fi

        if [ ${ntp_service_not_running} -ne 0 ];then
                if [ ${ntp_service_not_running} -ne 3 ];then
                        Error "NTP Service is not running in all the CP Servers"
                        ${ECHO} "\nCP Servers where NTP Service is running:"
                        cat /var/tmp/ntp_cps_running
                        ${ECHO} "\nCP Servers where NTP Service is not running:"
                        cat /var/tmp/ntp_cps_not_running

                        ${ECHO} "\nPlease ensure that NTP Service status should be same for all the CP Servers"
                        rm -f /var/tmp/check_ntp_mismatch_cps /var/tmp/check_ntp_mismatch_cps_test /var/tmp/ntp_cps_info /var/tmp/ntp_cps_not_running /var/tmp/ntp_cps_running >/dev/null 2>&1
                        exit 1
                fi
        fi

        if [ ${ntp_service_running} -ne 0 ];then
                if [ ${ntp_service_running} -ne 3 ];then
                        Error "NTP Service is not running in all the CP Servers"
                        ${ECHO} "\nCP Servers where NTP Service is running:"
                        cat /var/tmp/ntp_cps_running
                        ${ECHO} "\nCP Servers where NTP Service is not running:"
                        cat /var/tmp/ntp_cps_not_running

                        ${ECHO} "\nPlease ensure that NTP Service status should be same for all the CP Servers"
                        rm -f /var/tmp/check_ntp_mismatch_cps /var/tmp/check_ntp_mismatch_cps_test /var/tmp/ntp_cps_info /var/tmp/ntp_cps_not_running /var/tmp/ntp_cps_running >/dev/null 2>&1
                        exit 1
                fi
        fi


        if [ -s /var/tmp/check_ntp_mismatch_cps ];then
                sed -i "/${CURRENT_HOSTIP}/d" /var/tmp/check_ntp_mismatch_cps

                for CPS_NODE in `cat /var/tmp/all_cps | awk -F= '{ print $2 }'`
                do
                        sed -i "/${CPS_NODE}/d" /var/tmp/check_ntp_mismatch_cps
                done

                cat /var/tmp/check_ntp_mismatch_cps | sort | uniq -u > /var/tmp/check_ntp_mismatch_cps_test

                if [ -s /var/tmp/check_ntp_mismatch_cps_test ];then
                        Error "NTP Configuration is not same in all the CP Servers"
                        ${ECHO} "Please use same NTP Server IP for all the CP Servers and Cluster Nodes"
                        cat /var/tmp/ntp_cps_info
                        rm -f /var/tmp/check_ntp_mismatch_cps /var/tmp/check_ntp_mismatch_cps_test /var/tmp/ntp_cps_info /var/tmp/ntp_cps_not_running /var/tmp/ntp_cps_running >/dev/null 2>&1
                        exit 1
                fi

                rm -f /var/tmp/check_ntp_mismatch_cps /var/tmp/check_ntp_mismatch_cps_test /var/tmp/ntp_cps_info /var/tmp/ntp_cps_not_running /var/tmp/ntp_cps_running >/dev/null 2>&1
        fi

        rm -f /var/tmp/check_ntp_mismatch_cps /var/tmp/check_ntp_mismatch_cps_test /var/tmp/ntp_cps_info /var/tmp/ntp_cps_not_running /var/tmp/ntp_cps_running >/dev/null 2>&1

        if [ ${cps_ntp_configured} -eq 3 ];then

                [ -s /var/tmp/cps_time ] && rm -f /var/tmp/cps_time

                for CPS_NODE in `cat /var/tmp/all_cps | awk -F= '{ print $2 }'`
                do
                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "LC_ALL=C LANG=C /bin/date -u +%Y%m%d%H%M 2>/dev/null" >> /var/tmp/cps_time
                done

                if [ `cat /var/tmp/cps_time | sort | uniq -u | wc -l` -ne 0 ];then
                        rm -f /var/tmp/cps_time
                        sleep 1

                        for CPS_NODE in `cat /var/tmp/all_cps | awk -F= '{ print $2 }'`
                        do
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "LC_ALL=C LANG=C /bin/date -u +%Y%m%d%H%M 2>/dev/null" >> /var/tmp/cps_time
                        done

                        if [ `cat /var/tmp/cps_time | sort | uniq -u | wc -l` -ne 0 ];then
                                Error "As NTP Service is already configured all the CP Servers, hence System Time of CP Servers must be same"
                                ${ECHO} "\nPlease modify the System Time of respective CP Server(s) to have no Time Difference"
                                ${ECHO} "Current System Time of CP Servers (yyyy:mm:dd:HH:MM):"

                                for CPS_NODE in `cat /var/tmp/all_cps | awk -F= '{ print $2 }'`
                                do
                                        echo "${CPS_NODE} : "`${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "LC_ALL=C LANG=C /bin/date -u +%Y:%m:%d:%H:%M 2>/dev/null"`
                                done

                                ${ECHO} "\nFollowing commands can be used to update/sync the System time with reference (correct) System from the respective Node"
                                ${ECHO} "    sudo systemctl restart ntpd.service  (If NTP Service is configured on the respective Node)"
                                ${ECHO} "    sudo ntpdate -b -t 4 -p 4 -u <system_ip_address_having_correct_time_where_ntp_is_running>"
                                rm -f /var/tmp/cps_time
                                exit 1
                        fi
                        rm -f /var/tmp/cps_time
                fi
        fi


}

##################################################################################
# Function to check time mismatch between CPS and Cluster Node while configuring #
# CPS based Fencing in running Cluster
##################################################################################
check_time_mispatch()
{
        CPS_NODE=$1
        ${ECHO} "\n--> Checking for System Time mismatch between ${CURRENT_HOST} and ${CPS_NODE}"
        export CURRENT_USER_NAME=`printenv SUDO_USER`
        [ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"

        [ -s /var/tmp/cps_time ] && rm -f /var/tmp/cps_time
        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "LC_ALL=C LANG=C /bin/date -u +%Y%m%d%H%M 2>/dev/null" > /var/tmp/cps_time
        /bin/date -u +%Y%m%d%H%M 2>/dev/null >> /var/tmp/cps_time

        if [ `cat /var/tmp/cps_time | sort | uniq -u | wc -l` -ne 0 ];then

                sleep 1
                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "LC_ALL=C LANG=C /bin/date -u +%Y%m%d%H%M 2>/dev/null" > /var/tmp/cps_time
                /bin/date -u +%Y%m%d%H%M 2>/dev/null >> /var/tmp/cps_time

                if [ `cat /var/tmp/cps_time | sort | uniq -u | wc -l` -ne 0 ];then

                        CP_CLUS_NODE=`${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} ${CPSADM} -s ${CPS_NODE} -a list_nodes 2>/dev/null" | egrep -v "assuming|CP|ClusterName|WARNING|=|${clustername}" | grep -v "^$" | wc -l`
                        if [ ${CP_CLUS_NODE} -ne 0 ]; then
                                Error "System Time mismatch observed between Ericsson Mediation Cluster nodes and CP Server ${CPS_NODE}"
                                ${ECHO} "\n[INFO] : CP Server ${CPS_NODE} is already being used for the following:\n"
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} ${CPSADM} -s ${CPS_NODE} -a list_nodes 2>/dev/null" | egrep -v "assuming|CP|WARNING|="
                                ${ECHO} "\nSystem Time of CP Server ${CPS_NODE} (yyyy:mm:dd:HH:MM):"`${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "LC_ALL=C LANG=C /bin/date -u +%Y:%m:%d:%H:%M 2>/dev/null"`
                                ${ECHO} "System Time of ${CURRENT_HOST} (yyyy:mm:dd:HH:MM):" `/bin/date -u +%Y:%m:%d:%H:%M 2>/dev/null`
                                ${ECHO} "\nPlease modify the System Time of respective System to have no Time Difference"

                                ${ECHO} "\nFollowing commands can be used to update/sync the System time with reference (correct) System from the respective Node"
                                ${ECHO} "  sudo systemctl restart ntpd.service  (If NTP Service is configured on the respective Node)"
                                ${ECHO} "  sudo ntpdate -b -t 4 -p 4 -u <system_ip_address_having_correct_time_where_ntp_is_running>"
                                ${ECHO} "\n[NOTE] : It is not recommended to change the System time of Ericsson Mediation Application Cluster Nodes"
                                rm -f /var/tmp/cps_time
                                exit 1
                        fi
                fi
        fi

        rm -f /var/tmp/cps_time
}

#########################################################################
# Function to check NTP Server IP mismatch between CPS and Cluster Node #
#########################################################################
check_ntp_mispatch()
{

        ${ECHO} "\n--> Checking for NTP configuration in CP Server ${CPS_NODE}"
        CPS_NODE=$1
        export CURRENT_USER_NAME=`printenv SUDO_USER`
        [ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"

        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} grep '^server' /etc/ntp.conf" > /var/tmp/cps_node_test 2>/dev/null

        grep "[0-9].rhel.pool.ntp.org" /var/tmp/cps_node_test >/dev/null 2>&1
        [ $? -eq 0 ] && return 0

        grep ${NTP_Server_IP} /var/tmp/cps_node_test >/dev/null 2>&1
        if [ $? -eq 0 ]; then
                rm -f /var/tmp/cps_node_test >/dev/null 2>&1
                return 0
        else
                echo ${NTP_Server_IP} | grep -qi server
                [ $? -eq 0 ] && NTP_Server_IP=`echo ${NTP_Server_IP} | awk '{print $2}'`
                if [ "X${NTP_Server_IP}" != "X${CPS_NODE}" ];then
                        Error "NTP_Server_IP : ${NTP_Server_IP} entered for Current Cluster Node is not configured in CP Server ${CPS_NODE}"
                        ${ECHO} "Please use same NTP Server IP for all the CP Servers and Cluster Nodes"
                        rm -f /var/tmp/cps_node_test >/dev/null 2>&1
                        exit 1
                else
                        rm -f /var/tmp/cps_node_test >/dev/null 2>&1
                        return 0
                fi
        fi

        rm -f /var/tmp/cps_node_test >/dev/null 2>&1

}

#--------------------------------------------------------------------------------------------#
# Function to Configure NTP. Thie function will be called for Clueter and Addnode operation  #
# For Standalone and CPS deployment this function will only be called if external NTP server #
# IP address was provided in the template. For Cluster if NTP Server Ip is not provided then #
# the first node of Cluster will act as NTP Server and remaining nodes (including CPS) will  #
# act as NTP Client.                                                                         #
#--------------------------------------------------------------------------------------------#
Configure_NTP()
{
        Func_Header "Configuring Network Time Protocol" ${1} ${2}

        grep "^OPTIONS=.*ntp:ntp" /etc/sysconfig/ntpd >/dev/null 2>&1
        [ $? -ne 0 ] && sed -i -e '/OPTIONS=/ s/OPTIONS=.*/OPTIONS="-u ntp:ntp"/g' /etc/sysconfig/ntpd

        if [ "X${CONFIGMODE}" = "XADDNODE" ]; then
                Configure_NTP_Addnode
        elif [ "X${CONFIGMODE}" = "XCLUSTER" ]; then
                if [ "X${CURRENT_NODE_AS_NTP}" = "XY" ]; then

                        [ "X${IO_FENCING_TYPE}" = "XCPS" ] && Check_Configure_NTP_CPS
                        Configure_NTP_internal
                else
                        Configure_NTP_external
                        [ "X${IO_FENCING_TYPE}" = "XCPS" ] && Check_Configure_NTP_external_CPS
                fi
        else
                Configure_NTP_external
        fi

        update_status "Configure_NTP=Y"

}

#################################################################
# Function to check if NTP is configured in CPS server or not   #
# If NTP is not configured in CPS then configure the same       #
#################################################################
Check_Configure_NTP_CPS()
{
        source /etc/cp_server_ip >/dev/null 2>&1
        export CURRENT_USER_NAME=`printenv SUDO_USER`
        [ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"

        export CPS_HOSTIP=`${SSH} ${CURRENT_USER_NAME}@${CPS1} "/usr/bin/hostname -i" | awk '{ print $1 }'`
        export CPSHOST_NETMASK=`${SSH} ${CURRENT_USER_NAME}@${CPS1} "/usr/sbin/ifconfig" | grep -w "${CPS_HOSTIP}" | awk '{ print $4 }'`
        export CPSHOST_NWID=`ipcalc -n ${CPS_HOSTIP} ${CPSHOST_NETMASK} | awk -F"=" '{print $2}'`

        cat > /var/tmp/ntp.conf <<-EOF
        restrict -4 default kod nomodify notrap nopeer noquery
        restrict -6 default kod nomodify notrap nopeer noquery
        restrict 127.0.0.1
        restrict -6 ::1
        restrict ${CPSHOST_NWID} mask ${CPSHOST_NETMASK} nomodify notrap

        driftfile /var/lib/ntp/ntp.drift
        logfile /var/log/ntp.log

        server 127.127.1.0 # local clock
        EOF

        for CPS_NODE in `cat /etc/cp_server_ip | awk -F= '{ print $2 }'`
        do
                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/grep '^server' /etc/ntp.conf" | grep "[0-9].rhel.pool.ntp.org" >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                        ${ECHO} "\n--> Configuring Network Time Protocol for CP Server : ${CPS_NODE}"

                        case ${CPS_NODE} in
                        $CPS2)
                                echo "server ${CPS1} iburst prefer" >> /var/tmp/ntp.conf
                                ;;
                        $CPS3)
                                echo "server ${CPS2} iburst" >> /var/tmp/ntp.conf
                                ;;
                        esac

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/rm -f /var/tmp/ntp.conf " >/dev/null 2>&1

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                        ${SUDO} /usr/bin/test -f /var/tmp/ntp.conf
                        if [ \$? -eq 0 ];then
                                ${SUDO} /usr/bin/rm -f /var/tmp/ntp.conf
                        fi "  >/dev/null 2>&1

                        ${SCP} /var/tmp/ntp.conf ${CURRENT_USER_NAME}@${CPS_NODE}:/var/tmp/ntp.conf >/dev/null 2>&1
                        [ -f /var/tmp/ntpd.tar ] && rm -f /var/tmp/ntpd.tar >/dev/null 2>&1
                        tar -cf /var/tmp/ntpd.tar -C /etc/sysconfig/ ntpd >/dev/null 2>&1
                        chmod o+r /var/tmp/ntpd.tar >/dev/null 2>&1

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                        ${SUDO} /usr/bin/test -f /var/tmp/ntpd.tar
                        if [ \$? -eq 0 ];then
                                ${SUDO} /usr/bin/rm -f /var/tmp/ntpd.tar
                        fi "  >/dev/null 2>&1

                        ${SCP} /var/tmp/ntpd.tar ${CURRENT_USER_NAME}@${CPS_NODE}:/var/tmp/ >/dev/null 2>&1
                        if [ $? -eq 0 ];then
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                                ${SUDO} /usr/bin/mv -f /var/tmp/ntp.conf /etc/ntp.conf
                                ${SUDO} /usr/bin/tar -xf /var/tmp/ntpd.tar -C /etc/sysconfig/
                                if [ \$? -eq 0 ];then
                                        ${SUDO} /usr/bin/rm -f /var/tmp/ntpd.tar
                                fi
                                ${SUDO} /usr/bin/chown root:root /etc/ntp.conf
                                ${SUDO} /usr/bin/chmod 644 /etc/ntp.conf
                                ${SUDO} /usr/bin/touch /var/lib/ntp/ntp.drift /var/log/ntp.log
                                ${SUDO} /usr/bin/echo 0.0 | ${SUDO} /usr/bin/tee -a /var/lib/ntp/ntp.drift" >/dev/null 2>&1
                                rm -f /var/tmp/ntpd.tar >/dev/null 2>&1
                        else
                                ${ECHO} "\n[ ERROR ] : Unable to copy /etc/sysconfig/ntpd from ${CURRENT_USER_NAME}@`hostname -s` to ${CURRENT_USER_NAME}@${CPS_NODE} "
                                exit 1
                        fi

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/sbin/iptables-save" | grep -q 123 >/dev/null 2>&1
                        [ $? -ne 0 ] && {
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                                ${SUDO} /usr/sbin/iptables -I INPUT -p udp --dport 123 -j ACCEPT
                                ${SUDO} /usr/sbin/iptables-save
                                exit" >/dev/null 2>&1
                        }

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/firewall-cmd --state -q" >/dev/null 2>&1
                        [ $? -eq 0 ] && {
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                                ${SUDO} /usr/bin/firewall-cmd --add-service=ntp --permanent
                                ${SUDO} /usr/bin/firewall-cmd --reload
                                exit" >/dev/null 2>&1
                        }

                        if [ "X${CPS_NODE}" != "X${CPS1}" ];then
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                                ${SUDO} /usr/bin/timedatectl set-ntp no
                                ${SUDO} /usr/bin/timedatectl set-local-rtc 0
                                ${SUDO} /usr/bin/systemctl enable ntpd.service
                                ${SUDO} /usr/bin/systemctl restart ntpd.service
                                sleep 2
                                ${SUDO} /usr/sbin/ntpdate -b -t 4 -p 4 -u ${CPS1}
                                ${SUDO} /usr/sbin/hwclock --systohc
                                exit" >/dev/null 2>&1
                        else
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                                ${SUDO} /usr/bin/timedatectl set-ntp no
                                ${SUDO} /usr/bin/timedatectl set-local-rtc 0
                                ${SUDO} /usr/bin/systemctl enable ntpd.service
                                ${SUDO} /usr/bin/systemctl restart ntpd.service
                                sleep 2
                                ${SUDO} /usr/sbin/hwclock --systohc
                                exit" >/dev/null 2>&1
                        fi
                fi
        done

        rm -f /var/tmp/ntp.conf
}


#########################################################
# Function to configure NTP during Add a Node operation #
#########################################################
Configure_NTP_Addnode()
{

        export CURRENT_USER_NAME=`printenv SUDO_USER`
        [ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"

        REMOTE_NTP_CONFIGURED="Y"
        /usr/sbin/ntpq -c "timeout 600" -pn ${rem_clus_host} 2>/dev/null | grep -iw remote >/dev/null 2>&1
        if [ $? -eq 0 ];then
                ${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/bin/cat /etc/ntp.conf" | grep "[0-9].rhel.pool.ntp.org" >/dev/null 2>&1
                [ $? -eq 0 ] && REMOTE_NTP_CONFIGURED="N"

        else
                ${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/bin/cat /etc/ntp.conf" | grep "[0-9].rhel.pool.ntp.org" >/dev/null 2>&1
                if [ $? -ne 0 ]; then

                        NTP_Server_IP=`${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/bin/cat /etc/ntp.conf" | grep prefer | awk '{print $2}'`
                        if [ "${NTP_Server_IP}X" != "X" ];then
                                ${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "
                                ${SUDO} /usr/bin/timedatectl set-ntp no >/dev/null 2>&1
                                ${SUDO} /usr/bin/timedatectl set-local-rtc 0 >/dev/null 2>&1
                                ${SUDO} /usr/bin/systemctl enable ntpd.service >/dev/null 2>&1
                                ${SUDO} /usr/bin/systemctl restart ntpd.service >/dev/null 2>&1
                                sleep 2

                                ${SUDO} /usr/sbin/ntpdate -b -t 4 -p 4 -u ${NTP_Server_IP} >/dev/null 2>&1
                                ${SUDO} /usr/sbin/hwclock --systohc >/dev/null 2>&1
                                exit" >/dev/null 2>&1
                        else
                                ${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "
                                ${SUDO} /usr/bin/timedatectl set-ntp no
                                ${SUDO} /usr/bin/timedatectl set-local-rtc 0
                                ${SUDO} /usr/bin/systemctl enable ntpd.service
                                ${SUDO} /usr/bin/systemctl restart ntpd.service
                                sleep 2
                                ${SUDO} /usr/sbin/hwclock --systohc
                                exit" >/dev/null 2>&1
                        fi
                else
                        REMOTE_NTP_CONFIGURED="N"
                fi
        fi

        if [ "X${REMOTE_NTP_CONFIGURED}" = "XY" ];then
                grep '^server' /etc/ntp.conf | grep "[0-9].rhel.pool.ntp.org" >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                        ${ECHO} "\n--> Configuring Network Time Protocol"
                        [ -f /var/tmp/ntp.tar ] && rm -f /var/tmp/ntp.tar  >/dev/null 2>&1
                        ${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "
                        ${SUDO} /usr/bin/test -f /var/tmp/ntp.tar
                        if [ \$? -eq 0 ];then
                                ${SUDO} /usr/bin/rm -f /var/tmp/ntp.tar
                        fi
                        ${SUDO} /usr/bin/tar -cf /var/tmp/ntp.tar -C /etc/ ntp.conf
                        ${SUDO} /usr/bin/chmod o+r /var/tmp/ntp.tar
                        ${SCP} /var/tmp/ntp.tar ${CURRENT_USER_NAME}@${CURRENT_HOST_IP}:/var/tmp/ntp.tar " >/dev/null 2>&1
                        if [ $? -ne 0 ];then
                                ${ECHO} "\n[ ERROR ] : Unable to copy /etc/ntp.conf from ${CURRENT_USER_NAME}@${rem_clus_host} to ${CURRENT_USER_NAME}@${CURRENT_HOST}"
                                exit 1
                        else
                                tar -xf /var/tmp/ntp.tar -C /etc/ >/dev/null 2>&1
                                rm -f /var/tmp/ntp.tar >/dev/null 2>&1
                        fi
                        ${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/bin/rm -f /var/tmp/ntp.tar" >/dev/null 2>&1
                        echo "server ${rem_clus_host} iburst prefer" >> /etc/ntp.conf

                        [ -f /var/tmp/ntpd.tar ] && rm -f /var/tmp/ntpd.tar >/dev/null 2>&1
                        ${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "
                        ${SUDO} /usr/bin/test -f /var/tmp/ntpd.tar
                        if [ \$? -eq 0 ];then
                                ${SUDO} /usr/bin/rm -f /var/tmp/ntpd.tar
                        fi
                        ${SUDO} /usr/bin/tar -cf /var/tmp/ntpd.tar -C /etc/sysconfig/ ntpd
                        ${SUDO} /usr/bin/chmod o+r /var/tmp/ntpd.tar
                        ${SCP} /var/tmp/ntpd.tar ${CURRENT_USER_NAME}@${CURRENT_HOST_IP}:/var/tmp/ntpd.tar " >/dev/null 2>&1
                        if [ $? -ne 0 ];then
                                ${ECHO} "\n[ ERROR ] : Unable to copy /etc/sysconfig/ntpd from ${CURRENT_USER_NAME}@${rem_clus_host} to ${CURRENT_USER_NAME}@${CURRENT_HOST}"
                                exit 1
                        else
                                tar -xf /var/tmp/ntpd.tar -C /etc/sysconfig/ >/dev/null 2>&1
                                rm -f /var/tmp/ntpd.tar >/dev/null 2>&1
                        fi
                        ${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/bin/rm -f /var/tmp/ntp.tar" >/dev/null 2>&1
                        touch /var/lib/ntp/ntp.drift /var/log/ntp.log >/dev/null 2>&1
                        echo 0.0 > /var/lib/ntp/ntp.drift

                        iptables-save | grep -q 123
                        [ $? -ne 0 ] && {
                                iptables -I INPUT -p udp --dport 123 -j ACCEPT >/dev/null 2>&1
                                iptables-save >/dev/null 2>&1
                        }

                        firewall-cmd --state -q
                        [ $? -eq 0 ] && {
                                firewall-cmd --add-service=ntp --permanent >/dev/null 2>&1
                                firewall-cmd --reload >/dev/null 2>&1
                        }

                        timedatectl set-ntp no >/dev/null 2>&1
                        timedatectl set-local-rtc 0 >/dev/null 2>&1
                        systemctl enable ntpd.service >/dev/null 2>&1
                        systemctl restart ntpd.service >/dev/null 2>&1
                        sleep 2

                        ntpdate -b -t 4 -p 4 -u ${rem_clus_host} >/dev/null 2>&1
                        hwclock --systohc >/dev/null 2>&1
                else
                        ${ECHO} "\n--> Network Time Protocol is already configured in current host"
                fi
        else
                ${ECHO} "\n--> Network Time Protocol is not configured in ${rem_clus_host}"
                ${ECHO} "\n--> Skipping NTP configuration..."
        fi

}

#########################################################
# Function to configure NTP using Current System IP     #
#########################################################
Configure_NTP_internal()
{
        export CURRENT_HOSTIP=$(/usr/bin/gethostip -d `hostname -s` 2>/dev/null)
        export HOST_NETMASK=`ifconfig | grep -w "${CURRENT_HOSTIP}" | awk '{print $4}'`
        export HOST_NWID=`ipcalc -n ${CURRENT_HOSTIP} ${HOST_NETMASK} | awk -F"=" '{print $2}'`

        [ "X${CONFIGMODE}" = "XCLUSTER" ] && {
                ${ECHO} "\n--> Configuring Network Time Protocol on Current Cluster Node : ${CURRENT_HOSTIP}"
        } || ${ECHO} "\n--> Validating Network Time Protocol on Current Cluster Node : ${CURRENT_HOSTIP}"

        cat > /var/tmp/ntp.conf <<-EOF
        restrict -4 default kod nomodify notrap nopeer noquery
        restrict -6 default kod nomodify notrap nopeer noquery
        restrict 127.0.0.1
        restrict -6 ::1
        restrict ${HOST_NWID} mask ${HOST_NETMASK} nomodify notrap

        driftfile /var/lib/ntp/ntp.drift
        logfile /var/log/ntp.log

        server 127.127.1.0 # local clock
        EOF

        if [ "X${IO_FENCING_TYPE}" = "XCPS" ]; then

                source /etc/cp_server_ip >/dev/null 2>&1
                echo "server ${CPS1} iburst" >> /var/tmp/ntp.conf
                echo "server ${CPS2} iburst" >> /var/tmp/ntp.conf
                echo "server ${CPS3} iburst prefer" >> /var/tmp/ntp.conf
        fi

        touch /var/lib/ntp/ntp.drift /var/log/ntp.log >/dev/null 2>&1
        echo 0.0 > /var/lib/ntp/ntp.drift

        [ -s /etc/ntp.conf ] && mv -f /etc/ntp.conf /etc/ntp.conf_bkp_`date +%d%m%Y%H%M%S`
        mv -f /var/tmp/ntp.conf /etc/ntp.conf

        iptables-save | grep -q 123
        [ $? -ne 0 ] && {
                iptables -I INPUT -p udp --dport 123 -j ACCEPT >/dev/null 2>&1
                iptables-save >/dev/null 2>&1
        }

        firewall-cmd --state -q
        [ $? -eq 0 ] && {
                firewall-cmd --add-service=ntp --permanent >/dev/null 2>&1
                firewall-cmd --reload >/dev/null 2>&1
        }

        systemctl enable ntpd.service >/dev/null 2>&1
        systemctl restart ntpd.service >/dev/null 2>&1

        if [ "X${IO_FENCING_TYPE}" = "XCPS" ]; then
                timedatectl set-ntp no  >/dev/null 2>&1
                systemctl stop ntpd.service >/dev/null 2>&1
                ntpdate -b -t 4 -p 4 -u ${CPS1} >/dev/null 2>&1
                [ $? -eq 0 ] && {
                        timedatectl set-local-rtc 0 >/dev/null 2>&1
                        hwclock --systohc >/dev/null 2>&1
                }

                systemctl restart ntpd.service >/dev/null 2>&1
        else
                timedatectl set-ntp no  >/dev/null 2>&1
                timedatectl set-local-rtc 0 >/dev/null 2>&1
        fi

        hwclock --systohc >/dev/null 2>&1

}

#########################################################
# Function to configure NTP using external NTP Server   #
#########################################################
Configure_NTP_external()
{

        ${ECHO} "\n--> Configuring NTP using NTP Server IP ${NTP_Server_IP}"
        export CURRENT_HOSTIP=$(/usr/bin/gethostip -d `hostname -s` 2>/dev/null)
        export HOST_NETMASK=`ifconfig | grep -w "${CURRENT_HOSTIP}" | awk '{print $4}'`
        export HOST_NWID=`ipcalc -n ${CURRENT_HOSTIP} ${HOST_NETMASK} | awk -F"=" '{print $2}'`

        cat > /var/tmp/ntp.conf <<-EOF
        restrict -4 default kod nomodify notrap nopeer noquery
        restrict -6 default kod nomodify notrap nopeer noquery
        restrict 127.0.0.1
        restrict -6 ::1
        restrict ${HOST_NWID} mask ${HOST_NETMASK} nomodify notrap

        driftfile /var/lib/ntp/ntp.drift
        logfile /var/log/ntp.log

        server 127.127.1.0 # local clock
        server ${NTP_Server_IP} iburst prefer
        EOF

        touch /var/lib/ntp/ntp.drift /var/log/ntp.log >/dev/null 2>&1
        echo 0.0 > /var/lib/ntp/ntp.drift

        [ -s /etc/ntp.conf ] && mv -f /etc/ntp.conf /etc/ntp.conf_bkp_`date +%d%m%Y%H%M%S`
        mv -f /var/tmp/ntp.conf /etc/ntp.conf

        iptables-save | grep -q 123
        [ $? -ne 0 ] && {
                iptables -I INPUT -p udp --dport 123 -j ACCEPT >/dev/null 2>&1
                iptables-save >/dev/null 2>&1
        }

        firewall-cmd --state -q
        [ $? -eq 0 ] && {
                firewall-cmd --add-service=ntp --permanent >/dev/null 2>&1
                firewall-cmd --reload >/dev/null 2>&1
        }

        timedatectl set-ntp no >/dev/null 2>&1
        timedatectl set-local-rtc 0 >/dev/null 2>&1
        systemctl enable ntpd.service >/dev/null 2>&1
        systemctl restart ntpd.service >/dev/null 2>&1
        sleep 2
        ntpdate -b -t 4 -p 4 -u ${NTP_Server_IP} >/dev/null 2>&1
        hwclock --systohc >/dev/null 2>&1
}

########################################################################
# Function to configure NTP on CPS Server using external NTP Server    #
########################################################################
Check_Configure_NTP_external_CPS() {

        source /etc/cp_server_ip >/dev/null 2>&1
        export CURRENT_USER_NAME=`printenv SUDO_USER`
        [ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"

        for value in ${CPS1} ${CPS2} ${CPS3}
        do
                CPS_NODE=`echo ${value} | awk -F= '{ print $2 }'`
                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/grep '^server' /etc/ntp.conf" | grep "[0-9].rhel.pool.ntp.org" >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                        ${ECHO} "\n--> Configuring Network Time Protocol for CP Server : ${CPS_NODE}"
                        [ -f /var/tmp/ntp.tar ] && rm -f /var/tmp/ntp.tar >/dev/null 2>&1
                        [ -f /var/tmp/ntpd.tar ] && rm -f /var/tmp/ntpd.tar  >/dev/null 2>&1
                        tar -cf /var/tmp/ntp.tar -C /etc/ ntp.conf
                        tar -cf /var/tmp/ntpd.tar -C /etc/sysconfig/ ntpd
                        chmod o+r /var/tmp/ntp.tar /var/tmp/ntpd.tar

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                        ${SUDO} /usr/bin/test -f /var/tmp/ntp.tar
                        if [ \$? -eq 0 ];then
                                ${SUDO} /usr/bin/rm -f /var/tmp/ntp.tar
                        fi "  >/dev/null 2>&1

                        ${SCP} /var/tmp/ntp.tar ${CURRENT_USER_NAME}@${CPS_NODE}:/var/tmp/ntp.tar >/dev/null 2>&1
                        if [ $? -ne 0 ];then
                                ${ECHO} "\n[ ERROR ] : Unable to copy /etc/ntp.conf from ${CURRENT_USER_NAME}@`hostname -s` to ${CURRENT_USER_NAME}@${CPS_NODE} "
                                exit 1
                        fi

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                        ${SUDO} /usr/bin/test -f /var/tmp/ntpd.tar
                        if [ \$? -eq 0 ];then
                                ${SUDO} /usr/bin/rm -f /var/tmp/ntpd.tar
                        fi "  >/dev/null 2>&1

                        ${SCP} /var/tmp/ntpd.tar ${CURRENT_USER_NAME}@${CPS_NODE}:/var/tmp/ntpd.tar >/dev/null 2>&1
                        if [ $? -ne 0 ];then
                                ${ECHO} "\n[ ERROR ] : Unable to copy /etc/sysconfig/ntpd from ${CURRENT_USER_NAME}@`hostname -s` to ${CURRENT_USER_NAME}@${CPS_NODE} "
                                exit 1
                        fi
                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                        ${SUDO} /usr/bin/tar -xf /var/tmp/ntp.tar -C /etc/
                        sleep 1
                        ${SUDO} /usr/bin/tar -xf /var/tmp/ntpd.tar -C /etc/sysconfig/
                        sleep 1
                        ${SUDO} /usr/bin/rm -f /var/tmp/ntp.tar /var/tmp/ntpd.tar
                        ${SUDO} /usr/bin/touch /var/lib/ntp/ntp.drift /var/log/ntp.log
                        ${SUDO} /usr/bin/echo 0.0 | ${SUDO} /usr/bin/tee -a /var/lib/ntp/ntp.drift" >/dev/null 2>&1
                        rm -f /var/tmp/ntp.tar /var/tmp/ntpd.tar >/dev/null 2>&1

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} echo 0.0 | ${SUDO} /usr/bin/tee -a /var/lib/ntp/ntp.drift" >/dev/null 2>&1

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/sbin/iptables-save" | grep -q 123 >/dev/null 2>&1
                        [ $? -ne 0 ] && {
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                                ${SUDO} /usr/sbin/iptables -I INPUT -p udp --dport 123 -j ACCEPT
                                ${SUDO} /usr/sbin/iptables-save
                                exit" >/dev/null 2>&1
                        }

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "${SUDO} /usr/bin/firewall-cmd --state -q" >/dev/null 2>&1
                        [ $? -eq 0 ] && {
                                ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                                ${SUDO} /usr/bin/firewall-cmd --add-service=ntp --permanent
                                ${SUDO} /usr/bin/firewall-cmd --reload
                                exit" >/dev/null 2>&1
                        }

                        ${SSH} ${CURRENT_USER_NAME}@${CPS_NODE} "
                        ${SUDO} /usr/bin/timedatectl set-ntp no
                        ${SUDO} /usr/bin/timedatectl set-local-rtc 0
                        ${SUDO} /usr/bin/systemctl enable ntpd.service
                        ${SUDO} /usr/bin/systemctl restart ntpd.service
                        sleep 2
                        ${SUDO} /usr/bin/systemctl stop ntpd.service
                        ${SUDO} /usr/sbin/ntpdate -b -t 4 -p 4 -u ${NTP_Server_IP}
                        ${SUDO} /usr/sbin/hwclock --systohc
                        exit" >/dev/null 2>&1
                fi
        done

}