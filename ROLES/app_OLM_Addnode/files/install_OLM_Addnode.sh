version=`ls -td ./CX* | head -1`
cd ./$version/
sudo ./Install_App.sh -P OLM -C ADDTOSG << EOF

y
EOF





