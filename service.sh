
MODDIR=${0%/*}
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 10
done

# 率先更新充电器配置
$MODDIR/bin/chg_ctl load_config 2> /dev/null
$MODDIR/bin/ioauth ufcs 2> /dev/null &

MAX_SIZE=$((5 * 1024 * 1024))
LOGFILE="/data/opbatt/battchg.log"
[ ! -e $LOGFILE ] && touch $LOGFILE
FILE_SIZE=$(stat -c %s "$LOGFILE" 2>/dev/null)
[ "$FILE_SIZE" -gt "$MAX_SIZE" ] && : > "$LOGFILE"

cp -av $MODDIR/module.prop.bak $MODDIR/module.prop

BB=${MODDIR}/bin/busybox
OPB_C=${MODDIR}/bin/opbatt_control
chmod +x $OPB_C

chmod +x $BB
# 刷新最低值
FOO_PATH="/sys/class/oplus_chg/common"
origin_ddc=$(cat $FOO_PATH/deep_dischg_counts)
echo 1 > $FOO_PATH/deep_dischg_counts
echo 1 > $FOO_PATH/deep_dischg_count_cali
echo $origin_ddc > $FOO_PATH/deep_dischg_counts
echo 0 > $FOO_PATH/deep_dischg_count_cali

#检测dtb是否一致
DTBO_PARTI="/dev/block/bootdevice/by-name/dtbo$(getprop ro.boot.slot_suffix)"
DTBOIMG="${MODDIR}/dtbo.img"
MD5DTBOIMG=$($BB md5sum $DTBOIMG | $BB awk '{printf $1}')
MD5PARTI=$($BB md5sum $DTBO_PARTI| $BB awk '{printf $1}')
errimg=0
[ "$MD5DTBOIMG" != "$MD5PARTI" ] && errimg=1
of_overwriter=0

#防止prop文件失效
modifyfile=$MODDIR/module.prop

GETVAR() {
    
    chgdata="Oplus_chg_v2框架 WebUi监控面板"
    
    [ $errimg -eq "1" ] && chgdata="${chgdata}|❌️DTBO镜像已被修改，请重新刷入模块。"
    [ -e "/sys/firmware/devicetree/base/soc/author/author" ] &&
    chgdata="${chgdata}|⚠️发现内核dtbo复写程序,dtbo修改可能不生效"
}

UPDATEPARM()
{
    sed -i 's/^description=.*/description='"${chgdata}"'/g' $modifyfile
}

BATT_PATH="/sys/class/oplus_chg/battery"
BCC_CUR=13700
BCC="$BATT_PATH/bcc_current"
NCD="$BATT_PATH/normal_cool_down"
CD="$BATT_PATH/cool_down"
chmod 0644 $BCC
chmod 0644 $NCD
chmod 0644 $CD
echo 0 >$CD
echo 0 >$NCD
echo $BCC_CUR >$BCC

chmod 0400 $BCC
chmod 0400 $NCD
chmod 0400 $CD
# fixed hidl voter
chmod 0444 /sys/class/power_supply/battery/current_now

while true;do
    LOGPREFIX="[$(date +%Y-%m-%d-%H:%M:%S)][module]"
    GETVAR
    UPDATEPARM
    echo "=====================MODULE start==========================" >> $LOGFILE
    echo "$LOGPREFIX [service.sh] start" >> $LOGFILE
    $OPB_C >> $LOGFILE
    OPB_CRET=$?
    echo "$LOGPREFIX [service.sh] REBOOTED exit code(${OPB_CRET})" >> $LOGFILE
    case $OPB_CRET in
        1|2)
            echo "$LOGPREFIX [service.sh] 等待验证中，10秒后重试..." >> $LOGFILE
            sleep 10
        ;;
        3|4|5|6)
            echo "$LOGPREFIX [service.sh] 服务异常, 2秒后尝试重启" >> $LOGFILE
            sleep 10
        ;;
        *)
            sleep 10
        ;;
    esac
done