version=`ls -td ./CX* | head -1`
cd ./$version/
sudo ./Install_App.sh -C CLUSTER -P MGR << EOF

y
y
EOF





