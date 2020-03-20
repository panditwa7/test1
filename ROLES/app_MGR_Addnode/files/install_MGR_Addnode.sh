exit 0
version=`ls -td ./CX* | head -1`
cd ./$version/
sudo ./Install_App.sh -P MGR -C ADDTOSG << EOF

y
EOF





