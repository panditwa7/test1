version=`ls -td ./CX* | head -1`
cd ./$version/
sudo ./Install_Platform.sh -C ADDNODE -E external -F NFS << EOF

y
y
y
EOF


