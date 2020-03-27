exit 0
version=`ls -td ./CX* | head -1`
cd ./$version/
sudo ./Install_Platform.sh -C CPS << EOF

y

EOF