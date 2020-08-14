#version=`ls -td ./CX* | head -1`
#cd ./$version/
#sudo ./Install_Platform.sh -C CLUSTER -E external -F NFS << EOF
sudo ./Install_Platform.sh -C $1 -E $2 $3 << EOF

y
y
y
y

EOF