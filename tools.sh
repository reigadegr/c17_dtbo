uidebug() {
    [ "$debug" -eq 1 ] && ui_print "| [调试信息]: $@"
}

ui_print_br() {
    ui_print "-------------------------------------"
}

namemark() {
    local modelstr=$(fdtget -t s $1 / model | sed 's/jzmod_.*//g')
    fdtput -t s $1 / model "${modelstr} jzmod_${2}"
}

find_prop_symbols() {
    fdtget $1 /__symbols__ $2
}
find_prop_symbols_head() {
    fdtget $1 /__symbols__ $2 | sed -E 's#^(/fragment@[0-9]+).*#\1#'
}
find_prop_fixups_head() {
    fdtget $1 /__fixups__ $2 | sed -E 's#^(/fragment@[0-9]+).*#\1#'
}

####################################################
#
####################################################
# lfdtput -r/d file symbols path
#          $2   $1    $2    $4
# 根据fragment编号删除
rm_verbose=v
fgrmr_prop() {
    local lpath=$(find_prop_symbols_head $1 $4)
    #ui_print "command is lfdtput -$3 -$rm_verbose $1 $lpath/__overlay__/$5"
    fdtput -$3 -$rm_verbose $1 $lpath/__overlay__/$5 >/dev/null 2>&1
    wait
}

fgfrmr_prop() {
    local lpath=$(find_prop_fixups_head $1 $4)
    #ui_print "command is lfdtput -$3 -$rm_verbose $1 $lpath/__overlay__/$5"
    fdtput -$3 -$rm_verbose $1 $lpath/__overlay__/$5 >/dev/null 2>&1
    wait
}

# lfdtput -r/d file symbols path
#          $2   $1    $2    $4
# 删除节点
rmr_prop() {
    local lpath=$(find_prop_symbols $1 $3)
    fpath="$lpath/$4"
    #ui_print "command is lfdtput -$2 -$rm_verbose $1 $fpath"
    fdtput -$2 -$rm_verbose $1 $fpath >/dev/null 2>&1
    wait
}
# lfdtput -r/d file symbols path
#          $2   $1    $2    $4
# 删除根属性
rmd_prop() {
    local lpath=$(find_prop_symbols $1 $3)
    #ui_print "command is lfdtput -$2 -$rm_verbose $1 $lpath $4"
    fdtput -$2 -$rm_verbose $1 "$lpath" "$4" >/dev/null 2>&1
    wait
}
# lfdtput -r/d file symbols path
#          $2   $1    $2    $4
# 删除带目录得属性
rmdp_prop() {
    local lpath=$(find_prop_symbols $1 $3)
    #ui_print "command is lfdtput -$2 -$rm_verbose $1 $lpath/$4 $5"
    fdtput -$2 -$rm_verbose $1 "$lpath/$4" "$5" >/dev/null 2>&1
    wait
}

rm_proc_from_file() {
    while IFS= read -r line; do
        if [ "$(echo $line | awk '{printf $1}')" == "r" ]; then
            rmr_prop $2 $line
            elif [ "$(echo $line | awk '{printf $1}')" == "d" ]; then
            rmd_prop $2 $line
            elif [ "$(echo $line | awk '{printf $1}')" == "fgr" ]; then
            fgrmr_prop $2 $line
            elif [ "$(echo $line | awk '{printf $1}')" == "fgfr" ]; then
            fgfrmr_prop $2 $line
        fi
    done <$1
}

####################################################
# usage:
# $1 对应音量+的选项提示
# $2 音量+的赋值
# $3 对应音量-的选项提示
# $4 音量-的赋值
# $5 需要操作的变量
# e.g.: choo_by_vol "BMS实际电量值" 1 "官方平滑电量显示" 0 real_soc
choo_by_vol() {
    ui_print_br
    ui_print ""
    ui_print "- 请选择刷入的选项来配置不同功能"
    ui_print "! 音量+ ：$1"
    ui_print "! 音量- ：$3"
    
    case "$(until_key)" in
        up)
            ui_print "- 已选择 $1"
            eval "$5=\"$2\""
            return 0
        ;;
        down)
            ui_print "- 已选择 $3"
            eval "$5=\"$4\""
            return 0
        ;;
    esac
    # uidebug "$5 = $(eval "echo \$$5")"
    ui_print_br
}
####################################################

BUILD_DTOV() {
    for key in $keys; do
        eval "val=\${$key:-0}"
        dts_file="$PATCH_PATH/${key}_${val}.dts"
        [ -f "$dts_file" ] || continue
        uidebug "- 编译: $(basename $dts_file)"
        dtc -@ -I dts -O dtb -o "$(basename $dts_file).m.dtbo" "$dts_file" >/dev/null 2>&1 &
    done
    
    for patch_file in $(ls $PATCH_PATH/force_patch_* 2>/dev/null); do
        uidebug "- 编译: $(basename $patch_file)"
        dtc -@ -I dts -O dtb -o "$(basename $patch_file).m.dtbo" "$patch_file" >/dev/null 2>&1 &
    done
    
    wait
}

PATCH_DTB() {
    
    ################################patch#####################################
    ui_print "- 正在对 $1 打补丁"
    
    for key in $keys; do
        eval "val=\${$key:-0}"
        sh_file="$PATCH_PATH/${key}_${val}.sh"
        [ -f "$sh_file" ] || continue
        #uidebug "- 执行: $(basename $sh_file)"
        . $sh_file $1
    done
    
    for i in $(ls *.m.dtbo); do
        fdtoverlay -i $1 -o $1.m $i >/dev/null 2>&1
        mv $1.m $1
    done
    
    ################################remove#####################################
    ui_print "- 正在对 $1 进行节点删除"
    
    for key in $keys; do
        eval "val=\${$key:-0}"
        case "$key" in
            rm_*)
                rm_file="$PATCH_PATH/$key"
                if [ "$val" -eq 0 ] && [ -f "$rm_file" ]; then
                    rm_proc_from_file "$rm_file" "$1"
                fi
            ;;
        esac
    done
    
    for rm_patch in $(ls $PATCH_PATH/force_rm_* 2>/dev/null); do
        rm_proc_from_file "$rm_patch" "$1"
    done
    
    
    # 打标记
    namemark $1 "$1"
}

SETUP_PREBUILT()
{
    busybox xz -d "$MODPATH/prebuilt_tools/cpython-arm64.tar.xz" || abort '! xz安装包损坏'
    tar xf $MODPATH/prebuilt_tools/cpython-arm64.tar || abort '! tar安装包损坏'
    mv ./prefix/bin/* $MODPATH/prebuilt_tools/bin/
    mv ./prefix/lib/* $MODPATH/prebuilt_tools/lib/
}

SKIP_AVB_FOOTER=0

GETAVBINFO(){
    local USE_STOCK_IMG=0
    local AVB_FOOTER_INFO=0
    
    ui_print "！！！ 正在尝试使用机内DTBO分区读取footer"
    OUTPUT=$($MODPATH/prebuilt_tools/bin/avbtool info_image --image "${DTBOTMP}" 2>/dev/null)
    if [ $? -ne 0 ];then
        ui_print "！！！ 获取机内DTBO AVB footer失败"
        ui_print "！！！ 你可以提供当前系统版本的dtbo镜像用作签名镜像"
        ui_print "！！！ 放入内置存储根目录，并且命名为dtbo_stock.img"
        
        ui_print "！！！ ▶️ 音量+ 使用你提供的dtbo_stock.img"
        ui_print "！！！ ▶️ 音量- 跳过avb footer写入，刷完后自行关闭avb校验"
        KEY=$(until_key)
        if [ "$KEY" == "up" ];then
            USE_STOCK_IMG=1
        fi
        
        if [ "$KEY" == "down" ];then
            ui_print "！！！ 无法获取AVB footer，请确认已关闭AVB校验，否则可能卡fastboot"
            SKIP_AVB_FOOTER=1
            sleep 3
        fi
    else
        ui_print "！！！ 读取机内DTBO分区 footer 成功"
        AVB_FOOTER_INFO=1
    fi
    
    if [ ! -e "/storage/emulated/0/dtbo_stock.img" ] && [ $USE_STOCK_IMG -eq 1 ];then
        ui_print "! 未发现你提供的dtbo_stock.img"
        ui_print "！！！ ▶️ 音量+ 跳过avb footer写入，刷完后自行关闭avb校验"
        ui_print "！！！ ▶️ 音量- 退出"
        KEY=$(until_key)
        if [ "$KEY" == "up" ];then
            SKIP_AVB_FOOTER=1
        fi
        
        if [ "$KEY" == "down" ];then
            exit 1
        fi
    fi
    
    if [ -e "/storage/emulated/0/dtbo_stock.img" ] && [ $AVB_FOOTER_INFO -eq 0 ] && [ $USE_STOCK_IMG -eq 1 ] && [ $SKIP_AVB_FOOTER -eq 0 ] ;then
        ui_print "- 检测到dtbo_stock.img，读取中"
        OUTPUT=$($MODPATH/prebuilt_tools/bin/avbtool info_image --image /storage/emulated/0/dtbo_stock.img)
        if [ $? -eq 0 ];then
            ui_print "- 读取成功，使用你提供的DTBO镜像进行footer提取"
            AVB_FOOTER_INFO=1
        else
            ui_print "! 读取你提供的dtbo_stock.img footer信息失败，可能是镜像有问题"
            GETAVBINFO
        fi
    fi
    
    if [ $AVB_FOOTER_INFO -eq 1 ];then
        PARTITION_SIZE=$(echo "$OUTPUT" | grep "^Image size:" | head -n1 | awk '{print $3}')
        HASH_ALG=$(echo "$OUTPUT" | grep "Hash Algorithm:" | head -n1 | awk '{print $3}')
        PARTITION_NAME=$(echo "$OUTPUT" | grep "Partition Name:" | head -n1 | awk '{print $3}')
        SALT=$(echo "$OUTPUT" | grep "Salt:" | head -n1 | awk '{print $2}')
        ALGORITHM=$(echo "$OUTPUT" | grep "^Algorithm:" | head -n1 | awk '{print $2}')
        ROLLBACK_INDEX=$(echo "$OUTPUT" | grep "Rollback Index:" | head -n1 | awk '{print $3}')
        RELEASE=$(echo "$OUTPUT" | grep "Release String:" | head -n1 | cut -d"'" -f2)
        PROP=$(echo "$OUTPUT" | grep "Prop:" | head -n1 | sed -E "s/^[[:space:]]*Prop:[[:space:]]*([^ ]+) -> '(.*)'/\1:\2/")
        ui_print_br
        ui_print "**** AVB footer info ****"
        ui_print "** partition_size=$PARTITION_SIZE"
        ui_print "** algorithm=$ALGORITHM"
        ui_print "** rollback_index=$ROLLBACK_INDEX"
        ui_print "** internal_release_string='$RELEASE'"
        ui_print "** hash_algorithm=$HASH_ALG"
        ui_print "** salt=$SALT"
        ui_print "** prop='$PROP'"
        ui_print "** partition_name=$PARTITION_NAME"
        ui_print_br
    fi
}

AVBSIGIN()
{
    if [ "$SKIP_AVB_FOOTER" -eq 0 ];then
        $MODPATH/prebuilt_tools/bin/avbtool add_hash_footer \
        --image $1 \
        --partition_size $PARTITION_SIZE \
        --salt $SALT \
        --partition_name $PARTITION_NAME \
        --hash_algorithm $HASH_ALG \
        --algorithm $ALGORITHM \
        --rollback_index $ROLLBACK_INDEX \
        --key $MODPATH/prebuilt_tools/testkey_rsa4096.pem \
        --prop "$PROP" \
        --internal_release_string "$RELEASE"
    else
        ui_print "！ 跳过AVB hash footer写入"
    fi
}

REPACKDTBO() {
    PID="$(printf "%d" "0x$(getprop ro.vendor.product.device.oem | cut -c3-)")"
    ui_print "- 机型代码：$PID"
    ui_print ""
    ui_print "- 开始DTBO修改过程"
    ui_print ""
    ui_print ""
    ui_print "- 解包DTBO中..."
    if ! mkdtimg dump $DTBOTMP -b dtb >/dev/null 2>&1;then
        ui_print "! 解包DTBO失败"
        exit 1
    fi
    wait
    
    ui_print "- 编译补丁中..."
    BUILD_DTOV
    
    ui_print "- 补丁开始"
    for i in dtb.*; do
        # if fdtget -t i $i / oplus,project-id | grep -q $PID; then
        #     ui_print "- 为本机型的${i}进行修改"
        PATCH_DTB $i &
        # else
        #     continue
        # fi
    done
    wait
    ui_print "- 打包DTBO中..."
    if ! mkdtimg create $DTBOTMP --page_size=4096 dtb.* >/dev/null 2>&1;then
        ui_print "! 打包DTBO失败"
        exit 1
    fi
    wait
}

set_default_config() {
    for key in $model_CONFIG_KEYS; do
        eval "$key=0"
    done
}

use_last_config() {
    keys=""
    eval "keys=\${${model}_CONFIG_KEYS}"
    
    FUC_STR=""
    for key in $keys; do
        eval "val=\${$key:-0}"
        FUC_STR="${FUC_STR}${key}=${val}\n"
    done
    
    echo -e "$FUC_STR" > "$CONFIG_FILE"
}

jz_install_finish() {
    ui_print "- 清理临时文件"
    rm -r $MODPATH/bin/fdt*
    rm -r $MODPATH/bin/dtc
    rm -r $MODPATH/bin/mkdtimg
    rm -r $MODPATH/prebuilt_tools
    rm -r $MODPATH/patch
}

warning_info() {
    ui_print_br
    ui_print ""
    ui_print "- ⚠️注意事项⚠️ -"
    ui_print ""
    ui_print "- 以下步骤必须同意后才可以刷入"
    ui_print "- 1、刷入过程中发现选错，可退出重新刷入。"
    ui_print "- 2、提示“刷入中”时，请勿关机！！"
    ui_print "- 3、修改电池温控和其他温控可能导致电池起火或机器损坏！！"
    ui_print "- 4、解容会使电池老化！！"
    ui_print "- 5、如有不懂请查询官网！！"
    ui_print "- https://op13batt.heypiqi.com/"
    ui_print ""
    ui_print "- 你同意这么做么？"
    ui_print ""
    ui_print "! 音量+ ：是"
    ui_print "! 音量- ：否"
    ui_print ""
    case "$(until_key)" in
        up)
            ui_print "- 已选择 我已阅读以上条款，并且所带来的后果由我自己承担！！"
            return 0
        ;;
        down)
            ui_print "- 已选择 不同意以上条款，退出安装"
            exit 1
        ;;
    esac
    ui_print_br
}

#########################################################################
choo_option() {
    keys=""
    eval "keys=\${${model}_CONFIG_KEYS}"
    
    FUC_STR=""
    for key in $keys; do
        eval "desc0=\${${key}_text_0:-<无说明>}"
        eval "desc1=\${${key}_text_1:-<无说明>}"
        
        choo_by_vol "$desc1" 1 "$desc0" 0 "$key"
        
        eval "val=\${$key:-0}"
        FUC_STR="${FUC_STR}${key}=${val}\n"
    done
    
    echo -e "$FUC_STR" > "$CONFIG_FILE"
    ui_print "- 写入配置"
}

pr_choo_option() {
    ui_print "当前配置 ($model)："
    
    for key in $keys; do
        eval "val=\${$key:-0}"
        # eval "desc=\${${key}_text_${val}:-<无说明>}"
        ui_print " - $key = $val"
    done
}

pr_patch_readme()
{
    [ -f "$PATCH_PATH/README.txt" ] && cat "$PATCH_PATH/README.txt" | while read line; do ui_print "$line"; done
    #[ -f "$PATCH_PATH/README.txt" ] && ui_print $(cat "$PATCH_PATH/README.txt")
}

load_config_keys() {
    keys=""
    
    for file in $(ls "$PATCH_PATH"/rm_* "$PATCH_PATH"/patch_* "$PATCH_PATH"/sh_patch_* 2>/dev/null); do
        [ -f "$file" ] || continue
        filename=$(basename "$file")
        key=$(echo "$filename" | sed -E 's/(_[01])?\.[^.]+$//')
        keys="$keys $key"
    done
    
    keys=$(echo $keys | xargs -n1 | sort -u | xargs)
    
    eval "${model}_CONFIG_KEYS=\"$keys\""
    if [ -z "$keys" ]; then
        ui_print "未检测到($model)可用补丁，仅安装WebUI。"
    else
        ui_print_br
        ui_print "🔹 已加载补丁 ($model): "
        for k in $keys; do
            ui_print "   - $k"
        done
        ui_print_br
    fi
    
    
}

prepare_patch_files() {
    for file in "$PATCH_PATH"/*; do
        filename=$(basename "$file")
        
        file_ver=$(echo "$filename" | sed -n 's/.*_c\([0-9]\+\)\(\..*\)$/\1/p')
        if [ -n "$file_ver" ]; then
            if [ "$file_ver" != "$osver" ]; then
                rm -f "$file"
            else
                newname=$(echo "$filename" | sed "s/_c${osver}//")
                mv "$file" "$PATCH_PATH/$newname"
            fi
        fi
    done
}

GETVERITY_STATE()
{
    if $MODPATH/bin/avbctl get-verity | grep -q "disabled"; then
        AVBVERIFY=0
    else
        AVBVERIFY=1
    fi
    
    if $MODPATH/bin/avbctl get-verification | grep -q "disabled"; then
        AVBVERIFICATION=0
    else
        AVBVERIFICATION=1
    fi
    
    if [ $AVBVERIFY -eq 0 ] && [ $AVBVERIFICATION -eq 0 ]; then
        AVBSTATE=0
    else
        AVBSTATE=1
    fi
    ui_print "! AVB2.0 状态: $AVBVERIFY|$AVBVERIFICATION"
}
