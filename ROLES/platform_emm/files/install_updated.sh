# Use this file in case of external disks are going to be used
# If -F VRTS: from vxdisk list output update <mmstorage disk> and <mmdb disk>
# If IO_Fencing_Type: CPS also update 3 io fencing disks from vxdisk list output
# If -F NFS or Upgrades or -O NODG, then remove the lines for disks
vxdisk list
sudo ./Install_Platform.sh -C $1 -E $2 $3 << EOF
y
y
<mmstorage disk>
<mmdb disk>
<io fencing disk1>
<io fencing disk2>
<io fencing disk3>
y
y
y
EOF