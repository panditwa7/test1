#version=`ls -td ./CX* | head -1`
#cd ./$version/
sudo ./Install_Platform.sh -C ADDNODE -E $1 $2 << EOF

y
y
y
EOF