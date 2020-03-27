exit 0
version=`ls -td ./CX* | head -1`
cd ./$version/
sudo ./Install_App.sh -C CLUSTER -P FEM << EOF


y
y
EOF





