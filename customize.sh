[ -f "$MODPATH/skt-utils.sh" ] && . "$MODPATH/skt-utils.sh" || abort '! File "skt-utils.sh" does not exist!'
[ -f "$MODPATH/tools.sh" ] && . "$MODPATH/tools.sh" || abort '! File "tools.sh" does not exist!'
# [ -f "$MODPATH/prebuilt_tools/cpython-arm64.tar.xz" ] || abort '! Missing prebuilt python3'
. "$MODPATH/patch/FUC_STR.sh"
. "$MODPATH/patch/MODULE_MAP.sh"


# PATH init
[ ! -f /data/opbatt ] && mkdir -p /data/opbatt
[ -f /data/opbatt/kernellog ] && rm -rf /data/opbatt/kernellog

export PATH="$MODPATH/bin:$MODPATH/prebuilt_tools/bin:$PATH"
export PYTHONHOME="$MODPATH/prebuilt_tools"
export LD_LIBRARY_PATH="$MODPATH/prebuilt_tools/lib:$MODPATH/prebuilt_tools/bin:$LD_LIBRARY_PATH"

chmod +x $MODPATH/bin/*

# SETUP_PREBUILT
chmod +x $MODPATH/prebuilt_tools/bin/*

cp -a $MODPATH/module.prop $MODPATH/module.prop.bak

for f in "$MODPATH"/patch/*; do
    [ -f "$f" ] || continue
    dos2unix "$f" >/dev/null 2>&1
done

INSTALLMODE="KSU"
debug=1
AVBSTATE=0

osver=$(getprop ro.build.version.release)
model=$(getprop ro.product.vendor.name)
slot_suffix="$(getprop ro.boot.slot_suffix)"
CONFIG_FILE="/data/opbatt_$model.conf"

DTBO_PARTI="/dev/block/bootdevice/by-name/dtbo${slot_suffix}"
DTBOTMP="${TMPDIR}/dtbo.img"
dd if=$DTBO_PARTI of=$DTBOTMP conv=fsync
ui_print_br
GETVERITY_STATE
GETAVBINFO
ui_print_br
wait

#################################start####################################

ui_print "- OPlus 电池工具包"
ui_print ""

if ! grep -q "^$model=" "$MODPATH/patch/MODULE_MAP.sh"; then
    ui_print "⚠️ 非支持机型，退出安装"
    exit 1
else
    patch_dir=$(grep "^$model=" "$MODPATH/patch/MODULE_MAP.sh" | cut -d'=' -f2)
    
    if [ -d "$MODPATH/patch/$patch_dir" ]; then
        PATCH_PATH="$MODPATH/patch/$patch_dir"
    else
        ui_print "⚠️ 找不到补丁目录"
        exit 1
    fi
fi


ui_print "- 机型代号: $model"
ui_print ""

ui_print "- 系统版本：$osver"

if [ "$BOOTMODE" ] && [ "$KSU" ]; then
    ui_print "- 使用KernelSu模式安装，此模式支持WebUI显示"
    elif [ "$BOOTMODE" ] && [ "$MAGISK_VER_CODE" ]; then
    ui_print "- 使用Magisk模式安装，需安装Ksuwebui应用。"
    INSTALLMODE="MAGISK"
fi
ui_print "- 部分utils脚本来自于酷安@芙洛洛"
ui_print "- Python3预编译来源@破星"
ui_print ""


[ -e "/sys/firmware/devicetree/base/soc/author/author" ] && ui_print "- 发现内核dtbo复写程序，dtbo修改可能不生效"


ui_print_br
ui_print "- ⚠️⚠️⚠️请勿触摸屏幕⚠️⚠️⚠️ -"
ui_print "- ⚠️⚠️⚠️请勿触摸屏幕⚠️⚠️⚠️ -"
ui_print "- ⚠️⚠️⚠️请勿触摸屏幕⚠️⚠️⚠️ -"
ui_print_br


#prepare_patch_files
load_config_keys
pr_patch_readme
set_default_config

config_changed=0

if [ -f "$CONFIG_FILE" ]; then
    ui_print_br
    ui_print ""
    ui_print "- 检测到配置文件，是否使用已有配置"
    ui_print "！注：原有配置中如有不存在的功能，会默认选择+"
    ui_print ""
    ui_print "! 音量+ ：是"
    ui_print "! 音量- ：否"
    ui_print ""
    
    . "$CONFIG_FILE"
    
    eval "keys=\${${model}_CONFIG_KEYS}"
    
    for key in $keys; do
        eval "val=\${$key:-UNDEFINED}"
        if [ "$val" = "UNDEFINED" ]; then
            config_changed=1
            break
        fi
    done
    
    case "$(until_key)" in
        up)
            if [ "$config_changed" -eq 1 ]; then
                ui_print "！ 检测到配置有变化，将使用默认值覆盖缺失项"
            else
                ui_print "- 已选择 使用上次已选择配置"
            fi
            use_last_config
        ;;
        down)
            ui_print "- 已选择 重新选择模块功能"
            warning_info
            choo_option
        ;;
    esac
    ui_print_br
else
    ui_print "- 未检测到配置文件，使用全新配置"
    warning_info
    choo_option
fi
#######################################################################################################

pr_choo_option

ui_print "- 覆盖恒压配置"
mv ${PATCH_PATH}/batt_control /data/opbatt/batt_control

if [ "${patch_batt_therm}" -eq 0 ]; then
    cat <<-EOF | cat - /data/opbatt/batt_control > /data/opbatt/batt_control.tmp
temp_range=42,43,44,45,46
temp_curr_offset=800,1200,1800,2500,4500
EOF
else
    cat <<-EOF | cat - /data/opbatt/batt_control > /data/opbatt/batt_control.tmp
temp_range=39,40,41,42,43
temp_curr_offset=500,1000,1500,2000,4000
EOF
fi

mv /data/opbatt/batt_control.tmp /data/opbatt/batt_control

REPACKDTBO
AVBSIGIN $DTBOTMP
ui_print ""
ui_print "⚠️ 刷入中，请勿关机"
dd if=$DTBOTMP of=$DTBO_PARTI conv=fsync
dd if=$DTBO_PARTI of=$MODPATH/dtbo.img conv=fsync
wait
ui_print ""
ui_print "- 重启时务必确保充电器断开，使解容以及FCC统计修复修改生效"
ui_print ""

#sleep 30
jz_install_finish
skt_mod_install_finish
# rm -rf /data/adb/modules*/fopbatt
