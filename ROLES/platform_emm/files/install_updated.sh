# Use this file in case of external disks are going to be used
# If -F VRTS: from vxdisk list output update <mmstorage disk> and <mmdb disk>
# If IO_Fencing_Type: CPS also update 3 io fencing disks from vxdisk list output
vxdisk list
sudo ./Install_Platform.sh -C $1 -E $2 $3 << EOF
y
y
mmstorage_disk
mmdb_disk
io_fencing_disk1
io_fencing_disk2
io_fencing_disk3
y
y
y
EOF