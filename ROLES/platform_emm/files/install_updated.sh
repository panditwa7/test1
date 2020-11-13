version=`ls -td ./CX* | head -1`
cd ./$version/
sudo ./Install_Platform.sh -C CLUSTER -E external -F VRTS << EOF
y
y
rhel_vmdk0_0
rhel_vmdk0_2
y
y
y
y
EOF
