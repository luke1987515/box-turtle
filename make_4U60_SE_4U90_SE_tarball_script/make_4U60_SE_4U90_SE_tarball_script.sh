#!/bin/bash
# 此檔案由 Sheirr 請 峯哥 製作 4U60_SE_4U90_SE.tar 製作腳本
# Luke 於 2024-05-16T11:24:27+08:00 新增防呆操作

#後續修改Edge FW VER
VER=3A63
#後續修改Hub FW VER
HUBVER=3A62

current_path=$(pwd)
echo "目前所在資料夾路徑為：$current_path"

#原始檔案位置
#ORGfolder=/mnt/c/Users/sheirr.lin/Desktop/TMP/4U60_SE_4U90_SE_FW
ORGfolder=$current_path/4U60_SE_4U90_SE_FW
#Rename檔案位置
#NEWfolder=/mnt/c/Users/sheirr.lin/Desktop/TMP/4U60_SE_4U90_SE_FW/NEW
NEWfolder=$current_path/4U60_SE_4U90_SE_FW/NEW

if [ ! -d $ORGfolder ];then mkdir $ORGfolder; chmod 777 $ORGfolder;fi
if [ ! -d $NEWfolder ];then mkdir $NEWfolder; chmod 777 $NEWfolder;fi
#ll $ORGfolder > 123.txt
echo "========================="
echo "=   Create Edge files   ="
echo "========================="
echo -n "Check if Edge firmware exist or not ... "
K=`ls -l $ORGfolder|grep -v "Edge"|grep -c "fw$VER"`
if [ "$K" != "0" ];then 
  echo "$K File(s) found"
  fw=yes
else 
  echo "Not found !! "
  fw=no
fi
echo -n "Check if Edge mfg exist or not ... "
K1=`ls -l $ORGfolder|grep -c "mfg$VER"`
if [ "$K1" != "0" ];then 
  echo "$K1 File found"
  mfg=yes
else 
  echo "Not found !! "
  mfg=no
fi
if [ "$fw" == "yes" ]; then
  for PP in Edge0 Edge1 Edge2 ;do
    ORGFW1=`ls -l $ORGfolder|grep fw$VER|awk '{print $NF}'|cut -d_ -f1`
    ORGFW2=`ls -l $ORGfolder|grep fw$VER|awk '{print $NF}'|cut -d_ -f2-`
    NEWFW1=`echo "$ORGFW1"_"$PP"`
    ORGFW="$ORGFW1"_"$ORGFW2"
    NEWFW=`echo "$NEWFW1"_"$ORGFW2"`
    #echo ORG FW = $ORGFW
    #echo NEW FW = $NEWFW
    echo "Copy $PP firmware file to NEW folder ..."
    cp $ORGfolder/$ORGFW $NEWfolder/$NEWFW
  done
fi  
if [ "$mfg" == "yes" ]; then
  for PP in Edge0 Edge1 Edge2 ;do
    ORGmfg1=`ls -l $ORGfolder|grep mfg$VER|awk '{print $NF}'|cut -d_ -f1`
    ORGmfg2=`ls -l $ORGfolder|grep mfg$VER|awk '{print $NF}'|cut -d_ -f2-`
    NEWmfg1=`echo "$ORGmfg1"_"$PP"`
    ORGmfg="$ORGmfg1"_"$ORGmfg2"
    NEWmfg=`echo "$NEWmfg1"_"$ORGmfg2"`
    #echo ORG mfg = $ORGmfg
    #echo NEW mfg = $NEWmfg
    echo "Copy $PP mfg file to NEW folder ..."
    cp $ORGfolder/$ORGmfg $NEWfolder/$NEWmfg
  done
fi  
echo "========================"
echo "=   Create HUB files   ="
echo "========================"
fw=no
mfg=no
PP=Hub
echo -n "Check if Hub firmware exist or not ... "
K2=`ls -l $ORGfolder|grep -v "HUBEdge"|grep -c "fw$HUBVER"`
if [ "$K2" != "0" ];then 
  echo "$K2 File(s) found"
  fw=yes
else 
  echo "Not found !! "
  fw=no
fi
echo -n "Check if Hub mfg exist or not ... "
K3=`ls -l $ORGfolder|grep -c "mfg$HUBVER"`
if [ "$K3" != "0" ];then 
  echo "$K1 File found"
  mfg=yes
else 
  echo "Not found !! "
  mfg=no
fi
if [ "$fw" == "yes" ]; then
  ORGFW1=`ls -l $ORGfolder|grep fw$HUBVER|awk '{print $NF}'|cut -d_ -f1`
  ORGFW2=`ls -l $ORGfolder|grep fw$HUBVER|awk '{print $NF}'|cut -d_ -f2-`
  NEWFW1=`echo "$ORGFW1"_Hub`
  ORGFW="$ORGFW1"_"$ORGFW2"
  NEWFW=`echo "$NEWFW1"_"$ORGFW2"`
  echo "Copy $PP firmware file to NEW folder ..."
  cp $ORGfolder/$ORGFW $NEWfolder/$NEWFW
fi  
if [ "$mfg" == "yes" ]; then
  ORGmfg1=`ls -l $ORGfolder|grep mfg$HUBVER|awk '{print $NF}'|cut -d_ -f1`
  ORGmfg2=`ls -l $ORGfolder|grep mfg$HUBVER|awk '{print $NF}'|cut -d_ -f2-`
  NEWmfg1=`echo "$ORGmfg1"_Hub`
  ORGmfg="$ORGmfg1"_"$ORGmfg2"
  NEWmfg=`echo "$NEWmfg1"_"$ORGmfg2"`
  echo "Copy $PP mfg file to NEW folder ..."
  cp $ORGfolder/$ORGmfg $NEWfolder/$NEWmfg
fi  
echo
cd $NEWfolder
if [ -f 4U60_SE_4U90_SE.tar ];then rm 4U60_SE_4U90_SE.tar;fi
if [ -z "$(ls -A "$NEWfolder")" ]; then
  echo "請在 4U60_SE_4U90_SE_FW 放入原始 FW & MFG"
else  
  tar -cvf 4U60_SE_4U90_SE.tar * > /dev/null
  echo "Start tar files completed!!"
fi
echo
cd ..
 

