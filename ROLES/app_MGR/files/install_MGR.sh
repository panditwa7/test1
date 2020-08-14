#version=`ls -td ./CX* | head -1`
#cd ./$version/
sudo ./Install_App.sh -C $1 -P MGR $2 -M LOCAL << EOF
..
y
y
EOF