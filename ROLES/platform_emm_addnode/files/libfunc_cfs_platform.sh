#!/bin/ksh

#-----------------------------------------------#
# This Function will configure VCS using DISK	#
# based I/O Fencing								#
#-----------------------------------------------#

# DevOps updates:
# 1. input_additional_network_ipv4 function: bond not pingable

create_cfs_respfile()
{

	### Reading Cluster section
	log "\n--> Generating response file"
	sed -n "/^\[.*\<Cluster\>\]/,/^\[/s/^[^[]/&/p" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} > /var/tmp/cluster.ini
	chmod 755 /var/tmp/cluster.ini
	source /var/tmp/cluster.ini
	rm -f /var/tmp/cluster.ini

	sed -e "s/<HOSTNAME>/`hostname -s`/g" \
	-e "s/<CLUSTERID>/${Cluster_ID}/g" \
	-e "s/<VER>/${VER}/g" \
	-e "s/<CLUSTERNAME>/${Cluster_Name}/g" \
	-e "s/<VRTS_PROD_TYPE>/${VRTS_PROD_TYPE}/g" \
	-e "s/<HBLINK1>/${HeartBeat_Link_1}/g" \
	-e "s/<HBLINK2>/${HeartBeat_Link_2}/g" \
	-e "s/<fendg>/${IOFENDG}/g" \
	${CFS_Template_File}.eric > ${CFS_Template_File}

	echo ${IOFENDG} > /etc/vxfendg
	
	[ "X${Cluster_Type}" = "XVCS" ] && sed -i -e "s/SFCFSHA/VCS/g" ${CFS_Template_File}

	if [ ! -f ${CFS_Template_File} ]; then
		log " [ERROR] : Could not create response file for Cluster Setup. Exiting!!"
		exit 2002
	fi

}

#-----------------------------------------------#
# This Function will configure VCS using CPS	#
# based I/O Fencing				#
#-----------------------------------------------#
create_cfs_cps_respfile()
{
	### Reading Cluster section
	log "\n--> Generating response file"
	sed -n "/^\[.*\<Cluster\>\]/,/^\[/s/^[^[]/&/p" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} > /var/tmp/cluster.ini
	source /var/tmp/cluster.ini
	rm -f /var/tmp/cluster.ini

	sed -e "s/<HOSTNAME>/`hostname -s`/g" \
	-e "s/<CLUSTERID>/${Cluster_ID}/g" \
	-e "s/<VER>/${VER}/g" \
	-e "s/<CLUSTERNAME>/${Cluster_Name}/g" \
	-e "s/<VRTS_PROD_TYPE>/${VRTS_PROD_TYPE}/g" \
	-e "s/<HBLINK1>/${HeartBeat_Link_1}/g" \
	-e "s/<HBLINK2>/${HeartBeat_Link_2}/g" \
	-e "s/<CPS1>/${CPS1}/g" \
	-e "s/<CPS2>/${CPS2}/g" \
	-e "s/<CPS3>/${CPS3}/g" \
	${CFS_CPS_Template_File}.eric > ${CFS_CPS_Template_File}


	[ "X${Cluster_Type}" = "XVCS" ] && sed -i -e "s/SFCFSHA/VCS/g" ${CFS_CPS_Template_File}
	[ "X${FSTYPE}" = "XNFS" ] && sed -i -e "s/SFCFSHA/VCS/g" ${CFS_CPS_Template_File}

	if [ ! -f ${CFS_CPS_Template_File} ]; then
		log " [ERROR] : Could not create response file for Cluster Setup. Exiting!!"
		exit 2002
	fi

}

#----------------------------------------------------------------------------#
# This Function will be called to make the VCS Cluster from response file    #
#----------------------------------------------------------------------------#
make_the_cluster()
{

	export CURRENT_USER_NAME=`printenv SUDO_USER`
	[ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"
	
	for svc in vxglm vxodm vxgms vxfen gab llt
	do
		systemctl stop ${svc} > /dev/null 2>&1
	done
	/opt/VRTSvcs/bin/CmdServer -stop > /dev/null 2>&1
	sleep 2
	/opt/VRTS/bin/amfconfig -Uof > /dev/null 2>&1
	sleep 2
	/opt/VRTSvcs/vxfen/bin/vxfen unload > /dev/null 2>&1
	
	for vrfile in vxfen llt gab vcs
	do
		sed -i -e "s/_START=.*/_START=1/g" -e "s/_STOP=.*/_STOP=1/g" /etc/sysconfig/${vrfile} >/dev/null 2>&1
	done
	
	if [ "X${IO_FENCING_TYPE}" = "XCPS" ];then 
		source /etc/cp_server_ip >/dev/null 2>&1
		${SSH} ${CURRENT_USER_NAME}@${CPS1} "${SUDO} /usr/bin/systemctl restart ntpd.service"  >/dev/null 2>&1

		systemctl restart ntpd.service >/dev/null 2>&1
		sleep 3
		ntpdate -b -t 4 -p 4 -u ${CPS1} >/dev/null 2>&1
		hwclock --systohc >/dev/null 2>&1

		create_cfs_cps_respfile
		if [ -s ${CFS_CPS_Template_File} ] && [ -x ${INSTALLVCS} ]; then

			${SSH} ${CURRENT_USER_NAME}@${CPS2} "
			${SUDO} /usr/bin/systemctl restart ntpd.service
			sleep 2
			${SUDO} /usr/sbin/ntpdate -b -t 4 -p 4 -u ${CPS1}
			${SUDO} /usr/sbin/hwclock --systohc
			exit" >/dev/null 2>&1

			${SSH} ${CURRENT_USER_NAME}@${CPS3} "
			${SUDO} /usr/bin/systemctl restart ntpd.service
			sleep 2
			${SUDO} /usr/sbin/ntpdate -b -t 4 -p 4 -u ${CPS1}
			${SUDO} /usr/sbin/hwclock --systohc
			exit" >/dev/null 2>&1
		
			for cp_vip in ${CPS1} ${CPS2} ${CPS3}
			do				
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
			done

			log "\n--> Please wait while VCS configuration is started"
			[ -s /var/tmp/Platform_LOGS.txt ] && rm -f /var/tmp/Platform_LOGS.txt > /dev/null 2>&1
			
			${INSTALLVCS} -responsefile ${CFS_CPS_Template_File} -noipc | tee /var/tmp/Platform_LOGS.txt
			sed -i "/V-9-40-6798/d" /var/tmp/Platform_LOGS.txt
		fi

		chmod +x /etc/rc.d/rc.local
		cp ${MISC_DIR}/cps_vxfen /etc/init.d/ > /dev/null 2>&1
		chmod 755 /etc/init.d/cps_vxfen > /dev/null 2>&1
		grep -w "cps_vxfen" /etc/rc.d/rc.local > /dev/null 2>&1
		[ $? -ne 0 ] && echo "/etc/init.d/cps_vxfen" >> /etc/rc.d/rc.local
	else
		create_cfs_respfile
		if [ -s ${CFS_Template_File} ] && [ -x ${INSTALLVCS} ];then
			log "\n--> Please wait while VCS configuration is started"
			[ -s /var/tmp/Platform_LOGS.txt ] && rm -f /var/tmp/Platform_LOGS.txt > /dev/null 2>&1

			${INSTALLVCS} -responsefile ${CFS_Template_File} -noipc | tee /var/tmp/Platform_LOGS.txt
			sed -i "/V-9-40-6798/d" /var/tmp/Platform_LOGS.txt
		fi
	fi
}

#------------------------------------#
# This Function will configure VCS   #
# taking responsile as an input      #
#------------------------------------#
Configure_VCS()
{
	Func_Header "Configure VCS" ${1} ${2}

	trap "/opt/VRTSvcs/bin/hastop -local" EXIT
	CURRENT_HOST=`hostname -s`
	${HASYS} -state 2>/dev/null | awk '{print $1}'| grep -w "^${CURRENT_HOST}$" >/dev/null 2>&1
	if [ $? -ne 0 ];then
		make_the_cluster
	else
		/usr/sbin/vxfenconfig -l | grep "Fencing\ Mode" | grep -w DISABLED >/dev/null 2>&1
		[ $? -eq 0 ] && {
			${HASTOP} -local >/dev/null 2>&1
			make_the_cluster
		}
	fi

	if [ "X${Cluster_Type}" = "XSFCFSHA" ]; then
		${HAGRP} -state 2>/dev/null | grep -w cvm >/dev/null 2>&1
		if [ $? -ne 0 ];then
			log "\ncvm Service Group is not configured. Please check the Logs for more details"
			log "\n Configuration for <Veritas Cluster> FAILED."
			exit 1
		fi
	fi

	if [ -s /var/tmp/Platform_LOGS.txt ];then
		grep "Failed$" /var/tmp/Platform_LOGS.txt | sort -u | grep "Starting\ llt"  > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			VRTS_CONFIG_LOG_DIR=`grep "/opt/VRTS/install/logs" /var/tmp/Platform_LOGS.txt | sort -u | tail -1`
			if [ -s ${VRTS_CONFIG_LOG_DIR}/start.llt.`hostname -s` ]; then
				grep "ERROR" ${VRTS_CONFIG_LOG_DIR}/start.llt.`hostname -s` | grep "already\ being\ used"> /dev/null 2>&1
				[ $? -eq 0 ] && {
					${ECHO} "\n\nCluster Configuration failed for the following ERROR"
					${ECHO} "====================================================\n"
					grep "ERROR" ${VRTS_CONFIG_LOG_DIR}/start.llt.`hostname -s`
					[ -s /var/tmp/Platform_LOGS.txt ] && rm -f /var/tmp/Platform_LOGS.txt > /dev/null 2>&1
					exit 1
				}
			fi
			
			grep "V-14-2-15238" /var/log/messages | grep -w "${CURRENT_HOST}" | grep "ERROR" | grep "lltconfig" > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				${ECHO} "\n\nCluster Configuration failed for the following ERROR"
				${ECHO} "====================================================\n"
				grep "V-14-2-15238" /var/log/messages | grep -w "${CURRENT_HOST}" | grep "ERROR" | grep "lltconfig"
				[ -s /var/tmp/Platform_LOGS.txt ] && rm -f /var/tmp/Platform_LOGS.txt > /dev/null 2>&1
				exit 1
			fi
	fi

	rm -f /var/tmp/Platform_LOGS.txt > /dev/null 2>&1
	fi

	if [ "X${Cluster_Type}" = "XSFCFSHA" ]; then
		count=0
		${HAGRP} -online cvm -sys `hostname -s` > /dev/null 2>&1
		while true
		do
			${HAGRP} -online cvm -sys `hostname -s` >/dev/null 2>&1
			${HAGRP} -state cvm -sys `hostname -s` 2>/dev/null |grep ONLINE >/dev/null 2>&1
			if [ $? -ne 0 ]; then
				if [ "${count}" -gt 60 ]; then
					log "\n\nCVM service group is not ONLINE on node ${node}.\n Make sure that CVM is up on all the cluster Nodes."
					log "\n Configuration for <Veritas Cluster> FAILED."
					exit 1
				else
					${ECHO} "\n  --> Waiting for cvm Service Group to come ONLINE"
					count=`expr ${count} + 1`
					sleep 5
				fi
			else
				break
			fi
		done
	elif [ "X${Cluster_Type}" = "XVCS" ]; then

		count=0
		while [ 1 ]; do
			${HASYS} -state 2>/dev/null | grep RUNNING | grep `hostname -s` >/dev/null 2>&1
			if [ $? -ne 0 ];then
				if [ "${count}" -gt 60 ]; then
					log "\n\n HA Cluster Daemon is not ONLINE on node ${node}.\n Make sure that HA Cluster Daemon is up on all the cluster Nodes."
					log "\n Configuration for <Veritas Cluster> FAILED."
					exit 1
				else
					${ECHO} "\n  --> Waiting for Cluster Service to come ONLINE"
					count=`expr ${count} + 1`
					sleep 5
				fi
			else
				break
			fi
		done
		
	fi

	if [ "X${IO_FENCING_TYPE}" = "XCPS" ]; then

		${VXDCTL} scsi3pr 2>/dev/null | grep "off$" >/dev/null 2>&1
		[ $? -ne 0 ] && ${VXDCTL} scsi3pr off >/dev/null 2>&1

		[ ! -s /var/VRTSvxfen/security/keys/client_private.key ] && {
			log "\n [ERROR] : Fencing configuration with CP Servers failed.\n Please check the connectivity with the CP Servers"
			exit 1
		}
		source /etc/cp_server_ip >/dev/null 2>&1
		client_cert=`ls -1 /var/VRTSvxfen/security/certs | grep "^client_" | egrep "${CPS1}|${CPS2}|${CPS3}" | wc -l`
		
		[ ${client_cert} -ne 3 ] && {
			log " [ERROR] : Fencing configuration with CP Servers failed.\n Please check the connectivity with the CP Servers"
			exit 1
		}

		grep "Vxfen_CPS" /etc/VRTSvcs/conf/config/main.cf >/dev/null 2>&1
		[ $? -ne 0 ] && {
			log " [ERROR] : Fencing configuration with CP Servers failed.\n Please check the connectivity with the CP Servers"
			exit 1
		}
	fi
	
	trap - EXIT
	Update_user_group

	flog "Please check the configuration logs under : /opt/VRTS/install/logs/`ls -tr /opt/VRTS/install/logs | tail -1` directory"
	
	log "\n Configuration for <Veritas Cluster> was successful."
	
	Stop_telemetry_service_veritas
	
	touch -f /tmp/reboot_now

	# Set MTU value to 1200 in case of cloud environment
	rpm -qa | grep -w "cloud-init" >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		sed -i "/link/s/-$/1200/" /etc/llttab
	fi

	if [ "X${IO_FENCING_TYPE}" = "XCPS" ];then
		Revert_SysFiles /var/tmp/cp_sysfiles_info CPS "Performing post configuration tasks on"
	fi
	update_status "Configure_VCS=Y"
}
######################################
### UPDATE USER/GROUP  ###############
######################################
Update_user_group()
{
####################Updating user/group if not assigned start ################
        find /opt/VRTSvcs/ -xdev -nouser >/var/tmp/test
        cat /var/tmp/test |while read line
        do
                chown root: $line
        done
        find /opt/VRTSvcs -xdev -nogroup >/var/tmp/test
        cat /var/tmp/test |while read line
        do
                chown :root $line
        done
        find /var/VRTSvcs/ -xdev -nouser >/var/tmp/test
        cat /var/tmp/test |while read line
        do
                chown root: $line
        done
        find /var/VRTSvcs/ -xdev -nogroup >/var/tmp/test
        cat /var/tmp/test |while read line
        do
                chown :root $line
        done
####################Updating user/group if not assigned end ################
}

#######################################
### NFS SHARE TO Cluster Configuration#
#######################################

Cloud_NFS_Group()
{
	func_seq_no=${1}
	Func_Header "Configuring Service Group for NFS Mount" ${func_seq_no} ${2}

	${HASTATUS} -sum > /dev/null 2>&1
	[ $? -ne 0 ] && {
		${ECHO} "Cluster Daemon is not running on current node"
		exit 1
	}

	${HAGRP} -list | grep -w ${SG_CLOUD_NAME} >/dev/null 2>&1
	if [ $? -ne 0 ]; then 

		MOUNT_RESOURCE1="nfsmount1"
		MOUNT_RESOURCE2="nfsmount2"
		MOUNT_POINT1=/var/opt/mediation/MMDB
		MOUNT_POINT2=/var/opt/mediation/MMStorage
		
		###################Checking for Service Group In Cluster ##############

		${ECHO} "\n Adding Service Group ${SG_CLOUD_NAME} to Cluster Configuration"
		
		# Make cluster configuration read-write
		conf_stat=`${HACLUS} -value ReadOnly`
		if [ ${conf_stat} -ne 0 ];then
			${ECHO} "\n--> Making Cluster Read write"
			${HACONF} -makerw
			sleep 3
		fi

		${HAGRP} -add ${SG_CLOUD_NAME} >/dev/null 2>&1
		${HAGRP} -modify ${SG_CLOUD_NAME} SystemList -add `hostname -s` 0
		${HAGRP} -modify ${SG_CLOUD_NAME} AutoStartList -add `hostname -s`
		${HAGRP} -modify ${SG_CLOUD_NAME} Parallel 1
		${HAGRP} -link ${SG_CLOUD_NAME} Network online local firm

		${ECHO} "\n--> Creating ${MOUNT_RESOURCE1} Resource in ${SG_CLOUD_NAME}"
		
		${HARES} -add ${MOUNT_RESOURCE1} Mount ${SG_CLOUD_NAME} > /dev/null 2>&1
		${HARES} -modify ${MOUNT_RESOURCE1} Critical 1
		${HARES} -modify ${MOUNT_RESOURCE1} MountPoint "${MOUNT_POINT1}"
		${HARES} -modify ${MOUNT_RESOURCE1} BlockDevice "${MMDB_Share_IP}:${MMDB_Share_Name}"
		${HARES} -modify ${MOUNT_RESOURCE1} FSType ${NFS_Ver_MMDB}
		
		if [ "X${NFS_Ver_MMDB}" = "Xnfs" ];then
			version=3
		elif [ "X${NFS_Ver_MMDB}" = "Xnfs4" ];then
			version=4.0
		fi
		${HARES} -modify ${MOUNT_RESOURCE1} MountOpt "rw,bg,hard,nointr,tcp,vers=${version},timeo=600,rsize=1048576,wsize=1048576"
		${HARES} -modify ${MOUNT_RESOURCE1} Enabled 1
		${HARES} -override ${MOUNT_RESOURCE1} LevelTwoMonitorFreq
		${HARES} -modify ${MOUNT_RESOURCE1} LevelTwoMonitorFreq 1

		${ECHO} "\n--> Creating ${MOUNT_RESOURCE2} Resource in ${SG_CLOUD_NAME}"

		${HARES} -add ${MOUNT_RESOURCE2} Mount ${SG_CLOUD_NAME} > /dev/null 2>&1
		${HARES} -modify ${MOUNT_RESOURCE2} Critical 1
		${HARES} -modify ${MOUNT_RESOURCE2} MountPoint "${MOUNT_POINT2}"
		${HARES} -modify ${MOUNT_RESOURCE2} BlockDevice "${MMStorage_Share_IP}:${MMStorage_Share_Name}"
		${HARES} -modify ${MOUNT_RESOURCE2} FSType ${NFS_Ver_MMStorage}
		
		if [ "X${NFS_Ver_MMStorage}" = "Xnfs" ];then
			version=3
		elif [ "X${NFS_Ver_MMStorage}" = "Xnfs4" ];then
			version=4.0
		fi

		${HARES} -modify ${MOUNT_RESOURCE2} MountOpt "rw,bg,hard,nointr,tcp,vers=${version},timeo=600,rsize=1048576,wsize=1048576"
		${HARES} -modify ${MOUNT_RESOURCE2} Enabled 1
		${HARES} -override ${MOUNT_RESOURCE2} LevelTwoMonitorFreq
		${HARES} -modify ${MOUNT_RESOURCE2} LevelTwoMonitorFreq 1

		# Make cluster configuration read-only
		conf_stat=`${HACLUS} -value ReadOnly`
		if [ ${conf_stat} -eq 0 ];then
			${ECHO} "\n--> Saving Cluster Configuration"
			${HACONF} -dump -makero
			sleep 3
		fi
		bond_name=`${HARES} -display MM_ONM_NIC -attribute Device DualDevice | grep bond  | awk '{print $4}' | sort -u | head -1`
		route -n | grep -w ${bond_name} | grep -wq UG
		if [ $? -ne 0 ]; then
			GATEWAY=`${HARES} -display MM_ONM_NIC -attribute IPv4RouteOptions | grep IPv4RouteOptions | awk '{print $NF}'`
			[ "X${GATEWAY}" != "X" ] && ip route add default via ${GATEWAY}  dev ${bond_name} 2> /dev/null
		fi
	fi

	HOSTNAME=`hostname -s`
	SG_STATE=`${HAGRP} -state ${SG_CLOUD_NAME} -sys $HOSTNAME 2>/dev/null`

	if [ "X${SG_STATE}" != "XONLINE" ]; then
		${HAGRP} -online ${SG_CLOUD_NAME} -any >/dev/null 2>&1
	fi

	${ECHO} "\n NFS Mount Resources successfully Configured\n"
	update_status "Cloud_NFS_Group=Y"
}


#----------------------------------#
# Function to import Disk Group in #
# Shared mode on CVM master        #
#----------------------------------#
Make_DG_Shareable()
{
	Func_Header "Making Disk Groups Shareable" ${1} ${2}

	woDGS_single="${DATADG}"
	unset vdgarray
	unset vdgmountarray
	vdgnames=""
	for numofdgs in ${woDGS_single}
	do
		vdg=`echo ${numofdgs} | cut -d":" -f1`
		vdgnames="${vdgnames} ${vdg}"
		vdgdir=`echo ${numofdgs} | cut -d":" -f2`
		vdgmountdir="${vdgmountdir} ${vdgdir}"
		vdgdesc=`echo ${numofdgs} | cut -d":" -f3`
		vdgmountdesc="${vdgmountdesc} ${vdgdesc}"
	done
	
	#--------------------------#
	# Creation of Array        #
	#--------------------------#
	set -A vdgarray ${vdgnames}
	set -A vdgmountarray ${vdgmountdir}

	#-----------------------------#
	# Unmount the Veritas Volumes #
	#-----------------------------#
	for mountpath in ${vdgmountarray[@]}
	do
		cat /etc/fstab | grep -v "^#" | grep -w "${mountpath}">/dev/null 2>&1
		[ $? -eq 0 ] && {
			grep -vw "${mountpath}" /etc/fstab >/etc/fstab.mod
			echo y | mv -f /etc/fstab /etc/fstab_`date +%d_%m_%Y-%H_%M`
			mv -f /etc/fstab.mod /etc/fstab
		}

		/bin/df -k| grep "${mountpath}" > /dev/null 2>&1
		[ $? -eq 0 ] && {
			/bin/fuser -k -c ${mountpath} > /dev/null 2>&1	
			/bin/umount -f ${mountpath} > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				Error "Unable to unmount ${dgs} disk group"
				exit 1
			fi
		}
	done

	#------------------------------#
	# Deport all the Disk Groups   #
	#------------------------------#
	for dgs in ${vdgarray[@]}
	do
		${VXDISK} list 2>/dev/null | grep -w "$dgs" > /dev/null 2>&1
		[ $? -eq 0 ] && {
			${VXDG} deport ${dgs} > /dev/null 2>&1
			if [ $? -ne 0 ];then
				Error "\nUnable to deport ${dgs} disk group"
				exit 1
			fi
		}
	done

	sleep 3

	#-----------------------------#
	# This is to find CVM Master  #
	#-----------------------------#
	cvmmaster=`${VXDCTL} -c mode 2>/dev/null | grep "^master" | awk -F':' '{ print $2 }'`
	cvmmaster=`echo ${cvmmaster}`
	export CURRENT_USER_NAME=`printenv SUDO_USER`
	[ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"

	if [ -z ${cvmmaster} ];then
		Error "\nUnable to find CVM Master, Please check CVM configuration..."
		exit 1
	fi	

	if [ "X`hostname -s`" = "X${cvmmaster}" ];then
		for dgs in ${vdgarray[@]}
			do
			${VXDG} -Cfs import ${dgs}
		done
	else
		for dgs in ${vdgarray[@]}
		do
			${SSH} ${CURRENT_USER_NAME}@${cvmmaster} "${SUDO} ${VXDG} -Cfs import ${dgs}"
		done
	fi 

	#-------------------------------#
	# This will ensure all DG's are #
	# imported in shared mode       #
	#-------------------------------#
	for dgs in ${vdgarray[@]}
	do
		${VXDG} list | grep -w ${dgs} | grep "shared" > /dev/null 2>&1
		if [ $? -ne 0 ];then
			log "\nDisk Group : ${dgs} is not imported in shared mode"
			log "\nPlease ensure that all the disk devices are visible on all the nodes with active paths"
			log "\nPlease try reconfig reboot of other cluster node."
			exit 1
		fi
	done

	#-------------------------------#
	# Add DG to VCS config		#
	#-------------------------------#
	ctr=-1
	for dgs in ${vdgarray[@]}
	do
		ctr=`expr $ctr + 1`
		mountpoint=`echo ${vdgmountarray[$ctr]}`
		dgdescription=`echo ${vdgdescarray[$ctr]} | sed 's/#/ /g'`
		/opt/VRTS/bin/cfsmntadm add ${dgs} vol01 ${mountpoint} Mediation_DG all=cluster
		ret_code=`echo $?`
		if [ "${ret_code}" -ne 0 ] && [ "${ret_code}" -ne 4 ]; then
			log "\nCould not add ${dgdescription} to Cluster configuration. Please check /var/VRTSvcs/log/engineA.log for more details"			
			exit 1
		fi
	done

	for res in `${HAGRP} -resources Mediation_DG`
	do
		rcode=`${HARES} -display ${res} | grep Critical | awk '{print $NF}'`
		if [ "${rcode}" -eq 0 ]; then
			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 1 ];then
				${ECHO} "\n--> Making Cluster Configuration RE-Writable"
				${HACONF} -makerw
				sleep 3
			fi
			${HARES} -modify ${res} Critical 1
		fi
	done
	
	conf_stat=`${HACLUS} -value ReadOnly`
	if [ ${conf_stat} -eq 0 ];then
		${ECHO} "\n--> Saving Cluster Configuration"
		${HACONF} -dump -makero
		sleep 3
	fi

	log "\nImporting of disk groups in <SHARED MODE> was successful."
	update_status "Make_DG_Shareable=Y"

}

Network_Service_Group()
{
	Func_Header "Adding Network Resources to Cluster" ${1} ${2}
	## Check if cluster is running up and fine
	${HASYS} -state `hostname -s` > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		log " [ERROR] : Ensure that cluster is running in healthy state. Could not determine state of cluster"
		exit 205
	fi
	
	sed -n "/^\[.*\<Cluster\>\]/,/^\[/s/^[^[]/&/p" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} >> /tmp/cluster.ini
	source /tmp/cluster.ini
	rm -f /tmp/cluster.ini
	
	own_name=`hostname -s`
	
	${HAGRP} -list 2>/dev/null | grep -w "Vxfen_CPS" > /dev/null 2>&1 
	if [ $? -eq 0 ]; then
		${HAGRP} -value Vxfen_CPS AutoStartList | grep -w ${own_name} > /dev/null 2>&1 
		if [ $? -ne 0 ]; then
			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 1 ];then
				${HACONF} -makerw
				sleep 1
			fi

			${HAGRP} -modify Vxfen_CPS AutoStartList -add ${own_name} >/dev/null 2>&1

			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 0 ];then
				${HACONF} -dump -makero
				sleep 3
			fi
		fi
	fi

	## Check if there exists a network group
	${HAGRP} -list 2>/dev/null | grep -q Network
	if [ $? -eq 0 ]; then
		## Check state of Network group
		${HAGRP} -state Network -sys ${own_name} 2>/dev/null | grep "ONLINE" > /dev/null 2>&1
		if [ $? -ne 0 ]; then
		
			for bad_res in `${HAGRP} -resources Network`
			do 
				if [ "X`${HARES} -state ${bad_res} -sys ${own_name}`" != "XONLINE" ]; then
					# Check if this resource need to exist else delete it
					conf_stat=`${HACLUS} -value ReadOnly`
					if [ ${conf_stat} -eq 1 ];then
						${ECHO} "\n--> Making Cluster Configuration RE-Writable"
						${HACONF} -makerw
						sleep 3
					fi

					for name_bond in `${HARES} -display ${bad_res} -attribute Device -sys ${own_name} 2> /dev/null | grep -o "bond[0-9]*"`
					do
						if [ ! -f /etc/sysconfig/network-scripts/ifcfg-${name_bond} ]; then
							${HARES} -delete ${bad_res} 2>/dev/null
						fi
					done
					
					for name_bond in `${HARES} -display ${bad_res} -attribute DualDevice -sys ${own_name} 2> /dev/null | grep -o "bond[0-9]*"`
					do
						if [ ! -f /etc/sysconfig/network-scripts/ifcfg-${name_bond} ]; then
							${HARES} -delete ${bad_res} 2>/dev/null
						fi
					done
					conf_stat=`${HACLUS} -value ReadOnly`
					if [ ${conf_stat} -eq 0 ];then
						${ECHO} "\n--> Saving Cluster Configuration"
						${HACONF} -dump -makero
						sleep 3
					fi
				fi
			done

			sleep 2
			${HAGRP} -online Network -sys ${own_name}
			sleep 5
			
			${HAGRP} -state Network -sys ${own_name} 2>/dev/null | grep "ONLINE" > /dev/null 2>&1
			[ $? -ne 0 ] && log " [ERROR] : State of Network group is not clean. Please clean the state and retry"				
		fi
	else
		
		${ECHO} "\n Adding Network Service group to Cluster Configuration"
		conf_stat=`${HACLUS} -value ReadOnly`
		if [ ${conf_stat} -eq 1 ];then
			${ECHO} "\n--> Making Cluster Configuration RE-Writable"
			${HACONF} -makerw
			sleep 3
		fi
		
		${HAGRP} -add Network >/dev/null 2>&1
		${HAGRP} -modify Network SystemList ${own_name} 0 2>/dev/null
		${HAGRP} -autoenable Network -sys ${own_name} 2>/dev/null
		${HAGRP} -modify Network AutoStartList ${own_name} 2>/dev/null
		${HAGRP} -modify Network Parallel 1 2>/dev/null
		${HARES} -add Phantom Phantom  Network >/dev/null 2>&1
		${HARES} -modify Phantom Enabled 1

		## Dump configuration
		conf_stat=`${HACLUS} -value ReadOnly`
		if [ ${conf_stat} -eq 0 ];then
			${ECHO} "\n--> Saving Cluster Configuration"
			${HACONF} -dump -makero
			sleep 3
		fi
	fi
	
	### Determine number of bonds formed on the system
	## Either ONM or Traffic
	
	no_of_bonds=`cat /etc/modprobe.d/bond.conf | grep bond | wc -l`
	for bond_name in `cat /etc/modprobe.d/bond.conf | awk '{print $2}'`
	do
		IPADDR="X.X.X.X"
		IPV6ADDR="X:X:X"
		unset GATEWAY NETMASK other_hosts res_name ipv6addr_only
		source /etc/sysconfig/network-scripts/ifcfg-${bond_name}
		rpm -q "cloud-init" >/dev/null 2>&1
		if [ $? -eq 0 ];then
			if [ "X$BOOTPROTO" = "Xdhcp" ]; then
				IPADDR=`ifconfig ${bond_name} | awk '/netmask/ {print $2}'`
				NETMASK=`ifconfig ${bond_name} | awk '/netmask/ {print $4}'`
			fi
		fi
		[ ! -z $IPV6ADDR ] && ipv6addr_only=`echo ${IPV6ADDR} | awk -F/ '{print $1}'` && prefix=`echo ${IPV6ADDR} | awk -F/ '{print $2}'`

		cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | egrep "${IPADDR}|${ipv6addr_only}" | grep -qi "ONM"
		[ $? -eq 0 ] && {
			res_name="MM_ONM_NIC"
			other_hosts=$other_hosts_ONM
			[ "X${GATEWAY}" = "X" ] && GATEWAY=$default_gateway_ip_ONM
		}

		cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | egrep "${IPADDR}|${ipv6addr_only}" | grep -qi "Traffic"
		[ $? -eq 0 ] && {
			grep -wq "^bonding_interface_primary_Traffic" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} && res_name="MM_TRF_NIC"
			other_hosts=$other_hosts_Traffic
			[ "X${GATEWAY}" = "X" ] && GATEWAY=$default_gateway_ip_Traffic
		}

		if [ "X${res_name}" = "X" ]; then
			${ECHO} " [ERROR] : Could not determine resource name. Exiting!!"
			exit 606
		fi
		
		## Check if the same resource is already present or not
		${HARES} -list | grep -q ${res_name}
		if [ $? -eq 0 ]; then
			## If resource already exists, check the state
			${HARES} -state ${res_name} -sys ${own_name} 2> /dev/null | grep -q "ONLINE"
			if [ "$?" -ne 0 ]; then
				log "	[ERROR]	: Resource ${res_name} is not clean. Please clear the fault on resource and retry"
				exit 206
			else
				configure_ipv4=0
				# Check IPv4 is ok
				if [ "${IPADDR}" != "X.X.X.X" ]; then
					${HARES} -display ${res_name} -attribute Device| grep -q ${IPADDR}
					if [ $? -ne 0 ]; then
						conf_stat=`${HACLUS} -value ReadOnly`
						if [ ${conf_stat} -eq 1 ];then
							${ECHO} "\n--> Making Cluster Configuration RE-Writable"
							${HACONF} -makerw
							sleep 3
						fi
						${HARES} -modify ${res_name} Device ${bond_name} ${IPADDR} -sys ${own_name}
						#Is IPv4 Network Host added or not
						check_success=0
						for check_ipv4 in `${HARES} -display ${res_name} -attribute  NetworkHosts|grep -v '^#'| awk '{for(i=4;i<=NF;++i)print $i}'`
						do 
							ping -c1 $check_ipv4 > /dev/null 2>&1
							[ $? -eq 0 ] && check_success=1
						done

						[ "${check_success}" -ne 1 ] && {
							input_additional_network_ipv4 
							${HARES} -modify ${res_name} NetworkHosts -add "${other_hosts}" >/dev/null 2>&1
						}

						unset check_success
						conf_stat=`${HACLUS} -value ReadOnly`
						if [ ${conf_stat} -eq 0 ];then
							${ECHO} "\n--> Saving Cluster Configuration"
							${HACONF} -dump -makero
							sleep 3
						fi
					fi
					
					configure_ipv4=1
				fi
				
				# Check IPv6 is ok
				if [ "${IPV6ADDR}" != "X:X:X" ]; then
					ipv6addr_only=`echo ${IPV6ADDR} | awk -F/ '{print $1}'`
					rpm -q "cloud-init" >/dev/null 2>&1
					if [ $? -eq 0 ]; then
						prefix=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^netmask_Traffic=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
					else
						prefix=`echo ${IPV6ADDR} | awk -F/ '{print $2}'`
					fi
					${HARES} -display ${res_name} -attribute ArgListValues -sys ${own_name} 2> /dev/null | grep -q ${ipv6addr_only}
					if [ $? -ne 0 ]; then
						conf_stat=`${HACLUS} -value ReadOnly`
						if [ ${conf_stat} -eq 1 ];then
							${ECHO} "\n--> Making Cluster Configuration RE-Writable"
							${HACONF} -makerw
							sleep 3
						fi
						if [ "${configure_ipv4}" -eq 1 ]; then
							# If ipv4 is configured then configure as DualDevice
							${HARES} -local ${res_name} DualDevice
							${HARES} -modify ${res_name} DualDevice -add ${bond_name} ${ipv6addr_only} -sys ${own_name} >/dev/null 2>&1
						else
							# If ipv4 is not configured then configure as Device
							${HARES} -local ${res_name} Device
							${HARES} -modify ${res_name} Device -add ${bond_name} ${ipv6addr_only} -sys ${own_name} >/dev/null 2>&1
						fi

						${HARES} -modify ${res_name} PrefixLen ${prefix}
						check_success=0
						for check_ipv6 in `${HARES} -display ${res_name} -attribute  NetworkHosts | grep -v '^#' | awk '{for(i=4;i<=NF;++i)print $i}'`
						do 
							ping6 -c1 $check_ipv6 > /dev/null 2>&1
							[ $? -eq 0 ] && check_success=1
						done

						[ "${check_success}" -ne 1 ] && {
							input_additional_network_ipv6 
							${HARES} -modify ${res_name} NetworkHosts -add "${other_hosts}" >/dev/null 2>&1
						}

						unset check_success
						conf_stat=`${HACLUS} -value ReadOnly`
						if [ ${conf_stat} -eq 0 ];then
							${ECHO} "\n--> Saving Cluster Configuration"
							${HACONF} -dump -makero
							sleep 3
						fi
					fi
				else
					${HARES} -display ${res_name} -attribute DualDevice -sys ${own_name} > /dev/null 2>&1
					[ $? -eq 0 ] && {
						conf_stat=`${HACLUS} -value ReadOnly`
						if [ ${conf_stat} -eq 1 ];then
							${ECHO} "\n--> Making Cluster Configuration RE-Writable"
							${HACONF} -makerw
							sleep 3
						fi

						${HARES} -modify MM_ONM_NIC DualDevice -delete -keys >/dev/null 2>&1
						for check_ipv6 in `${HARES} -display ${res_name} -attribute  NetworkHosts|grep -v '^#'| awk '{for(i=4;i<=NF;++i)print $i}'`
						do 
							ping6 -c1 ${check_ipv6} >/dev/null 2>&1
							[ $? -eq 0 ] && ${HARES} -modify ${res_name} NetworkHosts -delete "${check_ipv6}" >/dev/null 2>&1
						done

						conf_stat=`${HACLUS} -value ReadOnly`
						if [ ${conf_stat} -eq 0 ];then
							${ECHO} "\n--> Saving Cluster Configuration"
							${HACONF} -dump -makero
							sleep 3
						fi
					}
				fi
			fi

			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 0 ];then
				${ECHO} "\n--> Saving Cluster Configuration"
				${HACONF} -dump -makero
				sleep 3
			fi
		else
			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 1 ];then
				${ECHO} "\n--> Making Cluster Configuration RE-Writable"
				${HACONF} -makerw
				sleep 3
			fi

			${HARES} -add ${res_name} MultiNICA Network >/dev/null 2>&1
			${HARES} -modify ${res_name} Enabled 1 >/dev/null 2>&1
			configure_ipv4=0

			if [ "${IPADDR}" != "X.X.X.X" ]; then
				## If ipv6 address exists in bond then add Device
				input_additional_network_ipv4
				${HARES} -local ${res_name} Device
				${HARES} -modify ${res_name} NetMask ${NETMASK}
				${HARES} -modify ${res_name} Device -add ${bond_name} ${IPADDR} -sys ${own_name} >/dev/null 2>&1
				BCast_IP=`ifconfig ${bond_name} | grep broadcast | awk '{print $NF}'`
				if [ "X${GATEWAY}" = "X" ]; then
					${HARES} -modify ${res_name} Options "broadcast ${BCast_IP}"
				else
					${HARES} -modify ${res_name} IPv4AddrOptions "broadcast ${BCast_IP}"
					[ ${res_name} = "MM_ONM_NIC" ] && ${HARES} -modify ${res_name} IPv4RouteOptions "default via ${GATEWAY}"
				fi
				
				${HARES} -modify ${res_name} NetworkHosts -add "${other_hosts}" >/dev/null 2>&1
				configure_ipv4=1
			fi

			if [ "${IPV6ADDR}" != "X:X:X" ]; then
				## If ipv6 address exists in bond then add Device
				input_additional_network_ipv6
				ipv6addr_only=`echo ${IPV6ADDR} | awk -F/ '{print $1}'`
				rpm -q "cloud-init" >/dev/null 2>&1
				if [ $? -eq 0 ]; then
					prefix=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^netmask_Traffic=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
				else
					prefix=`echo ${IPV6ADDR} | awk -F/ '{print $2}'`
				fi
				if [ "${configure_ipv4}" -eq 1 ]; then
					${HARES} -local ${res_name} DualDevice
					${HARES} -modify ${res_name} DualDevice -add ${bond_name} ${ipv6addr_only} -sys ${own_name} >/dev/null 2>&1
				else
					${HARES} -local ${res_name} Device
					${HARES} -modify ${res_name} Device -add ${bond_name} ${ipv6addr_only} -sys ${own_name} >/dev/null 2>&1
				fi
				${HARES} -modify ${res_name} PrefixLen ${prefix}
				${HARES} -modify ${res_name} NetworkHosts -add "${other_hosts}" >/dev/null 2>&1
			fi

			
			## Dump configuration
			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 0 ];then
				${ECHO} "\n--> Saving Cluster Configuration"
				${HACONF} -dump -makero
				sleep 3
			fi
		fi
		route -n | grep -w ${bond_name} | grep -wq UG
		if [ $? -ne 0 ]; then
		[ "X${GATEWAY}" != "X" ] && [ "${res_name}" = "MM_ONM_NIC" ] && ip route add default via ${GATEWAY}  dev ${bond_name} 2> /dev/null
		fi
	done

	log "\n--> Network configuration has been updated"
	[ "X${CONFIGMODE}" != "X" ] && update_status "Network_Service_Group=Y"

}

input_additional_network_ipv4()
{
	if [ "${IPADDR}" != "X.X.X.X" ]; then
			
		ask_for_address="no"

		if [ "X${other_hosts}" != "X" ]; then
			# DevOps Lab: bond not pingable
			#ping -c1 -I ${bond_name} ${other_hosts} > /dev/null 2>&1
			ping -c1 ${other_hosts} > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				[ "X${other_host_exception}" != "Xy" ] && ask_for_address="yes"
			fi
		else
			ask_for_address="yes"
		fi
		if [ "${ask_for_address}" == "yes" ]; then

			log "\n--> Enter a valid IPv4 address of any other host on network for ${res_name}: \c"
			correct_inp=1
			while [ ${correct_inp} = 1 ]; do
				read other_hosts
				# Check if host is reachable or not
				# DevOps Lab: bond not pingable
				#ping -c2 -I ${bond_name} ${other_hosts} > /dev/null 2>&1
				ping -c2 ${other_hosts} > /dev/null 2>&1
				if [ $? -eq 0 ]; then
					export other_hosts
					correct_inp=0
				else
					log "\n--> Could not reach the IP Address via ${bond_name}. Please re-enter: \c"
					
				fi
			done
		fi
	fi
}

input_additional_network_ipv6()
{
	if [ "${IPV6ADDR}" != "X:X:X" ]; then
		ask_for_address="no"

		if [ "X${other_hosts}" != "X" ]; then
			ping6 -c2 -I ${bond_name} ${other_hosts}  > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				ask_for_address="yes"
			fi
		else
			ask_for_address="yes"
		fi
		if [ "${ask_for_address}" == "yes" ]; then

			log "\n--> Enter a valid IPv6 address of any other host on network for ${res_name} : \c"
			correct_inp=1
			while [ ${correct_inp} = 1 ]; do
				read other_hosts
				# Check if host is reachable or not
				ping6 -c2 -I ${bond_name} ${other_hosts}  > /dev/null 2>&1
				if [ $? -eq 0 ]; then
					export other_hosts
					correct_inp=0
				else
					log "\n--> Could not reach the IPv6 Address via ${bond_name}. Please re-enter: \c"
				fi
			done
		fi
	fi

}

#--------------------------------#
# Function to control VCS        #
#--------------------------------#
VCS_Control()
{
	case ${1} in
		start) ${HASTART} ;;
		stopall) ${HASTOP} -all ;;
		stopforce) ${HASTOP} -all -force ;;
		status) ${HASTATUS} -sum ;;
	esac


}

#-----------------------------------#
# Function to validate CFS template #
#-----------------------------------#
Validate_CFS_Template()
{
	#---------------------------------------#
	# Check the correctness for the HB links#
	#---------------------------------------#
	export CURRENT_HOST=`hostname -s`
	
	for HB_nic in `cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^HeartBeat_Link" | awk -F"=" '{ print $NF }' | sed 's/"//g'`
	do
		ifconfig -a | awk '{print $1}' | grep -q ${HB_nic}
		[ $? -ne 0 ] && { 
			${ECHO} "\n [ ERROR ] : NIC : ${HB_nic} is not a valid interface on HOST : `hostname -s`, Please check ...."
			exit 1
		}
	done

	n1hb1=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^HeartBeat_Link" | awk -F"=" '{ print $NF }' | head -1`
	n1hb2=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^HeartBeat_Link" | awk -F"=" '{ print $NF }' | tail -1`
	
	uniqcount=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | egrep "^HeartBeat_Link|^bonding_interface_primary|^bonding_interface_standby" | awk -F"=" '{ print $NF }' | uniq -d | wc -l`
	
	if [ $uniqcount -gt 0 ] ;then
		${ECHO} "\n [ ERROR ] : Heartbeat Link(s) cannot be same as bonding ONM or Traffic Interface for a node. Please check .."
		exit 1
	fi
	
	if [ "X${n1hb1}" = "X${n1hb2}" ] ;then
		${ECHO} "\n [ ERROR ] : Heartbeat Link(s) cannot be same for a node. Please check .."
		exit 1
	fi
	export Cluster_Name=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^Cluster_Name=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
	export Cluster_ID=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^Cluster_ID=" | awk -F"=" '{print $NF}' | sed 's/"//g'`

	if [ `echo ${Cluster_Name} | wc -w` -ne 1 ]; then
		${ECHO} "\n [ ERROR ] : Cluster Name can not have Space. Please check .."
		exit 1
	fi
	
	sed -i -e "s/_START=.*/_START=1/g" -e "s/_STOP=.*/_STOP=1/g" /etc/sysconfig/llt >/dev/null 2>&1

	[ ! -s /etc/llthosts ] && ${ECHO} "0 ${CURRENT_HOST}" > /etc/llthosts

	{
	${ECHO}  "set-node ${CURRENT_HOST}"
	${ECHO}  "set-cluster ${Cluster_ID}"
	} > /etc/llttab

	for link in ${n1hb1} ${n1hb2}
	do
		interfaceid=`echo ${link} | grep -E -o "[0-9]+" | tail -1`
		interface=`echo ${link} | sed "s/${interfaceid}$//"`
		interfacemac=`ip link show ${link} | grep ether | awk '{print $2}'`

		# Set MTU value to 1200 in case of cloud environment
		rpm -q cloud-init >/dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "link ${link} eth-${interfacemac} - ether - 1200" >> /etc/llttab
		else
			echo "link ${link} eth-${interfacemac} - ether - -" >> /etc/llttab
		fi
	done

	systemctl start llt >/dev/null 2>/var/tmp/llttest

	if [ $(/usr/sbin/lltstat -nvv configured  | egrep "${n1hb1}.*UP|${n1hb2}.*UP" | wc -l) -lt 2 ];then
		${ECHO} "\n [ ERROR ] : LLT test failed using the provided entry for Cluster ID ${Cluster_ID} and Heartbeat Links"
		if [ -s /var/tmp/llttest ];then
			cat /var/tmp/llttest | grep ERROR
			rm -f /var/tmp/llttest
		fi

		exit 1
	fi

	DGW_IP=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^default_gateway_ip_ONM=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
	OTH_HOST_ONM=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^other_hosts_ONM=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
	BONDING_IP_ONM=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^bonding_interface_ip_ONM=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
	BONDING_IP_TRF=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^bonding_interface_ip_Traffic=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
	BONDING_NETMASK_TRF=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^netmask_Traffic=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
	OTH_HOST_TRF=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^other_hosts_Traffic=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
	DGW_IP_TRF=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^default_gateway_ip_Traffic=" | awk -F"=" '{print $NF}' | sed 's/"//g'`

	if [ "X${CLOUD_SETUP}" = "XY" ];then
		export IO_FENCING_TYPE="CPS"
	else
		export IO_FENCING_TYPE=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^IO_Fencing_Type=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
	fi

	export NTP_Server_IP=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^NTP_Server_IP=" | awk -F"=" '{print $NF}' | sed 's/"//g'`

	if [ "X${DGW_IP}" = "X${OTH_HOST_ONM}" ]; then
		${ECHO} "\n [ ERROR ] : IP Address for default_gateway_ip_ONM and other_hosts_ONM parameters can not be same. Please check .."
		exit 1
	fi

	if [ "X${BONDING_IP_ONM}" = "X${OTH_HOST_ONM}" ]; then
		${ECHO} "\n [ ERROR ] : IP Address for bonding_interface_ip_ONM and other_hosts_ONM parameters can not be same. Please check .."
		exit 1
	fi

	if [ "X${BONDING_IP_TRF}" = "X${OTH_HOST_ONM}" ]; then
		${ECHO} "\n [ ERROR ] : IP Address for bonding_interface_ip_Traffic and other_hosts_ONM parameters can not be same. Please check .."
		exit 1
	fi

	/bin/ping -c 2 ${OTH_HOST_ONM} > /dev/null 2>&1
	if [ $? -ne 0 ];then
		/bin/ping -c 2 ${DGW_IP} > /dev/null 2>&1
		if [ $? -ne 0 ];then
			${ECHO} "\n [ ERROR ] : IP Address ${OTH_HOST_ONM} is not reachable.\n\t     Make sure the IP Address specified for other_hosts_ONM parameter is pingable from the system. Please check .."
			exit 1
		else
			${ECHO} "\n [ WARNING ] : IP Address ${OTH_HOST_ONM} is not reachable. Assuming that the ONM Other Host is shutdown or will be configured later"
			export other_host_exception="y"
			sleep 3
		fi
	fi

	if [ "X${DGW_IP_TRF}" != "X" ]; then
		TRF_NIC_P=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^bonding_interface_primary_Traffic=" | awk -F"=" '{print $NF}' | sed 's/"//g'`

		if [ "X${BONDING_IP_TRF}" = "X${DGW_IP_TRF}" ]; then
			${ECHO} "\n [ ERROR ] : IP Address for bonding_interface_ip_Traffic and default_gateway_ip_Traffic parameters can not be same. Please check .."
			exit 1
		fi

		if [ "X${DGW_IP_TRF}" = "X${OTH_HOST_TRF}" ]; then
			${ECHO} "\n [ ERROR ] : IP Address for default_gateway_ip_Traffic and other_hosts_Traffic parameters can not be same. Please check .."
			exit 1
		fi

		if [ "X" = "X${OTH_HOST_TRF}" ]; then
			${ECHO} "\n [ ERROR ] : IP Address for other_hosts_Traffic parameters can not be null. Please check .."
			exit 1
		else
			BND_TRF=$(/usr/bin/grep MASTER /etc/sysconfig/network-scripts/ifcfg-${TRF_NIC_P})
			if [ -n "${BND_TRF}" ];then
			   TRF_BND=$(/usr/bin/grep MASTER /etc/sysconfig/network-scripts/ifcfg-${TRF_NIC_P} | cut -d"=" -f2)
				rpm -q "cloud-init" >/dev/null 2>&1
				if [ $? -eq 0 ]; then
					/usr/bin/ipcalc -6c ${OTH_HOST_TRF} > /dev/null 2>&1
					if [ $? -eq 0 ]; then
						/usr/sbin/ping6 -c3 -I ${TRF_BND} ${OTH_HOST_TRF} >/dev/null 2>&1
						if [ $? -ne 0 ];then
							/usr/sbin/ping6 -c3 -I ${TRF_BND} ${DGW_IP_TRF} >/dev/null 2>&1
							[ $? -ne 0 ] && {
								${ECHO} "\n [ ERROR ] : IP Addresses ${OTH_HOST_TRF} and ${DGW_IP_TRF} are not reachable via ${TRF_BND} interface.\n\t     Make sure the IP Address specified for other_hosts_Traffic parameter is pingable from the system. Please check .."
								exit 1
							} || {
								${ECHO} "\n [ WARNING ] : IP Address ${OTH_HOST_TRF} is not reachable. Assuming that the Traffic Other Host is shutdown or will be configured later"
								export other_host_exception="y"
								sleep 3
							}
						fi
					else
						/usr/bin/ipcalc -4c ${OTH_HOST_TRF} > /dev/null 2>&1
						if [ $? -eq 0 ];then
							/usr/bin/ping -c3 -I ${TRF_BND} ${OTH_HOST_TRF} >/dev/null 2>&1
							if [ $? -ne 0 ];then
								/usr/bin/ping -c3 -I ${TRF_BND} ${DGW_IP_TRF} >/dev/null 2>&1
								[ $? -ne 0 ] && {
									${ECHO} "\n [ ERROR ] : IP Addresses ${OTH_HOST_TRF} and ${DGW_IP_TRF} are not reachable via ${TRF_BND} interface.\n\t     Make sure the IP Address specified for other_hosts_Traffic parameter is pingable from the system. Please check .."
									exit 1
								} || {
									${ECHO} "\n [ WARNING ] : IP Address ${OTH_HOST_TRF} is not reachable. Assuming that the Traffic Other Host is shutdown or will be configured later"
									export other_host_exception="y"
									sleep 3
								}
							fi
						else
							${ECHO} "\n [ ERROR ] : IP Addresses ${OTH_HOST_TRF} is not a valid IP address.\n\t     Make sure the IP Address specified for other_hosts_Traffic parameter is valid IP address. Please check .."
							exit 1
						fi
					fi
				else
					/usr/sbin/arping -b -f -c2 -w 10 -s ${BONDING_IP_TRF} -D -I  ${TRF_BND} ${OTH_HOST_TRF} >/dev/null 2>&1
					if [ $? -eq 0 ];then
						/usr/sbin/arping -b -f -c2 -w 10 -s ${BONDING_IP_TRF} -D -I  ${TRF_BND} ${DGW_IP_TRF} >/dev/null 2>&1
						[ $? -eq 0 ] && {
							${ECHO} "\n [ ERROR ] : IP Addresses ${OTH_HOST_TRF} and ${DGW_IP_TRF} are not reachable via ${TRF_NIC_P} interface.\n\t     Make sure the IP Address specified for other_hosts_Traffic parameter is pingable from the system. Please check .."
							exit 1
						} || {
							${ECHO} "\n [ WARNING ] : IP Address ${OTH_HOST_TRF} is not reachable. Assuming that the Traffic Other Host is shutdown or will be configured later"
							export other_host_exception="y"
							sleep 3
						}
					fi
				fi
			else
				if [ "X${CLOUD_SETUP}" = "XY" ]; then
					/usr/bin/ipcalc -6c ${OTH_HOST_TRF} > /dev/null 2>&1
					if [ $? -eq 0 ]; then
						/usr/sbin/ping6 -c3 -I ${TRF_NIC_P} ${OTH_HOST_TRF} >/dev/null 2>&1
						if [ $? -ne 0 ];then
							/usr/sbin/ping6 -c3 -I ${TRF_NIC_P} ${DGW_IP_TRF} >/dev/null 2>&1
							[ $? -ne 0 ] && {
								${ECHO} "\n [ ERROR ] : IP Addresses ${OTH_HOST_TRF} and ${DGW_IP_TRF} are not reachable via ${TRF_NIC_P} interface.\n\t     Make sure the IP Address specified for other_hosts_Traffic parameter is pingable from the system. Please check .."
								exit 1
							} || {
								${ECHO} "\n [ WARNING ] : IP Address ${OTH_HOST_TRF} is not reachable. Assuming that the Traffic Other Host is shutdown or will be configured later"
								export other_host_exception="y"
								sleep 3
							}
						fi
					else
						/usr/bin/ipcalc -4c ${OTH_HOST_TRF} > /dev/null 2>&1
						if [ $? -eq 0 ];then
							/usr/bin/ping -c3 -I ${TRF_NIC_P} ${OTH_HOST_TRF} >/dev/null 2>&1
							if [ $? -ne 0 ];then
								/usr/bin/ping -c3 -I ${TRF_NIC_P} ${DGW_IP_TRF} >/dev/null 2>&1
								[ $? -ne 0 ] && {
									${ECHO} "\n [ ERROR ] : IP Addresses ${OTH_HOST_TRF} and ${DGW_IP_TRF} are not reachable via ${TRF_NIC_P} interface.\n\t     Make sure the IP Address specified for other_hosts_Traffic parameter is pingable from the system. Please check .."
									exit 1
								} || {
									${ECHO} "\n [ WARNING ] : IP Address ${OTH_HOST_TRF} is not reachable. Assuming that the Traffic Other Host is shutdown or will be configured later"
									export other_host_exception="y"
									sleep 3
								}
							fi
						else
							${ECHO} "\n [ ERROR ] : IP Addresses ${OTH_HOST_TRF} is not a valid IP address.\n\t     Make sure the IP Address specified for other_hosts_Traffic parameter is valid IP address. Please check .."
							exit 1
						fi
					fi
				else
					
					
					traffic_ip_nw_id=`/usr/bin/ipcalc ${BONDING_IP_TRF} ${BONDING_NETMASK_TRF} -n 2>/dev/null | grep "NETWORK=" | awk -F"=" '{print $2}' | head -1`

					ip -4 addr show 2>/dev/null | grep -w "${BONDING_IP_TRF}/${traffic_ip_nw_id}" >/dev/null 2>&1
					[ $? -ne 0 ] && ip address add ${BONDING_IP_TRF}/${traffic_ip_nw_id} dev ${TRF_NIC_P} >/dev/null 2>&1

					ifconfig ${TRF_NIC_P} up >/dev/null 2>&1
					/usr/sbin/arping -b -f -c2 -w 10 -s ${BONDING_IP_TRF} -D -I  ${TRF_NIC_P} ${OTH_HOST_TRF} >/dev/null 2>&1
					if [ $? -eq 0 ];then
						/usr/sbin/arping -b -f -c2 -w 10 -s ${BONDING_IP_TRF} -D -I ${TRF_NIC_P} ${DGW_IP_TRF} >/dev/null 2>&1
						[ $? -eq 0 ] && {
							${ECHO} "\n [ ERROR ] : IP Addresses ${OTH_HOST_TRF} and ${DGW_IP_TRF} are not reachable via ${TRF_NIC_P} interface.\n\t     Make sure the IP Address specified for other_hosts_Traffic parameter is pingable from the system. Please check .."
							exit 1
						} || {
							${ECHO} "\n [ WARNING ] : IP Address ${OTH_HOST_TRF} is not reachable. Assuming that the Traffic Other Host is shutdown or will be configured later"
							export other_host_exception="y"
							sleep 3
						}
					fi
				fi
			fi
		fi

		if [ "X${BONDING_IP_TRF}" = "X${OTH_HOST_TRF}" ]; then
			${ECHO} "\n [ ERROR ] : IP Address for bonding_interface_ip_Traffic and other_hosts_Traffic parameters can not be same. Please check .."
			exit 1
		fi
	fi

	if [ "X${FSTYPE}" = "XNFS" ];then
		export CONFIG_DG="NODG"
		#########################
		#CLOUD_NFS
		#########################
		
		NFS_Ver_MMDB=`grep "^NFS_Server_Version_for_MMDB=" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | awk -F '=' '{ print $2}'`
		NFS_Ver_MMStorage=`grep "^NFS_Server_Version_for_MMStorage=" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | awk -F '=' '{ print $2}'`
		MMDB_Share_IP=`grep "^NFS_Share_IP_for_MMDB=" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | awk -F '=' '{ print $2}'`
		MMStorage_Share_IP=`grep "^NFS_Share_IP_for_MMStorage=" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | awk -F '=' '{ print $2}'`
		MMDB_Share_Name=`grep "^MMDB_NFS_Share_Name=" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | awk -F '=' '{ print $2}'`
		MMStorage_Share_Name=`grep "^MMStorage_NFS_Share_Name=" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | awk -F '=' '{ print $2}'`
                MMDB_Share_Name=`readlink -fm $MMDB_Share_Name`
                MMStorage_Share_Name=`readlink -fm $MMStorage_Share_Name`
            
		if [ "X${NFS_Ver_MMDB}" = "Xnfs" ] || [ "X${NFS_Ver_MMStorage}" = "Xnfs" ];then
			systemctl enable rpcbind.service >/dev/null 2>&1
			systemctl start rpcbind.service >/dev/null 2>&1
			systemctl enable rpcbind.socket >/dev/null 2>&1
			systemctl start rpcbind.socket >/dev/null 2>&1
			systemctl enable nfslock >/dev/null 2>&1
			systemctl start nfslock >/dev/null 2>&1
		fi

		mkdir -p --mode=u+rwx,g+rxs,o+rx ${MMDB_DIR} ${STORAGE_DIR} 2>/dev/null
		MMStorage_DIR=${STORAGE_DIR}
		for mountPoint in MMDB MMStorage ; do
			NFS_Share_IP=$(eval echo "\$$mountPoint"_Share_IP)
			NFS_Share_Name=$(eval echo "\$$mountPoint"_Share_Name)
			NFS_Server_Version=$(eval echo NFS_Ver_"\$$mountPoint")
			NFS_Mount_Path=$(eval echo "\$$mountPoint"_DIR)
			if [ "X${NFS_Server_Version}" == "Xnfs" ];then
				nvers=3
			else
				nvers=4.0
			fi

			${ECHO} "\nValidating NFS share for ${mountPoint}..."; sleep 1
			# check for file permission on nfs
			timeout --preserve-status 30s mount -t nfs -o vers=${nvers},tcp ${NFS_Share_IP}:${NFS_Share_Name} ${NFS_Mount_Path} >/dev/null 2>&1
			if [ $? -ne 0 ]; then
				${ECHO} "\n [ERROR]: Unable to mount NFS share ${NFS_Share_IP}:${NFS_Share_Name}\n\nExiting...\n"
				exit 1
			else
				touch ${NFS_Mount_Path}/testfile > /dev/null 2>&1
				if [ $? -ne 0 ]; then
					${ECHO} "\n [ERROR] : NFS share ${NFS_Share_IP}:${NFS_Share_Name} does not have the proper permission.\n\nExiting...\n"
					umount ${NFS_Mount_Path} 2>/dev/null
					exit 1
				else
					rm -f ${NFS_Mount_Path}/testfile
					if [ $mountPoint = "MMDB" ]; then
						MMDB_FREE_SPACE=`df -h ${NFS_Mount_Path} | tail -1 | awk '{print $4}'`
					else
						MMSTORAGE_FREE_SPACE=`df -h ${NFS_Mount_Path} | tail -1 | awk '{print $4}'`
					fi
					umount ${NFS_Mount_Path} 2>/dev/null
				fi
			fi
		done

		grep -q "=Y$" ${PRODUCT_INSTALL_STATUS_FILE} >/dev/null 2>&1
		if [ $? -ne 0 ];then
			${ECHO} "\n\n--------------------------------------------------------------"
			${ECHO} "For Cluster setup, following NFS Shares will be configured :"
			${ECHO} "--------------------------------------------------------------\n"
			${ECHO} "MOUNT POINT \t\t\t\t NFS SHARE \t\t\t Free Space \t\t\t NFS Version"
			${ECHO} "*********** \t\t\t\t ********* \t\t\t ********** \t\t\t ***********\n"
			${ECHO} "${MMDB_DIR} \t\t $MMDB_Share_IP:$MMDB_Share_Name \t\t ${MMDB_FREE_SPACE} \t\t\t ${NFS_Ver_MMDB}"
			${ECHO} "${STORAGE_DIR} \t\t $MMStorage_Share_IP:$MMStorage_Share_Name \t\t ${MMSTORAGE_FREE_SPACE} \t\t\t ${NFS_Ver_MMStorage}\n"
			yorn "Is it ok to continue ? (y/n) : "
		fi
	fi
}


#-------------------------------------------#
# Function to Validate Cluster related info #
# in the Add Node Template.		    #
#-------------------------------------------#
Validate_Template_Add_Node()
{

	CURRENT_HOST=`hostname -s`
	export rem_clus_host=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^Clus_Node_IP" | ${AWK} -F"=" '{ print $2 }' | sed 's/\"//g'`
	
	[ "X${rem_clus_host}" = "X" ] && {
		${ECHO} "\n [ ERROR ] : Remote Host cannot be blank. Please check the value"
		exit 1
	}
	
	CURR_HOST_IP=$(/usr/bin/gethostip -d `hostname -s` 2>/dev/null)
	[ "X${CURR_HOST_IP}" = "X${rem_clus_host}" ] && {
		${ECHO} "\n [ ERROR ] : IP Address of Remote Host and IP of `hostname -s` can not be same"
		exit 1
	}

	check_same_network_Platform STDALONE ${CURR_HOST_IP} ${rem_clus_host}
	if [ $? -ne 0 ];then
		${ECHO} "\n [ ERROR ] : IP Address of Remote Host and `hostname -s` should be on Same Network"
		exit 1
	fi

	no_of_hb_rec=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^HeartBeat_Link" | wc -l`
	if [ ${no_of_hb_rec} -ne 2 ];then
		${ECHO} "\n [ ERROR ] : There should be exact two Heartbeat Records. Please check the value" 
		exit 1
	fi 

	export Nhb1=`grep "^HeartBeat_Link_1" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | awk -F'=' '{ print $NF }' | sed 's/"//g'`
	export Nhb2=`grep "^HeartBeat_Link_2" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | awk -F'=' '{ print $NF }' | sed 's/"//g'`
	
	uniqcount=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | egrep "^HeartBeat_Link|^bonding_interface_primary|^bonding_interface_standby" | awk -F"=" '{ print $NF }' | uniq -d | wc -l`
	
	if [ $uniqcount -gt 0 ] ;then
		${ECHO} "\n [ ERROR ] : Heartbeat Link(s) cannot be same as bonding ONM or Traffic Interface for a node."
		exit 1
	fi

	if [ "X${Nhb1}" = "X${Nhb2}" ] ;then
		${ECHO} "\n [ ERROR ] : Heartbeat Links cannot be same."
		exit 1
	fi

	if [ "X${Nhb1}" = "X" ] || [ "X${Nhb2}" = "X" ];then
		${ECHO} "\n [ ERROR ] : Heartbeat Links cannot be blank."
		exit 1
	fi

	#---------------------------------------#
	# Check for Valid interface on the host #
	#---------------------------------------#
	for iface in ${Nhb1} ${Nhb2}
	do 
		ip addr | grep "[1-9]:\ ${iface}:" > /dev/null 2>&1
		if [ $? -ne 0 ];then
			${ECHO} "\n [ ERROR ] : Heartbeat Interface : ${iface} does not exist."
			exit 1
		fi
	done
	rpm -q VRTSvxvm >/dev/null 2>&1
	if [ $? -eq 0 ];then
		/usr/sbin/vxddladm get namingscheme | grep -i "Enclosure" >/dev/null 2>&1
		if [ $? -ne 0 ]; then
			/usr/sbin/vxddladm set namingscheme=ebn persistence=yes
		fi
	fi

	ssh_keyless_platform
	export rem_clus_hostname=`${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "hostname"`

	grep -v "^#" ${PRODUCT_INSTALL_STATUS_FILE}  | grep "=N$" >/dev/null 2>&1
	[ $? -ne 0 ] && {
		${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} ${HAGRP} -list" | grep -w cvm >/dev/null 2>&1
		[ $? -ne 0 ] && export CONFIG_DG="NODG"
		return 1
	}

	${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/bin/cat /opt/VRTS/install/installer" | grep -wq ${VRTS_PROD_TYPE}
	[ $? -ne 0 ] && {
		${ECHO} "\n[ ERROR ] : Veritas Product SW installation (${VRTS_PROD_TYPE}) is not same on ${CURRENT_HOST} and ${rem_clus_hostname}"
		exit 1
	}

	# Check number of bonds on 1st node
	number_of_bonds=`${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/bin/cat /etc/modprobe.d/bond.conf | awk '{print $2}'" | wc -l`
	#Check number of bonds to be configured on 2nd Node
	sed -n "/^\[.*\<Traffic Bond\>\]/,/^\[/s/^[^[]/&/p" ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} > /tmp/bond.tmp
	
	source /tmp/bond.tmp
	rm -f /tmp/bond.tmp

	if [ "${number_of_bonds}" -gt 1 ]; then
		[ -z ${bonding_interface_primary_Traffic} ] && {
			log "\n[ERROR] : Traffic Bond must be configured. Exiting .."
			exit 501
		}
	fi

	log "\n--> Validating Heartbeat Link(s)"

	#--------------------------------------------#
	# Check to validate LLT links using dlpiping # 
	# utility offered by VERITAS		 #
	#--------------------------------------------#
	Lllt_links=""
	NOT_UP=0
	for link in $Nhb1 $Nhb2
	do
		interfaceid=`echo ${link} | grep -E -o "[0-9]+" | tail -1`
		interface=`echo ${link} | sed "s/${interfaceid}$//"`
		interfacemac=`ip addr | grep -A1 ${link} | grep ether | awk '{print $2}' | tr '[a-z]' '[A-Z]'`
		Lllt_links="${Lllt_links} ${interface}${interfaceid}"
		ifconfig ${link} | grep -i "RUNNING" > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			ifconfig ${link} up
			NOT_UP=`expr ${NOT_UP} + 1`
		fi
	done
	sleep 2

	Rllt_links=`${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/bin/cat /etc/llttab" |grep -v link-lowpri | grep "^link" |awk '{print $2}'`
	Llink=`echo ${Lllt_links} | awk '{ print $1 }'`
	lmac=`ip addr | grep -A1 ${Llink} | grep ether | awk '{print $2}' | tr '[a-z]' '[A-Z]'`
	${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/sbin/ifconfig ${Llink} up" >/dev/null 2>&1

	/opt/VRTSllt/dlpiping -s ${Llink} >/dev/null 2>&1 &
	dlpid=`echo $!`
	Rlink=`echo ${Rllt_links} | awk '{ print $1 }'`
	${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /opt/VRTSllt/dlpiping -t 40 -c ${Rlink} ${lmac}" | grep "alive" > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		Rllt_links=`echo ${Rllt_links} | awk '{ print $2 }'`
		kill -9 ${dlpid} > /dev/null 2>&1
	else
		Rlink=`echo ${Rllt_links} | awk '{ print $2 }'`
		${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /opt/VRTSllt/dlpiping -t 40 -c ${Rlink} ${lmac}"|grep "alive" >/dev/null 2>&1
		if [ $? -eq 0 ]; then
			Rllt_links=`echo ${Rllt_links} | awk '{ print $1 }'`
			kill -9 ${dlpid} > /dev/null 2>&1
		else
			${ECHO} "\n [ ERROR ] : Check the Heartbeat Link specified in the template : `echo ${Llink} | awk -F"/" '{print $NF}' |tr -d ':'`"
			${ECHO} " May be the wrong links specified or link connections are faulty"
			kill -9 ${dlpid} > /dev/null 2>&1
			exit 1 
		fi
	fi

	Llink=`echo ${Lllt_links} | awk '{ print $2 }'`
	lmac=`ip addr | grep -A1 ${Llink} | grep ether | awk '{print $2}' | tr '[a-z]' '[A-Z]'`
	${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /usr/sbin/ifconfig ${Llink} up" >/dev/null 2>&1

	/opt/VRTSllt/dlpiping -s ${Llink} >/dev/null 2>&1 &
	dlpid=`echo $!`
	
	${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} /opt/VRTSllt/dlpiping -t 40 -c ${Rllt_links} ${lmac}" | grep "alive" >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		kill -9 ${dlpid} > /dev/null 2>&1
	else
		${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO}  /usr/sbin/ifconfig ${Rllt_links} down"
		${ECHO} "\n [ ERROR ] : Check the Heartbeat Link specified in the template : `echo ${Llink} | awk -F"/" '{print $NF}' |tr -d ':'`"
		${ECHO} " May be the wrong links specified or link connections are faulty"
		kill -9 ${dlpid} > /dev/null 2>&1
		exit 1 
	fi

	for link in $Nhb1 $Nhb2
	do
		if [ "${NOT_UP}" -gt 0 ]; then
			ifconfig ${link} down
		fi
	done

	${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} ${HAGRP} -state -sys ${rem_clus_hostname}" | grep -w cvm >/dev/null 2>&1
	[ $? -ne 0 ] && export CONFIG_DG="NODG"

	${SSH} ${CURRENT_USER_NAME}@${rem_clus_host} "${SUDO} ${HAGRP} -state -sys ${rem_clus_hostname} 2>/dev/null" | grep -w "^${SG_CLOUD_NAME}" >/dev/null 2>&1
	[ $? -eq 0 ] && export FSTYPE="NFS"

}


#-----------------------------------------------------#
# Sync MM.config to all nodes in the cluster          #
#-----------------------------------------------------#
Sync_MM_CONFIG_CLUSTER()
{
	MYNAME=`hostname -s`
	count=0
	MM_FILE=`echo ${MM_CONFIG_FILE} | awk -F/ '{ print $NF }'`
	MM_FILE_PATH=`dirname ${MM_CONFIG_FILE}`
	[ -f /var/tmp/${MM_FILE}.tar ] && rm -f /var/tmp/${MM_FILE}.tar >/dev/null 2>&1
	tar -cf /var/tmp/${MM_FILE}.tar -C ${MM_FILE_PATH}/ ${MM_FILE} >/dev/null 2>&1
	chmod o+r /var/tmp/${MM_FILE}.tar >/dev/null 2>&1
	for HSTNAME in `${HASYS} -list | grep -vw "^${MYNAME}$"`
	do
		[ $count -eq 0 ] && ${ECHO} "\n--> Synchronizing ${MM_CONFIG_FILE} with other Cluster nodes  ..." && count=1
		${ECHO} "\t--> Copying ${MM_CONFIG_FILE} to ${HSTNAME}  ...\c"

		${SSH} ${CURRENT_USER_NAME}@${HSTNAME} "
		${SUDO} /usr/bin/test -f /var/tmp/${MM_FILE}.tar
		if [ \$? -eq 0 ];then
			${SUDO} /usr/bin/rm -f /var/tmp/${MM_FILE}.tar
		fi "  >/dev/null 2>&1
		
		${SCP} /var/tmp/${MM_FILE}.tar ${CURRENT_USER_NAME}@${HSTNAME}:/var/tmp/${MM_FILE}.tar >/dev/null 2>&1
		if [ $? -eq 0 ];then
			${SSH} ${CURRENT_USER_NAME}@${HSTNAME} "
			${SUDO} /usr/bin/tar -xf /var/tmp/${MM_FILE}.tar -C ${MM_FILE_PATH}/ 
			${SUDO} /usr/bin/rm -f /var/tmp/${MM_FILE}.tar " >/dev/null 2>&1
			${ECHO} "[OK]"
		else
			${ECHO} "[FAILED]\n\t\tPlease copy ${MM_CONFIG_FILE} manually to ${HSTNAME}"
		fi
	done
	rm -f /var/tmp/${MM_FILE}.tar >/dev/null 2>&1
}

#------------------------------#
# Function to Add Cluster Node #
#------------------------------#
Add_Cluster_Node()
{
	Func_Header "Adding New Node To Running Cluster" ${1} ${2}

	CURRENT_HOST=`hostname -s`
	export CURRENT_USER_NAME=`printenv SUDO_USER`
	[ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"
	CURRENT_HOST_IP=`hostname -i`
	export CURRENT_USER_HOME_DIR=`getent passwd ${CURRENT_USER_NAME} | awk -F: '{ print $(NF-1) }'`
	export CURRENT_USER_GID=`getent passwd ${CURRENT_USER_NAME} | awk -F: '{ print $(NF-3) }'`
	
	if [ ! -f ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys ];then
		touch ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys >/dev/null 2>&1
		chmod 600 ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys >/dev/null 2>&1
		chown ${CURRENT_USER_NAME}:${CURRENT_USER_GID} ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys >/dev/null 2>&1
	fi	
	
	${ECHO} ${CURRENT_HOST} > /etc/VRTSvcs/conf/sysname
	Clus_Node_IP=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^Clus_Node_IP" | ${AWK} -F'=' '{ print $2 }' | sed 's/\"//g'`
	Cluster_HOST=`${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "hostname -s" | head -1`
	Cluster_Name=`${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} ${HACLUS} -value ClusterName"`
	Cluster_ID=`${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} /usr/bin/cat /etc/llttab" | grep "^set-cluster" | awk '{print $2}'`
	clus_members=`${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} ${HASYS} -list"`

	${ECHO} "\n--> Copying Cluster Configuration Files from Host : ${Clus_Node_IP}\n"

	[ -f /var/tmp/pub_key ] && rm -f /var/tmp/pub_key >/dev/null 2>&1
	${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "sudo /usr/bin/cat \$HOME/.ssh/id_rsa.pub" >>/var/tmp/pub_key
	if [ -s /var/tmp/pub_key ];then
		PUB_KEY=`cat /var/tmp/pub_key | awk '{ print $2 }'`
		grep -wq ${PUB_KEY} ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys
		if [ $? -ne 0 ];then
			cat /var/tmp/pub_key >> ${CURRENT_USER_HOME_DIR}/.ssh/authorized_keys
			rm -f /var/tmp/pub_key >/dev/null 2>&1
		fi
	fi


	if [ "X${IO_FENCING_TYPE}" = "XCPS" ]; then
		clusfiles="${clusfiles} /etc/gabtab /etc/llthosts /etc/vxfenmode /etc/vxfentab /etc/sysconfig/vcs /etc/vx/.uuids/clusuuid"

		chmod +x /etc/rc.d/rc.local
		cp ${MISC_DIR}/cps_vxfen /etc/init.d/ > /dev/null 2>&1
		chmod 755 /etc/init.d/cps_vxfen > /dev/null 2>&1
		grep -w "cps_vxfen" /etc/rc.d/rc.local > /dev/null 2>&1
		[ $? -ne 0 ] && echo "/etc/init.d/cps_vxfen" >> /etc/rc.d/rc.local

	else
		clusfiles="${clusfiles} /etc/gabtab /etc/llthosts /etc/vxfendg /etc/vxfenmode /etc/sysconfig/vcs /etc/vx/.uuids/clusuuid"
	fi

	[ ! -d /etc/vx/.uuids ] && mkdir -p /etc/vx/.uuids >/dev/null 2>&1
	for filname in ${clusfiles}
	do
		log "\tCopying `basename ${filname}` from host : ${Clus_Node_IP}"
		File_Name=`echo ${filname} | awk -F/ '{ print $NF }'`
		File_Path=`dirname ${filname}`
		[ -f /var/tmp/${File_Name}.tar ] && rm -f /var/tmp/${File_Name}.tar >/dev/null 2>&1
		${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "
		${SUDO} /usr/bin/test -f /var/tmp/${File_Name}.tar
		if [ \$? -eq 0 ];then
			${SUDO} /usr/bin/rm -f /var/tmp/${File_Name}.tar
		fi
		${SUDO} /usr/bin/tar -cf /var/tmp/${File_Name}.tar -C ${File_Path} ${File_Name}
		${SUDO} /usr/bin/chmod o+r /var/tmp/${File_Name}.tar
		${SCP} /var/tmp/${File_Name}.tar ${CURRENT_USER_NAME}@${CURRENT_HOST_IP}:/var/tmp/${File_Name}.tar"
		if [ $? -ne 0 ];then
			log "\nError in copying `basename ${filname}` from host : ${Clus_Node_IP}"
			exit 1
		else
			tar -xf /var/tmp/${File_Name}.tar -C ${File_Path}/ >/dev/null 2>&1
			rm -f /var/tmp/${File_Name}.tar  >/dev/null 2>&1
		fi
		${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} /usr/bin/rm -f /var/tmp/${File_Name}.tar"
	done

	[ "X${IO_FENCING_TYPE}" = "XCPS" ] && {
		log "\tCopying keys for CP Server from host : ${Clus_Node_IP}"
		[ -f /var/tmp/keys.tar ] && rm -f /var/tmp/keys.tar >/dev/null 2>&1
		${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "
		${SUDO} /usr/bin/test -f /var/tmp/keys.tar
		if [ \$? -eq 0 ];then
			${SUDO} /usr/bin/rm -f /var/tmp/keys.tar
		fi
		${SUDO} /usr/bin/tar -cf /var/tmp/keys.tar /var/VRTSvxfen 
		${SUDO} /usr/bin/chmod o+r /var/tmp/keys.tar
		${SCP} /var/tmp/keys.tar ${CURRENT_USER_NAME}@${CURRENT_HOST_IP}:/var/tmp/keys.tar" >/dev/null 2>&1
		if [ $? -ne 0 ];then
			${ECHO} "\n[ ERROR ] : Unable to copy CP Server keys from ${CURRENT_USER_NAME}@${Clus_Node_IP} to ${CURRENT_USER_NAME}@${CURRENT_HOST_IP}"
			exit 1
		else
			tar -xf /var/tmp/keys.tar -C / >/dev/null 2>&1
			rm -f /var/tmp/keys.tar >/dev/null 2>&1
		fi
		${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} /usr/bin/rm -f /var/tmp/keys.tar" >/dev/null 2>&1

		## Stopping scsi3pr as this is a CPS based fencing
		${VXDCTL} scsi3pr 2>/dev/null | grep "off$" >/dev/null 2>&1
		[ $? -ne 0 ] && ${VXDCTL} scsi3pr off >/dev/null 2>&1
	}


	${ECHO} "\n--> Modifying Cluster Configuration Files for the New Node"
	cat /etc/llthosts | awk '{print $NF}'| grep -w "^${CURRENT_HOST}$" >/dev/null 2>&1
	if [ $? -ne 0 ];then
		${ECHO} "\n--> Adding New Node to /etc/llthosts"
		existing_id=`cat /etc/llthosts | grep -v "^$" | awk '{print $1}' | sort -n | uniq | tail -1`
		export new_node_id=`expr ${existing_id} + 1`
		cat /etc/llthosts | grep -v "^$" > /etc/llthosts.tmp
		mv -f /etc/llthosts.tmp /etc/llthosts
		${ECHO} "${new_node_id} ${CURRENT_HOST}" >> /etc/llthosts
	fi

	${ECHO}  "\n--> Generating /etc/llttab file for the New Node"
	{
		${ECHO}  "set-node ${CURRENT_HOST}"
		${ECHO}  "set-cluster ${Cluster_ID}"
	} > /etc/llttab

	${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} /usr/bin/cat /etc/llttab" | grep "^set-timer" >> /etc/llttab

	for link in ${Nhb1} ${Nhb2}
	do
		interfaceid=`echo ${link} | grep -E -o "[0-9]+" | tail -1`
		interface=`echo ${link} | sed "s/${interfaceid}$//"`
		interfacemac=`ip link | grep -A1 ${link} | grep ether | awk '{print $2}'`

		# Set MTU value to 1200 in case of cloud environment
		if [ "X${CLOUD_SETUP}" = "XY" ]; then
			echo "link ${link} eth-${interfacemac} - ether - 1200" >> /etc/llttab
		else
			echo "link ${link} eth-${interfacemac} - ether - -" >> /etc/llttab
		fi
	done
	
	${ECHO}  "\n--> Generating /etc/gabtab for the New Node"
	#--------------------------------------------#
	### Getting the Last Character from GABTAB ###
	#--------------------------------------------#
	node_count=`${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} ${HASYS} -list" | wc -l`
	${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} ${HASYS} -state ${CURRENT_HOST}" >/dev/null 2>&1
	if [ $? -ne 0 ];then
		node_count=`expr ${node_count} + 1`
		sed -i -e "s/-n[0-9]*.$/-n${node_count}/" /etc/gabtab

		${ECHO} "\n--> Copying updated configuration files to Cluster Members"
		
		[ -f /var/tmp/clus_files.tar ] && rm -f /var/tmp/clus_files.tar >/dev/null 2>&1
		tar -cf /var/tmp/clus_files.tar -C /etc/ gabtab llthosts >/dev/null 2>&1
		chmod o+r /var/tmp/clus_files.tar  >/dev/null 2>&1		
		for member in ${clus_members}
		do

			${SSH} ${CURRENT_USER_NAME}@${member} "
			${SUDO} /usr/bin/test -f /var/tmp/clus_files.tar
			if [ \$? -eq 0 ];then
				${SUDO} /usr/bin/rm -f /var/tmp/clus_files.tar
			fi "  >/dev/null 2>&1
			
			${SCP} /var/tmp/clus_files.tar ${CURRENT_USER_NAME}@${member}:/var/tmp/clus_files.tar >/dev/null 2>&1
			if [ $? -ne 0 ];then
				${ECHO} "\n[ ERROR ] : Unable to copy /etc/gabtab and /etc/llthosts from ${CURRENT_USER_NAME}@${CURRENT_HOST} to ${CURRENT_USER_NAME}@${member}"
				exit 1
			else
				${SSH} ${CURRENT_USER_NAME}@${member} "
				${SUDO} /usr/bin/tar -xf /var/tmp/clus_files.tar -C /etc/
				if [ \$? -eq 0 ];then
					${SUDO} /usr/bin/rm -f /var/tmp/clus_files.tar
				fi " >/dev/null 2>&1
				
			fi
		done
		rm -f /var/tmp/clus_files.tar  >/dev/null 2>&1
	else
		${ECHO}  "\n--> File /etc/gabtab already updated"
	fi

	[ "X${IO_FENCING_TYPE}" = "XCPS" ] && {
		${ECHO} "\n--> Registering host ${CURRENT_HOST} with CP Servers"
		source /etc/cp_server_ip >/dev/null 2>&1

		export CPS_NODEID=`sed "s/ /#/g" /etc/llthosts |grep "#${CURRENT_HOST}$" | awk -F"#" '{print $1}' | head -1`
		for cps_vip in ${CPS1} ${CPS2} ${CPS3}
		do
			${ECHO} "\n--> Registering host ${CURRENT_HOST} with CP Server ${CURRENT_USER_NAME}@${cps_vip}"
			${SSH} ${CURRENT_USER_NAME}@${cps_vip} "${SUDO} ${CPSADM} -s ${cps_vip} -a list_nodes -c ${Cluster_Name}" 2>/dev/null | awk '{print $3}' | awk -F'(' '{print $1}' | grep -w "^${CURRENT_HOST}$" >/dev/null 2>&1
			[ $? -ne 0 ] && ${SSH} ${CURRENT_USER_NAME}@${cps_vip} "${SUDO} ${CPSADM} -s ${cps_vip} -a add_node -c ${Cluster_Name} -h ${CURRENT_HOST} -n ${CPS_NODEID}"
		done
	}


	/sbin/lltstat -C 2>/dev/null | grep -wq "${Cluster_ID}"
	if [ $? -ne 0 ];then
		${ECHO} "\n--> Starting HeartBeat Links (LLT Service)"
		systemctl restart llt > /dev/null 2>&1
		/sbin/lltconfig -c -o  > /dev/null 2>&1
		${ECHO} "\n--> Waiting for LLT Service Startup"
		while true
		do
			/sbin/lltstat -C 2>/dev/null | grep -wq "${Cluster_ID}"
			[ $? -eq 0 ] && break
			sleep 2
			/sbin/lltconfig -c -o  > /dev/null 2>&1
		done
	fi

	/opt/VRTS/bin/gabconfig -C 2>/dev/null | grep -wq "GAB_Control"
	if [ $? -ne 0 ];then
		${ECHO} "\n--> Starting Group Atomic Broadcast (GAB) Modules"
		systemctl restart gab > /dev/null 2>&1
		sleep 2
		systemctl restart vxodm > /dev/null 2>&1

		${ECHO} "\n--> Waiting for GAB Membership"
		while true
		do
			/opt/VRTS/bin/gabconfig -C 2>/dev/null | grep -wq "GAB_Control"
			[ $? -eq 0 ] && break
			sleep 2
			/opt/VRTS/bin/gabconfig -c -x > /dev/null 2>&1
		done
	fi

	/usr/sbin/vxfenadm -d 2>/dev/null | grep '\*' | grep -wq "(${CURRENT_HOST})"
	if [ $? -ne 0 ];then
		${ECHO} "\n--> Starting I/O Fencing"
		systemctl restart vxfen > /dev/null 2>&1
		sleep 4
		count=0
		${ECHO} "\n--> Waiting for Fencing Membership"
		while true
		do
			/usr/sbin/vxfenadm -d 2>/dev/null | grep '\*' | grep -wq "(${CURRENT_HOST})"
			[ $? -eq 0 ] && break
			sleep 2
			count=`expr $count + 1`
                        if [ ${count} -eq 15 ]; then
                                systemctl restart vxfen > /dev/null 2>&1
                                count=0
                        fi
		done
	fi

	${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} ${HASYS} -state ${CURRENT_HOST}" > /dev/null 2>&1
	if [ $? -ne 0 ];then

		${ECHO} "\n--> Adding new Node ${CURRENT_HOST} to Cluster Configuration"
		conf_stat=`${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} /opt/VRTSvcs/bin/haclus -value ReadOnly"`
		[ "${conf_stat}" -eq 1 ] && {
			${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} ${HACONF} -makerw" >/dev/null 2>&1
			sleep 2
		}

		${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} ${HASYS} -add ${CURRENT_HOST}" > /dev/null 2>&1 
		sleep 1
		${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "${SUDO} ${HACONF} -dump -makero" > /dev/null 2>&1 
	else
		${ECHO} "\n--> Node ${CURRENT_HOST} was already added to Cluster Configuration"
	fi

	${HASYS} -state ${CURRENT_HOST} 2>/dev/null | grep -w RUNNING >/dev/null 2>&1
	if [ $? -ne 0 ];then
		${ECHO} "\n--> Starting HAD Daemon on ${CURRENT_HOST}"
		systemctl restart vcs > /dev/null 2>&1
		${HASTART} >/dev/null 2>&1
		
		count=0
		${ECHO} "\n--> Waiting for Cluster daemon startup on ${CURRENT_HOST}"
		while true
		do
			${HASYS} -state ${CURRENT_HOST} 2>/dev/null | grep -w RUNNING >/dev/null 2>&1
			[ $? -eq 0 ] && break
			sleep 2
			count=`expr $count + 1`
			if [ ${count} -eq 10 ];then
				${HASYS} -state ${CURRENT_HOST} 2>/dev/null | grep -wq "REMOTE_BUILD"
				if [ $? -eq 0 ];then
					${HASTOP} -local >/dev/null 2>&1
					sleep 1
					${HASTART} >/dev/null 2>&1
				fi
			fi
		done
	else
		${ECHO} "\n--> HAD Daemon was already running"
	fi

	update_status "Add_Cluster_Node=Y"

}

#---------------------------------------#
# This functionw will add the new node  #
# to various Service Groups             #
#---------------------------------------#
Adding_Node_To_ServiceGroups()
{
	Func_Header "Adding Node to Service Groups" ${1} ${2}

	CURRENT_HOST=`hostname -s`
	export CURRENT_USER_NAME=`printenv SUDO_USER`
	[ "X${CURRENT_USER_NAME}" = "X" ] && export CURRENT_USER_NAME="root"
	export CURRENT_HOSTIP=$(/usr/bin/gethostip -d ${CURRENT_HOST} 2>/dev/null)
	Clus_Node_IP=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^Clus_Node_IP" | ${AWK} -F'=' '{ print $2 }' | sed 's/\"//g'`
	Cluster_HOST=`${SSH} ${CURRENT_USER_NAME}@${Clus_Node_IP} "hostname -s" | head -1`

	conf_stat=`${HACLUS} -value ReadOnly`
	if [ ${conf_stat} -eq 1 ];then
		${ECHO} "\n--> Making Cluster Configuration RE-Writable"
		${HACONF} -makerw
		sleep 3
	fi

	export sys_idx=`${HASYS} -value ${CURRENT_HOST} LLTNodeId`
	${ECHO} "\n--> Adding the new node to Network Service Group"
	${HAGRP} -state Network -sys "^${CURRENT_HOST}$" >/dev/null 2>&1
	[ $? -ne 0 ] && {
		${ECHO}  "\n--> Adding Node to SystemList and AutoStartList of Network Service Group"
		${HAGRP} -modify Network SystemList -add ${CURRENT_HOST} ${sys_idx} >/dev/null 2>&1
		${HAGRP} -modify Network AutoStartList -add ${CURRENT_HOST} >/dev/null 2>&1
	}

	${ECHO}  "\n--> Adding the Node to Device Resource"
	${HARES} -state MM_ONM_NIC -sys ${CURRENT_HOSTIP} >/dev/null 2>&1
	if [ $? -ne 0 ];then
		### Determine number of bonds formed on the system
		## Either ONM or Traffic
		no_of_bonds=`cat /etc/modprobe.d/bond.conf | grep bond | wc -l`
		for bond_name in `cat /etc/modprobe.d/bond.conf | awk '{print $2}'`
		do
			unset IPADDR IPV6ADDR IPv4
			source /etc/sysconfig/network-scripts/ifcfg-${bond_name}
			rpm -q "cloud-init" >/dev/null 2>&1
			if [ $? -eq 0 ];then
				grep -w "IPV6INIT=yes" /etc/sysconfig/network-scripts/ifcfg-${bond_name} >/dev/null 2>&1
				if [ $? -eq 0 ]; then
					IPV6ADDR=`ifconfig ${bond_name} | awk '/global/ {print $2}'`
				else
					IPADDR=`ifconfig ${bond_name} | awk '/netmask/ {print $2}'`
				fi
			fi
			cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "${IPADDR}" | grep -qi "ONM"
			[ $? -eq 0 ] && export res_name="MM_ONM_NIC"

			cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "${IPADDR}" | grep -qi "Traffic"
			[ $? -eq 0 ] && export res_name="MM_TRF_NIC"
			if [ "X${res_name}" = "X" ]; then
				${ECHO} " [ERROR] : Could not determine resource name. Exiting..."
				exit 606
			fi

			IPv4=false
			if [ ! -z ${IPADDR} ]; then
				if [ "X${res_name}" = "XMM_TRF_NIC" ]; then
					${HARES} -display ${res_name} -attribute DualDevice | grep -wq ${bond_name}
					if [ $? -ne 0 ]; then
						deviceIP=`${HARES} -display ${res_name} -attribute Device | grep -w ${bond_name} | awk '{print $NF}'  | head -1`
						/usr/bin/ipcalc -4c $deviceIP 2>/dev/null
						if [ $? -ne 0 ]; then
							export modifyDevice=1
							modifyDevice ${bond_name}
						fi
					fi
				fi
				${HARES} -modify ${res_name} Device -add ${bond_name} ${IPADDR} -sys ${CURRENT_HOST} >/dev/null 2>&1
				IPv4=true
			fi
			if [ ! -z ${IPV6ADDR} ]; then
				if [ $IPv4 = "false" ] ; then
					${HARES} -display ${res_name} -attribute Device | grep -wq ${bond_name}
					if [ $? -eq 0 ]; then
						deviceIP=`${HARES} -display ${res_name} -attribute Device | grep -w ${bond_name} | awk '{print $NF}'  | head -1`
						/usr/bin/ipcalc -4c $deviceIP 2>/dev/null
						if [ $? -eq 0 ]; then
							IPv6Device=DualDevice
						else
							IPv6Device=Device
						fi
					else
						IPv6Device=Device
					fi
				else
					IPv6Device=DualDevice
				fi

				ipv6addr_only=`echo ${IPV6ADDR} | awk -F/ '{print $1}'`
				rpm -q "cloud-init" >/dev/null 2>&1
				if [ $? -eq 0 ]; then
					prefix=`cat ${CONFIG_TEMPLATE_SRC_PATH}/${CONFIG_TEMPLATE} | grep "^netmask_Traffic=" | awk -F"=" '{print $NF}' | sed 's/"//g'`
				else
					prefix=`echo ${IPV6ADDR} | awk -F/ '{print $2}'`
				fi
				${HARES} -modify ${res_name} ${IPv6Device} -add ${bond_name} ${ipv6addr_only} -sys ${CURRENT_HOST} >/dev/null 2>&1
			fi
		done
	fi

	${HAGRP} -list 2>/dev/null | grep -w "Vxfen_CPS" > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		conf_stat=`${HACLUS} -value ReadOnly`
		if [ ${conf_stat} -eq 1 ];then
			${ECHO} "\n--> Making Cluster Configuration RE-Writable"
			${HACONF} -makerw
			sleep 2
		fi

		${ECHO} "\n--> Adding the new Node to Vxfen_CPS Service Group"
		${HAGRP} -modify Vxfen_CPS SystemList -add ${CURRENT_HOST} ${sys_idx} >/dev/null 2>&1

		${ECHO}  "\n--> Adding the Node to AutoStartList of Vxfen_CPS Service Group"
		${HAGRP} -value Vxfen_CPS AutoStartList | grep -w ${CURRENT_HOST} > /dev/null 2>&1 
		[ $? -ne 0 ] && ${HAGRP} -modify Vxfen_CPS AutoStartList -add ${CURRENT_HOST} >/dev/null 2>&1
	fi

	if [ "X${FSTYPE}" = "XNFS" ];then
		NFS_SG_NAMES=`${HAGRP} -list | awk '{print $1}' | grep "_NFS$" | uniq`
		
		if [ "X" != "X${NFS_SG_NAMES}" ];then
			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 1 ];then
				${ECHO} "\n--> Making Cluster Configuration RE-Writable"
				${HACONF} -makerw
				sleep 3
			fi
		fi

		for NFS_SG_NAME in ${NFS_SG_NAMES}
		do
			${ECHO} "\n--> Adding the new node to ${NFS_SG_NAME} Service Group"

			${HAGRP} -state -sys ${CURRENT_HOST} 2>/dev/null | grep -w "^${NFS_SG_NAME}" >/dev/null 2>&1
			if [ $? -ne 0 ];then
				mountPoints=`${HARES} -display  -attribute MountPoint -group ${NFS_SG_NAME} | grep -w MountPoint | awk '{print $NF}'`
				for mountPoint in $mountPoints; do
					[ -d $mountPoint ] || mkdir -p --mode=u+rwx,g+rxs,o+rx $mountPoint
				done
				${ECHO}  "\n--> Adding Node to SystemList of ${NFS_SG_NAME} Service Group"
				${HAGRP} -modify ${NFS_SG_NAME} SystemList -add ${CURRENT_HOST} ${sys_idx}

				${ECHO}  "\n--> Adding Node to AutoStartList of ${NFS_SG_NAME} Service Group"
				${HAGRP} -modify ${NFS_SG_NAME} AutoStartList -add ${CURRENT_HOST}
			else
				${ECHO}  "\n--> Node was already added to ${NFS_SG_NAME} Service Group"
			fi
		done

		conf_stat=`${HACLUS} -value ReadOnly`
		if [ ${conf_stat} -eq 0 ];then
			${ECHO} "\n--> Saving Cluster Configuration"
			${HACONF} -dump -makero
			sleep 2
		fi
		for NFS_SG_NAME in ${NFS_SG_NAMES}
		do
			${HAGRP} -online ${NFS_SG_NAME} -sys ${CURRENT_HOST} >/dev/null 2>&1
			count=0
			while true
			do
				${HAGRP} -state ${NFS_SG_NAME} -sys ${CURRENT_HOST} 2>/dev/null | grep "ONLINE" >/dev/null 2>&1
				if [ $? -ne 0 ];then
					${ECHO} "\n --> Waiting for 10 more seconds ..."
					sleep 10
				else
					break
				fi
				
				count=`expr ${count} + 1`
				if [ ${count} -eq 12 ]; then
					${ECHO} "\n[ERROR] : Unable to start ${NFS_SG_NAME} Service Group within desired time"
					${ECHO} "\n[ACTION] : Please start ${NFS_SG_NAME} manually on node ${CURRENT_HOST} and then press the Enter key to continue"
					read user_input
					count=0
				fi
			done
		done
	fi
	
	${HAGRP} -state cvm > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		${HAGRP} -state cvm -sys ${CURRENT_HOST} > /dev/null 2>&1
		if [ $? -ne 0 ];then
			${ECHO} "\n--> Adding new node to CVM Configuration"
			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 1 ];then
				${ECHO} "\n--> Making Cluster Configuration RE-Writable"
				${HACONF} -makerw > /dev/null 2>&1
				sleep 3
			fi

			vxfsckd_res=`${HARES} -list Group=cvm Type=CFSfsckd 2>/dev/null| awk '{print $1}' | head -1`
			vxfsckd_activation=`${HARES} -value ${vxfsckd_res} ActivationMode ${Cluster_HOST} 2>/dev/null`
			cvmclus_res=`${HARES} -list Type=CVMCluster -localclus 2>/dev/null| awk '{print $1}' | head -1`

			${ECHO}  "\n--> Adding the Node to SystemList and AutoStartList of cvm SG"
			${HAGRP} -modify cvm SystemList -add ${CURRENT_HOST} ${sys_idx} > /dev/null 2>&1
			${HAGRP} -modify cvm AutoStartList -add ${CURRENT_HOST} > /dev/null 2>&1

			${ECHO}  "\n--> Adding the Node to ${cvmclus_res} Resource"
			${HARES} -modify ${cvmclus_res} CVMNodeId -add ${CURRENT_HOST} ${sys_idx} >/dev/null 2>&1

			${ECHO} "\n--> Adding the Node to ${vxfsckd_res} Resource"
			${HARES} -modify ${vxfsckd_res} ActivationMode ${vxfsckd_activation} -sys ${CURRENT_HOST} >/dev/null 2>&1

			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 0 ];then
				${ECHO} "\n--> Saving Cluster Configuration"
				${HACONF} -dump -makero >/dev/null 2>&1
				sleep 2
			fi
		else
			${ECHO} "\n--> Node ${CURRENT_HOST} was already added to CVM Configuration"
		fi

		clus_members=`${HASYS} -list | grep -v "^${CURRENT_HOST}$"`
		for member in ${clus_members}
		do
			${ECHO}  "\n--> Reinitializing Cluster on Node : ${member}"
			${SSH} ${CURRENT_USER_NAME}@${member} "${SUDO} /opt/VRTS/bin/vxclustadm -m vcs -t gab reinit"  >/dev/null 2>&1
			sleep 2
			${SSH} ${CURRENT_USER_NAME}@${member} "${SUDO} /etc/vx/bin/vxclustadm nidmap" >/dev/null 2>&1
		done

		${ECHO} "\n--> Starting cvm Service Group on ${CURRENT_HOST}"
		${HAGRP} -online cvm -sys ${CURRENT_HOST} >/dev/null 2>&1
		${ECHO} "\n--> Waiting for cvm to start on ${CURRENT_HOST}"
		${HAGRP} -wait cvm State ONLINE -sys ${CURRENT_HOST} -time 120 >/dev/null 2>&1

		count=0
		while true
		do
			${HAGRP} -state cvm -sys ${CURRENT_HOST} 2>/dev/null | grep "ONLINE" >/dev/null 2>&1
			if [ $? -ne 0 ];then
				${ECHO} "\n --> Waiting for 10 more seconds ..."
				sleep 10
			else
				break
			fi
			
			count=`expr ${count} + 1`
			if [ ${count} -eq 12 ]; then
				${ECHO} "\n[ERROR] : Unable to start cvm Service Group within desired time"
				${ECHO} "\n[ACTION] : Please start cvm manually on node ${CURRENT_HOST} and then press the Enter key to continue"
				read user_input
				count=0
			fi
		done

	fi

	CFSRES=`${HARES} -list Type=CFSMount | awk '{print $1}' | sort -u`
	if [ "X${CFSRES}" != "X" ]; then 
		SERVICE_GROUP=""
		for res in ${CFSRES}
		do
			SERVICE_GROUP1=`${HARES} -value ${res} Group`
			echo ${SERVICE_GROUP} | grep ${SERVICE_GROUP1} >/dev/null 2>&1
			[ $? -ne 0 ] && SERVICE_GROUP="${SERVICE_GROUP1} ${SERVICE_GROUP}"
		done
		
		for SG in ${SERVICE_GROUP}
		do
			${ECHO} "\n--> Adding Host ${CURRENT_HOST} to ${SG} Service Group"
			${HAGRP} -resources ${SG} | grep cvmvoldg | while read cvmvol
			do
				DG_NAME=`${HARES} -value ${cvmvol} CVMDiskGroup`
				${CFSDGADM} display ${DG_NAME} 2>/dev/null | grep -w ${CURRENT_HOST} > /dev/null 2>&1
				[ $? -ne 0 ] && {
					log "\n---> Adding ${DG_NAME} into CVM for Host ${CURRENT_HOST}"
					${CFSDGADM} add ${DG_NAME} ${CURRENT_HOST}=sw >/dev/null 2>&1
				}

				${HARES} -display ${cvmvol} | awk '{if($2=="CVMActivation" && $4=="sw"){print $3}}' | grep "^${CURRENT_HOST}$" > /dev/null 2>&1
				if [ $? -ne 0 ]; then
					conf_stat=`${HACLUS} -value ReadOnly`
					if [ ${conf_stat} -eq 1 ];then
						${HACONF} -makerw
						sleep 2
					fi

					${HARES} -modify ${cvmvol} CVMActivation sw -sys ${CURRENT_HOST} > /dev/null 2>&1
				fi
			done

			${HAGRP} -resources ${SG} | grep cfsmount | while read cfsmount
			do
				mountpoint=`${HARES} -value ${cfsmount} MountPoint`
				${CFSMNTADM} display ${CURRENT_HOST} 2>/dev/null| grep -w "${mountpoint}" >/dev/null 2>&1
				[ $? -ne 0 ] && ${CFSMNTADM} modify ${mountpoint} add ${CURRENT_HOST}="cluster" > /dev/null 2>&1
			done

		done

		conf_stat=`${HACLUS} -value ReadOnly`
		if [ ${conf_stat} -eq 0 ];then
			${ECHO} "\n--> Saving Cluster Configuration"
			${HACONF} -dump -makero
			sleep 2
		fi

		for SG_NAME in ${SERVICE_GROUP}
		do
			${HAGRP} -online ${SG_NAME} -sys ${CURRENT_HOST} >/dev/null 2>&1
		done
	fi

	[ -f /var/tmp/clus_mount.txt ] && rm -f /var/tmp/clus_mount.txt
	/opt/VRTS/bin/cfscluster status 2>/dev/null | grep MOUNTED | awk '{print $1}' | sort -u >/var/tmp/clus_mount.txt
	${HATYPE} -resources Mount |grep -v "^$" | while read res; do ${HARES} -value $res MountPoint >> /var/tmp/clus_mount.txt ; done
	[ -s /var/tmp/clus_mount.txt ] && {
		for dir in `cat /var/tmp/clus_mount.txt`
		do
			mkdir -p --mode=u+rwx,g+rxs,o+rx $dir >/dev/null 2>&1
		done
	}

	[ -f /var/tmp/clus_mount.txt ] && rm -f /var/tmp/clus_mount.txt

	conf_stat=`${HACLUS} -value ReadOnly`
	if [ ${conf_stat} -eq 0 ];then
		${ECHO} "\n--> Saving Cluster Configuration"
		${HACONF} -dump -makero
		sleep 2
	fi

	update_status Adding_Node_To_ServiceGroups
	Update_user_group
	${ECHO} "`hostname`" | egrep -w '^failover-[0-9]+$'  > /dev/null
	if [ $? -eq 0 ]; then
		isVNFLCM1=$(sudo -u $CURRENT_USER_NAME ${SSH} $rem_clus_host "cat /etc/mediation/MM.config " | sed 's/^ *//'  |sed 's/ *$//g'| grep -v "^-" | sed -n "/^\[[a-z|A-Z|0-9 ]*Manager CXC[0-9 ]*_[a-z|A-Z|0-9 ]*\]/,/^\[/s/^[^[]/&/p" |grep lcm.deployment= | sed -e 's/^[ \t]*//' | grep -v ^#| tail -1 | awk -F= '{print $NF}')
		if [ "X${isVNFLCM1}" = "Xtrue" ]; then
			${ECHO} "$CURRENT_USER_NAME" >> /etc/at.allow
			CXCDIR=`ls /install | grep "^CX"`
			systemctl start atd
			${ECHO} "sudo $CURRENT_USER_HOME_DIR/$CXCDIR/vnf-lcm/subjob.sh" > /var/tmp/temp1.sh
			chmod +x /var/tmp/temp1.sh
			chmod +x $CURRENT_USER_HOME_DIR/$CXCDIR/vnf-lcm/subjob.sh
			sudo -u $CURRENT_USER_NAME at now +5 minutes -f /var/tmp/temp1.sh
		fi
	fi	

}


#----------------------------------#
# Function to Add Disk Group in    #
# Shared mode on CVM master        #
#----------------------------------#
Add_DG_CVM()
{
	${ECHO} "\n Verifying Cluster Configuration ...."
	hastatus -sum > /dev/null 2>&1
	[ $? -ne 0 ] && {
		${ECHO} "Cluster Daemon is not running on current node"
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 1
	}
	
	${HAGRP} -state -sys `hostname -s` 2>/dev/null | grep -w "cvm" >/dev/null
	[ $? -ne 0 ] && {
		${ECHO} "\nCVM Service Group does not exist. Configure CVS Service group first." 
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 1
	}

	${HAGRP} -state cvm -sys `hostname -s` 2>/dev/null | grep -w "ONLINE" >/dev/null
	[ $? -ne 0 ] && {
		${ECHO} "\nCVM Service Group must be ONLINE for this operation"
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 1
	}

	vxdctl -c mode 2>/dev/null | grep "master:" | grep `hostname -s` >/dev/null
	[ $? -ne 0 ] && {
		${ECHO} "\n Acquiring CVM Master Privilege"
		vxclustadm setmaster `hostname -s`
		sleep 5
		vxdctl -c mode 2>/dev/null | grep "master:" | grep `hostname -s` >/dev/null
		[ $? -ne 0 ] && {
			${ECHO} "\nUnable to acquire CVM Master Privilege"
			${ECHO} "Run this command from `vxdctl -c mode 2>/dev/null | grep \"master:\" | awk -F\":\" '{print $2}'`"
			log "\nPress <Enter> to continue...\c"
			read contKey
			return 1
		}
	}

	${VXDISK} -o alldgs list | grep ":sliced" | grep -v shared | awk '{print $4}' | tr -d '()' | sort | uniq >/var/tmp/vxdg_status
	${HATYPE} -resources DiskGroup |grep -v "^$" | while read res; do ${HARES} -value $res DiskGroup >> /var/tmp/vxdg_status ; done
	cat /var/tmp/vxdg_status | grep -v rootdg | sort | uniq -u >/tmp/vxdg_status1
	[ -s /tmp/vxdg_status ] && rm -f /tmp/vxdg_status
	${VXDG} list | grep -v shared | grep -v STATE >/var/tmp/local_avail_dg
	for dg in `cat /tmp/vxdg_status1`
	do
		grep $dg /var/tmp/local_avail_dg >/dev/null
		[ $? -eq 0 ] && echo $dg >>/tmp/vxdg_status
	done


	rm -f /var/tmp/vxdg_status /var/tmp/local_avail_dg /tmp/vxdg_status1 >/dev/null 2>&1
	if [ -s /tmp/vxdg_status ]; then
		${ECHO} "\n ******* Available Disk Groups are ******* "
		cat /tmp/vxdg_status
		while true
		do
			${ECHO} "\n Enter the DiskGroup name to be added to Cluster Configuration : \c"
			read DG_NAME
			if [ "X${DG_NAME}" = "X" ]; then    
				${ECHO} "ERROR : DiskGroup Name can not be blank"
				continue
			else
				grep -w ${DG_NAME} /tmp/vxdg_status >/dev/null 2>&1
				if [ $? -ne 0 ]; then
					${ECHO} "ERROR : DiskGroup Name entered is invalid"
					continue
				else
					export DG_NAME
					break
				fi
			fi
			
		done
		rm -f /tmp/vxdg_status
	else
		${ECHO} "\n No DiskGroup is available for Cluster Configuration" 
		rm -f /tmp/vxdg_status
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 1
	fi

	MOUNT_POINT=""
	OLDMOUNT_POINT=""
	SYSTEM_LIST=""
	AUTOSTART_LIST=""
	SG_NAME=""

	if [ `${HASYS} -list 2>/dev/null | wc -l` -gt 1 ]; then 
		export CURRENT_HOST=`hostname -s`
		ALL_NODES=""
		for node in `${HASYS} -list 2>/dev/null | grep -vw "^${CURRENT_HOST}$"`
		do
			export ALL_NODES="${ALL_NODES} $node"
		done
		
		for clusnode in ${ALL_NODES}
		do
			${SSH} ${CURRENT_USER_NAME}@${clusnode} "
			${SUDO} ${VXDCTL} enable
			${SUDO} ${VXDG} deport ${DG_NAME}
			exit" >/dev/null 2>&1
		done

		[ -f /var/tmp/imp_dg.txt ] && rm -f  /var/tmp/imp_dg.txt >/dev/null 2>&1
		fail=0
		for clusnode in ${ALL_NODES}
		do
			${SSH} ${CURRENT_USER_NAME}@${clusnode} "${SUDO} ${VXDG} list" | grep -w ${DG_NAME} >/dev/null 2>&1
			[ $? -eq 0 ] && {
				echo " ${clusnode}" >> /var/tmp/imp_dg.txt
				fail=`expr $fail + 1`
			}
		done

		[ $fail -ne 0 ] && {
			${ECHO} "\n[ ERROR ] : DiskGroup ${DG_NAME} is already imported on following node(s)"
			cat /var/tmp/imp_dg.txt

			rm -f /var/tmp/imp_dg.txt >/dev/null 2>&1
			${ECHO} "\nDeport the DiskGroup ${DG_NAME} from other node(s) first"
			log "\nPress <Enter> to continue...\c"
			read contKey
			return 1
		} || rm -f /var/tmp/imp_dg.txt >/dev/null 2>&1
	fi

	###################Checking for DG Service Group In Cluster ##############

	${HAGRP} -list 2>/dev/null | grep "_DG" >/dev/null
	if [ $? -ne 0 ]; then
		while true
		do
			${ECHO} " \n Enter the Service Group Name to be added to Cluster : \c"
			read SG_NAME
			if [ "X${SG_NAME}" = "X" ]; then    
				${ECHO} "ERROR : Service Group Name can not be blank"
				continue
			else
				${HAGRP} -list 2>/dev/null | grep ${SG_NAME} >/dev/null 2>&1
				if [ $? -eq 0 ]; then
					${ECHO} "ERROR : Service Group Name entered Already Exist"
					continue
				else
					export SG_NAME
					break
				fi
			fi
		done
	else
		choice=""
		while true
		do
			${ECHO} " \n Do you want to add this Disk Group to existing Service Group (Y/N) : \c"
			read choice
			choice=`echo $choice | tr "[a-z]" "[A-Z]"`
			case ${choice} in
				Y|N) break;;
				*) continue;;
			esac
		done

		if [ "$choice" = "Y" ]; then
			${ECHO} "\n ********** Available Service Groups are **********"
			${HAGRP} -list 2>/dev/null | awk '/DG/ { print $1}' | sort -u | tee /tmp/sg_list
			while true
			do
				${ECHO} "\n Enter the Service Group name from the List : \c"
				read SG_NAME
				if [ "X${SG_NAME}" = "X" ]; then    
					${ECHO} "ERROR : Service Group Name can not be blank"
					continue
				else
					grep -w "${SG_NAME}" /tmp/sg_list >/dev/null 2>&1
					if [ $? -ne 0 ]; then
						${ECHO} "ERROR : Service Group Name entered is invalid"
						continue
					else
						export SG_NAME
						break
					fi
				fi
				
			done
		else
			while true
			do
				${ECHO} " \n Enter the Service Group Name to be added to Cluster : \c"
				read SG_NAME
				if [ "X${SG_NAME}" = "X" ]; then    
					${ECHO} "ERROR : Service Group Name can not be blank"
					continue
				else
					${HAGRP} -list 2>/dev/null | grep ${SG_NAME} >/dev/null 2>&1
					if [ $? -eq 0 ]; then
						${ECHO} "ERROR : Service Group Name entered Already Exist"
						continue
					else
						echo ${SG_NAME} | grep "_DG$"  >/dev/null 2>&1
						if [ $? -ne 0 ]; then
							${ECHO} "ERROR : Service Group Name should have _DG at the end"
							continue
						else
							export SG_NAME
							break
						fi
					fi
				fi
				
			done

		fi
	fi
	rm -f /tmp/sg_list >/dev/null 2>&1

	[ -f /var/tmp/clus_mount.txt ] && rm -f /var/tmp/clus_mount.txt
	/opt/VRTS/bin/cfscluster status 2>/dev/null | grep MOUNTED | awk '{print $1}' | sort -u >/var/tmp/clus_mount.txt
	${HATYPE} -resources Mount |grep -v "^$" | while read res; do ${HARES} -value $res MountPoint >> /var/tmp/clus_mount.txt ; done

	mount -v | grep "vx/dsk/${DG_NAME}/" >/dev/null
	if [ $? -eq 0 ]; then
		export OLDMOUNT_POINT=`mount -v | grep "vx/dsk/${DG_NAME}/vol" | awk '{print $3}'`
		while true
		do
			${ECHO} "\n[ INFO ] DiskGroup ${DG_NAME} already mounted on ${OLDMOUNT_POINT}"
			${ECHO} " \n Enter the Mount Point to be configured for ${DG_NAME} [${OLDMOUNT_POINT}] : \c"
			read MOUNT_POINT

			[ "X${MOUNT_POINT}" = "X" ] && MOUNT_POINT=${OLDMOUNT_POINT}

			if [ "X$(${ECHO} ${MOUNT_POINT} | grep '^\/')" = "X" ] ; then
				Error "Entered path is not an absolute path. Not starting with '/'"
				continue
			fi

			echo ${MOUNT_POINT} | egrep -w "^/dev|^/home|^/run|^/sys|^/boot|^/tmp|^/root|^/var/log|^/$"  >/dev/null 2>&1
			[ $? -eq 0 ] && {
				Error "The PATH should not be ${MOUNT_POINT}"
				continue
			}
			
			MOUNT_POINT=`echo ${MOUNT_POINT} | sed 's#/$##g'`

			export MOUNT_POINT=$(validate_cfs_dir ${MOUNT_POINT})
			
			if [ -s /var/tmp/clus_mount.txt ]; then
				fail=0
				MOUNT=""
				for mountpoint in `cat /var/tmp/clus_mount.txt`
				do
					echo "${MOUNT_POINT}/" | grep "${mountpoint}/" >/dev/null 2>&1
					[ $? -eq 0 ] && {
						fail=`expr $fail + 1`
						MOUNT="${mountpoint} $MOUNT"
					}
				done

				grep -w ${MOUNT_POINT} /var/tmp/clus_mount.txt >/dev/null 2>&1
				[ $? -eq 0 ] && {
					fail=`expr $fail + 1`
					MOUNT=`grep -w ${MOUNT_POINT} /var/tmp/clus_mount.txt`
				}

				[ $fail -ne 0 ] && {
					${ECHO} "\n[ERROR] : Following Path is already Configured in Cluster Configuration"
					${ECHO} ${MOUNT}
					continue 
				}
			fi

			mkdir -p --mode=u+rwx,g+rxs,o+rx ${MOUNT_POINT} >/dev/null 2>&1
			[ $? -ne 0 ] && {
				${ECHO} "\n ERROR : Invalid Mount Point"
				continue
			} || break
		done
	else
		while true
		do
			${ECHO} " \n Enter the Mount Point to be configured for ${DG_NAME} : \c"
			read MOUNT_POINT

			if [ "X${MOUNT_POINT}" = "X" ]; then
				${ECHO} " \n ERROR : Mount Point can not be blank value"
				continue
			else
				MOUNT_POINT=`echo ${MOUNT_POINT} | sed 's#/$##g'`

				export MOUNT_POINT=$(validate_cfs_dir ${MOUNT_POINT})
				
				if [ -s /var/tmp/clus_mount.txt ]; then
					fail=0
					MOUNT=""
					for mountpoint in `cat /var/tmp/clus_mount.txt`
					do
						echo "${MOUNT_POINT}/" | grep "${mountpoint}/" >/dev/null 2>&1
						[ $? -eq 0 ] && {
							fail=`expr $fail + 1`
							MOUNT="${mountpoint} $MOUNT"
						}
					done
					grep -w ${MOUNT_POINT} /var/tmp/clus_mount.txt >/dev/null 2>&1
					[ $? -eq 0 ] && {
						fail=`expr $fail + 1`
						MOUNT=`grep -w ${MOUNT_POINT} /var/tmp/clus_mount.txt`
					}

					[ $fail -ne 0 ] && {
						${ECHO} "\n[ERROR] : Following Path is already Configured in Cluster Configuration"
						${ECHO} ${MOUNT}
						continue 
					}
				fi
				
				mkdir -p --mode=u+rwx,g+rxs,o+rx ${MOUNT_POINT} >/dev/null 2>&1
				[ $? -ne 0 ] && {
					${ECHO} " \n ERROR : Invalid Mount Point"
					continue
				} || break
			fi
		done
		
	fi

	export MOUNT_POINT

	if [ "X${OLDMOUNT_POINT}" != "X" ]; then
		fuser -k -c ${OLDMOUNT_POINT} > /dev/null 2>&1
		umount -f ${OLDMOUNT_POINT} > /dev/null 2>&1
		if [ $? -ne 0 ];then
			log " \n ERROR : Unable to unmount ${DG_NAME} DiskGroup Mount point ${OLDMOUNT_POINT}. Try Un-mounting it manually and then re-issue this option"
			exit 1
		fi
	fi

	${VXDG} deport ${DG_NAME} > /dev/null 2>&1
	${VXDG} -Cf import ${DG_NAME} > /dev/null 2>&1
	sleep 2

	${ECHO} "\n Adding Disk Group ${DG_NAME} to Cluster Configuration"

	conf_stat=`${HACLUS} -value ReadOnly`
	if [ ${conf_stat} -eq 1 ];then
		${ECHO} "\n--> Making Cluster Configuration RE-Writable"
		${HACONF} -makerw
		sleep 3
	fi

	${HAGRP} -list 2>/dev/null | grep ${SG_NAME} >/dev/null 2>&1
	[ $? -ne 0 ] && {
		${HAGRP} -add ${SG_NAME} >/dev/null 2>&1
		${HAGRP} -modify ${SG_NAME} Parallel 1 >/dev/null 2>&1
		${HAGRP} -modify ${SG_NAME} AutoFailOver 0 >/dev/null 2>&1

		i=0
		for line in `${HASYS} -list 2>/dev/null`
		do
			export SYSTEM_LIST="${SYSTEM_LIST} ${line} $i"
			i=`expr $i + 1`
			export AUTOSTART_LIST="${AUTOSTART_LIST} ${line}"
		done

		${HAGRP} -modify ${SG_NAME} SystemList ${SYSTEM_LIST}
		${HAGRP} -modify ${SG_NAME} AutoStartList ${AUTOSTART_LIST}
		${HAGRP} -link ${SG_NAME} cvm online local firm

		${HAGRP} -list | grep ${SG_NAME} | grep "no\ systems\ declared" >/dev/null
		[ $? -eq 0 ] && {
			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 1 ];then
				${ECHO} "\n--> Making Cluster Configuration RE-Writable"
				${HACONF} -makerw
				sleep 3
			fi
			
			${HAGRP} -unlink ${SG_NAME} cvm >/dev/null
			${HAGRP} -delete ${SG_NAME} >/dev/null
			
			conf_stat=`${HACLUS} -value ReadOnly`
			if [ ${conf_stat} -eq 0 ];then
				${ECHO} "\n--> Saving Cluster Configuration"
				${HACONF} -dump -makero
				sleep 3
			fi

			${ECHO} "\n Unable to add Service Group ${SG_NAME} to Cluster Configuration"
			${ECHO} " Try Adding this DiskGroup Again"
			exit 1
		} || ${ECHO} "\n Service Group ${SG_NAME} Created Successfully"
	}


	${VXDG} deport ${DG_NAME} > /dev/null 2>&1
	sleep 3
	${VXDG} list | grep -w ${DG_NAME} > /dev/null 2>&1
	if [ $? -eq 0 ];then
		log "\n ERROR : Unable to deport ${DG_NAME} DiskGroup. Try deporting it manually and then re-issue this option"
		exit 1
	fi
	
	${VXDG} -Cfs import ${DG_NAME} > /dev/null
	${VXDG} list | grep shared | grep -w ${DG_NAME} > /dev/null 2>&1
	[ $? -ne 0 ] && {
		${ECHO} "\n ERROR : Unable to import the Disk Group in shared mode. Check if the Disk Group is being used in some other node or not."
		exit 1
		}

	/opt/VRTS/bin/cfsmntadm add ${DG_NAME} vol01 ${MOUNT_POINT} ${SG_NAME} all=cluster
	ret_code=$?
	sleep 5
	if [ ${ret_code} -ne 0 ] -o [ ${ret_code} -ne 4 ]; then
		log "\n ERROR : Could not add ${DG_NAME} to Cluster configuration. Check the /var/VRTSvcs/log/engine_A.log for more details"
		${VXDG} deport ${DG_NAME} > /dev/null 2>&1
		${VXDG} -Cf import ${DG_NAME} > /dev/null 2>&1
		exit 1
	fi

	conf_stat=`${HACLUS} -value ReadOnly`
	if [ ${conf_stat} -eq 1 ];then
		${ECHO} "\n--> Making Cluster Configuration RE-Writable"
		${HACONF} -makerw
		sleep 3
	fi

	for res in `${HAGRP} -resources ${SG_NAME}`
	do
		[ `${HARES} -value ${res} Critical` -eq 0 ] && ${HARES} -modify ${res} Critical 1
	done

	 conf_stat=`${HACLUS} -value ReadOnly`
	 if [ ${conf_stat} -eq 0 ];then
		 ${ECHO} "\n--> Saving Cluster Configuration"
		 ${HACONF} -dump -makero
		 sleep 3
	 fi

	${ECHO} "\n Disk Group ${DG_NAME} successfully added to Service Group ${SG_NAME} in Cluster Configuration"

	${ECHO} "\n Starting the Disk Group ${DG_NAME} resources to All Nodes"
	${HAGRP} -state ${SG_NAME} 2>/dev/null | grep "OFFLINE" >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		${HASYS} -list 2>/dev/null | while read line
		do
			${HAGRP} -online ${SG_NAME} -sys ${line} 2>/dev/null
		done
	else
		[ -f /tmp/cfs_res ] && rm -f /tmp/cfs_res
		for i in `${HAGRP} -resources ${SG_NAME}`
		do 
			${HARES} -state $i | grep OFFLINE | awk '{print $1}' | sort -ur >>/tmp/cfs_res
		done 

		for res in `cat /tmp/cfs_res`
		do
			${HASYS} -list | while read line
			do
				${HARES} -online ${res} -sys ${line}
			done
		done
		rm -f /tmp/cfs_res
	fi

	${ECHO} "\n ${SG_NAME} Service Group and Disk Group ${DG_NAME} Configuration Completed"
	hastatus -sum | grep ${SG_NAME}

	log "\nPress <Enter> to continue... \c"
	read contKey
}

#------------------------------------------#
# Function to Add CFS Support to Cluster   #
# by adding Cluster Volume Manager CVM	   #
#------------------------------------------#
Configure_CFS(){

	rpm -qa | grep -w "cloud-init" >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		${ECHO} "\n[ ERROR ] : This feature is not supported in Cloud deployment"
		exit 1
	fi

	${ECHO} "\n Checking existing Cluster Configuration and Status"
	${HASTATUS} -sum >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		${ECHO} "\n[ ERROR ] : Cluster Services are not running in this system. Cannot perform any Operation."
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 1
	fi

	/opt/VRTS/bin/cfscluster status 2>/dev/null | grep running | grep "CVM\ state" >/dev/null 2>&1
	if [ $? -eq 0 ]; then 

		${ECHO} "\n[ INFO ] : CLUSTER VOLUME MANAGER (CVM) is already configured"
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 1
	fi

	${ECHO} "\n[ INFO ] : Configuring CLUSTER VOLUME MANAGER (CVM)"
	${ECHO} "\n###############################################################\n"
	/opt/VRTS/bin/cfscluster config 2>/dev/null
	/opt/VRTS/bin/cfscluster status 2>/dev/null | grep running | grep "CVM\ state" >/dev/null 2>&1
	if [ $? -eq 0 ]; then 

		${ECHO} "\n[ INFO ] : CLUSTER VOLUME MANAGER (CVM) configured successfully"
		/etc/vx/bin/vxclustadm nidmap
		${ECHO} "\n###############################################################"
		${ECHO} "Starting cvm Service Group on all the Cluster Nodes\n"
		while true
		do
			${HAGRP} -state cvm 2>/dev/null | egrep "OFFLINE|PARTIAL" >/dev/null
			if [ $? -eq 0 ];then
				${ECHO} "\n\t--> Waiting for 5 more seconds ..."
				sleep 5
				continue
			else
				break
			fi
		done
		
		${HAGRP} -state cvm
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 0
	else
		${ECHO} "\n[ ERROR ] : CLUSTER VOLUME MANAGER (CVM) Configuration Failed"
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 0
	fi

}



#-----------------------------------------------#
# Function to remove CFS Support to Cluster	#
# by adding Cluster Volume Manager CVM		#
#-----------------------------------------------#
UnConfigure_CFS(){

	${ECHO} "\n Checking existing Cluster Configuration and Status"
	${HASTATUS} -sum >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		${ECHO} "\n[ ERROR ] : Cluster Services are not running in this system. Cannot perform any Operation."
		log "\nPress <Enter> to continue..."
		read contKey
		return 1
	fi

	/opt/VRTS/bin/cfscluster status 2>/dev/null | grep running | grep "CVM\ state" >/dev/null 2>&1
	if [ $? -ne 0 ]; then 
		${ECHO} "\n[ INFO ] : CLUSTER VOLUME MANAGER (CVM) is not configured"
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 1
	else
		${VXDISK} -o alldgs list 2>/dev/null | grep shared >/dev/null 2>&1
		if [ $? -eq 0 ]; then 
			${ECHO} "\n[ ERROR ] : Shared DiskGroup exist in Cluster\n"
			${VXDISK} -o alldgs list 2>/dev/null | grep "shared"
			${ECHO} "\nShared Mount Points"
			/opt/VRTS/bin/cfscluster status 2>/dev/null | grep MOUNTED | sort -u
			${ECHO} "\nUn-Share these DiskGroup(s) First"
			log "\nPress <Enter> to continue...\c"
			read contKey
			return 1
		fi
	
	fi

	${ECHO} "\n[ INFO ] : Un-Configuring CLUSTER VOLUME MANAGER (CVM)"
	${ECHO} "\n###############################################################\n"
	/opt/VRTS/bin/cfscluster unconfig 2>/dev/null
	/opt/VRTS/bin/cfscluster status 2>/dev/null | grep running | grep "CVM\ state" >/dev/null 2>&1
	if [ $? -ne 0 ]; then 
		while true
		do
			if [ -f /var/spool/locks/.vxcvmconfig.lock ];then
				${ECHO} "Waiting for Complete removal of Cluster Volume Manager"
				sleep 2
				continue
			else
				break
			fi
		done

		${ECHO} "\n[ INFO ] : CLUSTER VOLUME MANAGER (CVM) un-configured successfully"
		${ECHO} "\n###############################################################"
		/opt/VRTS/bin/cfscluster status 2>/dev/null
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 0
	else
		${ECHO} "\n[ ERROR ] : Un-Configuration of CLUSTER VOLUME MANAGER (CVM) Failed"
		log "\nPress <Enter> to continue...\c"
		read contKey
		return 0
	fi
}