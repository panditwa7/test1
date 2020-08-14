#version=`ls -td ./CX* | head -1`
#cd ./$version/
sudo ./Install_App.sh -C $1 -P OLM $2 << EOF

y
y
EOF