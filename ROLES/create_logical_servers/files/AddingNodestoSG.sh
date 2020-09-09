#!/bin/ksh

# MM_UTILITY is not adding SG to cluster when inputs are given from stdin (cat <server>.in | sudo ./MM_UTILITY), only when inputs are given in interactive mode from terminal
# This script will add FM and OM Services Groups to all nodes in cluster.

if [ -f /opt/VRTSvcs/bin/hagrp ]; then

    servers=`/opt/VRTSvcs/bin/hagrp -state | awk '{print $1}' | egrep "^FM_.*_grp|^OM_.*_grp" |sort | uniq`
    clus_members=`/opt/VRTSvcs/bin/hasys -list`

    conf_stat=`/opt/VRTSvcs/bin/haclus -value ReadOnly`
    if [ ${conf_stat} -eq 1 ]
    then
        echo "\n--> Making Cluster Configuration RE-Writable"
        #/opt/VRTSvcs/bin/haconf -makerw
        sleep 5
    fi

    for server in ${servers}
    do
        for clus_member in ${clus_members}
        do
            /opt/VRTSvcs/bin/hagrp -state ${server} 2>/dev/null |  awk '{print $3}' | grep -w "^${clus_member}$"
            [ $? -ne 0 ] && {
                sys_idx=`/opt/VRTSvcs/bin/hagrp -value ${server} SystemList |awk '{print $NF}'|uniq|sort -n|tail -1`
                sys_idx=`expr ${sys_idx} + 1`
                echo "\n--> Adding ${server} to ${clus_member}, id: ${sys_idx}"
                #/opt/VRTSvcs/bin/hagrp -modify ${server} SystemList -add ${clus_member} ${sys_idx}
                #/opt/VRTSvcs/bin/hagrp -modify ${server} AutoStartList -add ${clus_member}
                sleep 3
            }
        done
    done
fi

conf_stat=`/opt/VRTSvcs/bin/haclus -value ReadOnly`
if [ ${conf_stat} -eq 0 ]
then
    echo "\n--> Making Cluster Configuration Read-Only"
    #/opt/VRTSvcs/bin/haconf -dump -makero
    sleep 3
fi