#version=`ls -td ./CX* | head -1`
#cd ./$version/
sudo ./Install_App.sh -P FEM -C ADDTOSG << EOF

y
EOF