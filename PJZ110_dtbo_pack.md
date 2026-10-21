# PJZ110 DTBO 打包、签名与刷入流程

本文说明 `0aO电池工具包` 在安装时如何把 DTS 补丁变成可刷入的 `dtbo` 分区镜像。命令与分支逻辑取自 `customize.sh`、`tools.sh`，行号对应当前提交。

## 0. 参与的文件与工具

| 名称 | 来源 | 用途 |
|---|---|---|
| `DTBO_PARTI` | `customize.sh:37` | `/dev/block/bootdevice/by-name/dtbo${slot_suffix}`，当前槽位的 dtbo 分区 |
| `DTBOTMP` | `customize.sh` | `${TMPDIR}/dtbo.img`，分区镜像的临时副本 |
| `dtb.N` | `mkdtimg dump` 生成 | 镜像里的每个 DTBO 条目（每个项目/机型变体一份） |
| `*.m.dtbo` | `dtc` 生成 | 编译后的 overlay，供 `fdtoverlay` 合并 |
| `dtc` / `mkdtimg` / `fdtoverlay` / `fdtget` / `fdtput` | `$MODPATH/bin` | 设备端 DTBO 工具 |
| `avbtool` | `$MODPATH/prebuilt_tools/bin` | 读取和写入 AVB footer |
| `avbctl` | `$MODPATH/bin` | 只读查询 verity/verification 状态 |
| `testkey_rsa4096.pem` | `$MODPATH/prebuilt_tools` | 模块自带的签名私钥 |

`customize.sh` 把 `$MODPATH/bin` 和 `$MODPATH/prebuilt_tools/bin` 加进 `PATH`，并设置 `PYTHONHOME`、`LD_LIBRARY_PATH` 供预编译 Python 版 `avbtool` 使用。`SETUP_PREBUILT` 目前被注释掉，预编译工具已随模块提供；安装结束的 `jz_install_finish` 会删除 `patch/`、`prebuilt_tools/` 和 `bin/dtc`、`bin/mkdtimg`、`bin/fdt*`，所以打包只能发生在安装过程中。

## 1. 取出当前分区

```sh
dd if=$DTBO_PARTI of=$DTBOTMP conv=fsync
```

取的是整个 dtbo 分区，包含末尾的 AVB footer。`conv=fsync` 确保落盘后再读。

## 2. 拆成独立条目

```sh
mkdtimg dump $DTBOTMP -b dtb
```

在当前工作目录生成 `dtb.0`、`dtb.1`……每个文件是一个完整 DTBO 条目。`-b dtb` 指定输出前缀。拆包失败会直接 `exit 1`（`tools.sh:293-296`）。

`dts.dtb.5` 是其中一个条目反编译后的文本，按命名对应 `dtb.5`（第 6 个条目，从 0 开始数）。它是人工分析用的参考文件，模块安装不会读取它。

## 3. 编译选中的 DTS

`BUILD_DTOV`（`tools.sh:120-135`）遍历当前机型的选项键：

```sh
for key in $keys; do
    eval "val=\${$key:-0}"
    dts_file="$PATCH_PATH/${key}_${val}.dts"
    [ -f "$dts_file" ] || continue
    dtc -@ -I dts -O dtb -o "$(basename $dts_file).m.dtbo" "$dts_file" &
done

for patch_file in $(ls $PATCH_PATH/force_patch_* 2>/dev/null); do
    dtc -@ -I dts -O dtb -o "$(basename $patch_file).m.dtbo" "$patch_file" &
done
```

要点：

- 每个选项只编译被选中的那一个变体，例如 `patch_ddrc=1` 只编译 `patch_ddrc_1.dts`，不会把 `_0` 和 `_1` 一起合并。
- `-@` 必须保留，它把 label 写进 `__symbols__`，`fdtoverlay` 才能解析 `&oplus_mms_gauge` 这类引用。
- 输出名是 `<dts 文件名>.m.dtbo`，例如 `patch_ddrc_1.dts.m.dtbo`。
- `dtc` 失败只会在后台静默失败，后续 apply 阶段找不到 `.m.dtbo` 就跳过；不会中止安装。

## 4. 对每个 dtb 打补丁

`REPACKDTBO`（`tools.sh:285-318`）遍历所有 `dtb.*`：

```sh
for i in dtb.*; do
    # if fdtget -t i $i / oplus,project-id | grep -q $PID; then
    #     ui_print "- 为本机型的${i}进行修改"
    PATCH_DTB $i &
    # else
    #     continue
    # fi
done
wait
```

注意按 `project-id` 过滤的代码被注释掉了，实际是**对镜像里的每个项目变体都打同一套补丁**。`PID` 只用于打印机型代码，不参与筛选。所有任务并发执行，最后 `wait`。

`PATCH_DTB`（`tools.sh:137-177`）对单个 dtb 的执行顺序是：

1. 执行选中的 `sh_patch_*` 脚本，例如 `sh_patch_hm_1.sh` 用 `fdtget/fdtput` 改写 `oplus,hmbird/version_type`。
2. 对目录下每个 `.m.dtbo` 执行：

```sh
fdtoverlay -i $1 -o $1.m $i
mv $1.m $1
```

`fdtoverlay` 把 overlay 按 label 合并进目标 dtb。命令失败时不会生成 `$1.m`，随后的 `mv` 也失败，原 dtb 保持不变——是静默跳过，不是报错退出。

3. 处理删除清单：值为 0 的 `rm_*` 和始终执行的 `force_rm_*`，由 `rm_proc_from_file` 逐行解析，`r` 用 `fdtput -r` 删节点，`d` 用 `fdtput -d` 删属性。
4. `namemark` 在根节点 `model` 字符串末尾追加 ` jzmod_<dtb文件名>`，作为已处理标记：

```sh
fdtget -t s $1 / model | sed 's/jzmod_.*//g'
fdtput -t s $1 / model "${modelstr} jzmod_${2}"
```

## 5. 重新打包

```sh
mkdtimg create $DTBOTMP --page_size=4096 dtb.*
```

- `--page_size=4096` 必须与原镜像一致，否则 bootloader 可能拒绝。
- 输出直接覆盖 `$DTBOTMP`，此时还没有 AVB footer。
- `dtb.*` 的传入顺序就是 shell glob 的字典序（`dtb.0`、`dtb.1`、`dtb.10`、`dtb.2`……）。条目 ID 的推导方式取决于 `mkdtimg` 版本，不能想当然认为顺序无关；手工打包时建议显式列出文件，并保持与原镜像一致的条目数量和顺序。
- 打包失败会 `exit 1`（`tools.sh:313-316`）。

## 6. 读取原 AVB 参数

`customize.sh` 的顺序是：先 `dd` 取分区、`GETVERITY_STATE`、`GETAVBINFO`，最后才 `REPACKDTBO`。也就是说，AVB 参数是在补丁前从原镜像读的。

`GETAVBINFO`（`tools.sh:189-264`）执行：

```sh
avbtool info_image --image $DTBOTMP
```

并解析出：

| 字段 | 变量 | 用途 |
|---|---|---|
| `Image size` | `PARTITION_SIZE` | 重签时的分区大小 |
| `Algorithm` | `ALGORITHM` | 例如 `SHA256_RSA4096` |
| `Hash Algorithm` | `HASH_ALG` | 内容摘要算法 |
| `Salt` | `SALT` | 原 footer 的 salt |
| `Partition Name` | `PARTITION_NAME` | 通常是 `dtbo` |
| `Rollback Index` | `ROLLBACK_INDEX` | 防回滚索引 |
| `Release String` | `RELEASE` | 原厂 release 字符串 |
| `Prop` | `PROP` | 原 footer 里的属性键值 |

脚本对 `Prop` 和 `Release String` 只取 `head -n1` / 第一条，原 footer 若包含多条 prop，重签后只会保留第一条。这是脚本当前的限制。

读取失败时有两个分支：

- 音量+：使用内置存储根目录的 `dtbo_stock.img` 作为参数来源；文件不存在则再让用户选择跳过签名或退出。
- 音量-：`SKIP_AVB_FOOTER=1`，跳过 footer 写入，并提示刷完后自行关闭 AVB 校验。

## 7. 写入 AVB footer

`AVBSIGIN`（`tools.sh:266-283`）：

```sh
avbtool add_hash_footer \
    --image $DTBOTMP \
    --partition_size $PARTITION_SIZE \
    --salt $SALT \
    --partition_name $PARTITION_NAME \
    --hash_algorithm $HASH_ALG \
    --algorithm $ALGORITHM \
    --rollback_index $ROLLBACK_INDEX \
    --key $MODPATH/prebuilt_tools/testkey_rsa4096.pem \
    --prop "$PROP" \
    --internal_release_string "$RELEASE"
```

这一步会把镜像补齐到 `PARTITION_SIZE`，在末尾生成 hash descriptor 和签名。salt、算法、rollback index、prop、release string 都沿用原 footer，只有签名私钥换成了模块自带的 `testkey_rsa4096.pem`。

这里要特别注意：`testkey_rsa4096.pem` 不是原厂私钥。重签后 footer 结构合法，但**不等于恢复了原厂信任链**。如果设备的 AVB 校验仍然开启，而 `dtbo` 又挂在 `vbmeta` 的链式校验里，原厂 `vbmeta` 不会认可这把 key。模块只是用 `avbctl get-verity` / `get-verification` 打印状态（`AVBSTATE` 计算后并未用于中止安装），所以刷入前应确认 verity/verification 已关闭，或使用与之匹配的自定义 `vbmeta`。

若 `SKIP_AVB_FOOTER=1`，`AVBSIGIN` 只打印“跳过 AVB hash footer 写入”，不执行签名。

## 8. 写回分区并留档

```sh
dd if=$DTBOTMP of=$DTBO_PARTI conv=fsync
dd if=$DTBO_PARTI of=$MODPATH/dtbo.img conv=fsync
```

第一条把新镜像写回当前槽位的 dtbo 分区，第二条把分区内容重新读出，保存为模块内的 `dtbo.img`。`service.sh` 每次开机用这个文件与分区做 md5 对比；不一致时会在模块描述里提示“DTBO 镜像已被修改，请重新刷入模块”。

`dd` 和 `AVBSIGIN` 都没有显式的返回值检查，写入失败不会中止安装，这是脚本目前的行为，手工操作时应自己核对退出码。

## 9. 手工复现（只改 `dts.dtb.5` 这一条目）

如果不想跑模块，只想在已导出的条目上复现：

```sh
# 1. 记录原分区（在设备上）
adb shell su -c 'dd if=/dev/block/bootdevice/by-name/dtbo of=/sdcard/dtbo_stock.img'

# 2. 拆条目（PC 或设备端的 mkdtimg）
mkdtimg dump dtbo_stock.img -b dtb

# 3. 修改文本后回编译（完整 dtb 不需要 -@，-@ 是给 overlay 用的）
dtc -I dts -O dtb -o dtb.5.new dts.dtb.5
mv dtb.5 dtb.5.orig
mv dtb.5.new dtb.5

# 4. 显式列出全部条目重新打包，避免 glob 顺序问题
mkdtimg create dtbo_new.img --page_size=4096 \
    dtb.0 dtb.1 dtb.2 dtb.3 dtb.4 dtb.5

# 5. 读取原参数并签名
avbtool info_image --image dtbo_stock.img
avbtool add_hash_footer --image dtbo_new.img \
    --partition_size <Image size> \
    --salt <Salt> \
    --partition_name <Partition Name> \
    --hash_algorithm <Hash Algorithm> \
    --algorithm <Algorithm> \
    --rollback_index <Rollback Index> \
    --key testkey_rsa4096.pem \
    --prop "<Prop>" \
    --internal_release_string "<Release String>"

# 6. 刷入（按 ro.boot.slot_suffix 选择 dtbo_a 或 dtbo_b）
adb shell su -c 'dd if=/sdcard/dtbo_new.img of=/dev/block/bootdevice/by-name/dtbo_a'
```

三个前提：

- 条目数量和顺序要与原镜像一致，这里假设原镜像正好有 `dtb.0` 到 `dtb.5`；实际以 `mkdtimg dump` 的输出为准。
- `dts.dtb.5` 是其中一个项目变体，改它只影响该变体。它当前的 `model` 是 `Qualcomm Technologies, Inc. Sun MTP,dodge`，`qcom,board-id = <0x40008 0x0>`，`oplus,project-id = <0x5d0d>`；先确认 bootloader 实际选中的就是这个条目，否则改了不生效。
- 直接回编译整份 `dts.dtb.5` 会丢掉原文件里的 `__local_fixups__`/`__symbols__` 之外的手工格式，但 `dtc` 会重新生成所需结构；如果只改属性值，也可以先 `dtc` 编译原文件验证能否通过，再改。

## 10. 常见失败点

| 现象 | 原因 | 处理 |
|---|---|---|
| 解包 DTBO 失败 | `dtbo` 分区读不到，或 `mkdtimg` 不支持该镜像 | 确认分区路径和槽位 |
| 某个补丁没生效 | `dtc` 编译失败，或 `fdtoverlay` 找不到 label | 单独执行 `dtc`/`fdtoverlay` 看报错；检查 `__symbols__` |
| 刷完卡 fastboot | AVB 校验未关闭，或 `add_hash_footer` 失败 | 关闭 verity/verification，或提供匹配的 `vbmeta` |
| 模块描述提示 DTBO 被修改 | 分区 md5 与模块内 `dtbo.img` 不一致 | 重刷模块，或手动同步 `dtbo.img` |
| 开机后参数仍未变 | 改了 `dts.dtb.5` 但模块安装读的是 `patch/PJZ110/*.dts` | 同步改补丁文件，或走手工打包流程 |
