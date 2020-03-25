version=`ls -td ./CX* | head -1`
cd ./$version/
./Install_App.sh -P MGR -C ADDTOSG << EOF

y
EOF





