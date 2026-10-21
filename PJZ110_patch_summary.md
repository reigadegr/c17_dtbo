# PJZ110 全部功能与 DTBO 修改点清单（源码核对版）

机型：PJZ110（一加 13，含 CPH2649/CPH2653/CPH2655 等映射型号）。

目标文件：`/data/local/dtbo_work_space/c17/dts.dtb.5`，下文简称 `dts.dtb.5`。

行号以当前仓库中的 `dts.dtb.5` 为准。此前的解容、平滑电量修改都是等行数替换，没有改变后续行号；如果手工插入或删除行，后续行号会变化，应按节点路径重新定位。

本文新增了一次针对 `vendor/oplus/kernel/charger/v2`（下文简称 charger v2）的源码核对。判定标准只有一条：**DT 属性必须被驱动真正读取，并进入控制路径，才算“有效”**。只写进 DT 但没有人读，或者只写在上层同名副本、而驱动实际选择的是 `silicon_p_770` 子节点，都算“无效”。

## 0. 源码核对结论

先给出总表，后面各节展开。

| 文档项 | 判定 | 依据 |
|---|---|---|
| `patch_ddrc` 写在 `silicon_p_770/deep_spec,*` 和六组曲线 | **有效** | gauge 用 `oplus_get_node_by_type()` 选中 `silicon_p_770`，读取 `deep_spec` 并分配 `ddrc_curve` 策略 |
| `patch_ddrc` 同时写入上层同名 `deep_spec`/`ddrc_strategy` | **无效** | 上层副本不被 gauge 读取；补丁里上层值与机内相同，本身也是空操作 |
| 第 3 节的四个显式关机/欠压阈值 | **部分有效** | 属性会被读取，但最终关机电压由 `TARGET_SHUTDOWN_VOLTAGE` 投票取最大值，DD RC 曲线的 `vbat0` 可以覆盖它们 |
| `patch_soc_smooth` 的 `smooth_strategy/oplus_spec,reserve_table_centipercent` | **有效** | `bs` 策略解析该表，生成充电/放电/满充预留和平滑映射 |
| `oplus,reserve_chg_soc`、`oplus,reserve_dis_soc` | **无效** | 前者只在 `oplus,smooth_switch` 或 RUS 启动参数路径读取，本机没有该开关，初始化还会把开关关掉；后者在整棵 charger 树里没有任何解析 |
| 4.1/4.2 的 UFCS/PPS 温控属性 | **有效** | UFCS/PPS 驱动读取高低温数组和 `oplus,temp_range`，曲线策略按温度选段 |
| 4.3 的 `oplus_spec,vooc_*` 档位 | **存疑，本机 AP 内核侧无消费者** | 这些属性只在 AP voocphy/vooc 路径解析；本机 `voocphy_support=ADSP_VOOCPHY`，`oplus_chg_vooc.c` 从 `oplus,vooc` 节点读，而该节点没有这组值，ADSP 驱动本身也不解析温度 |
| `patch_chg_boost` 的 UFCS/PPS 电流、满充电压、策略块 | **有效** | ufcs/pps 驱动解析并进入 votable 与 `pps_ufcs_curve_v2`；例外见下一行 |
| `oplus,ufcs_charge_strategy_soc` | **无效** | 全树没有任何 `of_property_read_*` 读取这个属性；UFCS 实际用的是 `ufcs_charge_*_strategy/oplus,soc_range` |
| `oplus,cpa/oplus,protocol_list` | **有效，但只影响仲裁** | CPA 把它当协议优先级和最大功率表，不直接设定充电电流 |
| `force_rm_lcf` 删除 `silicon_p_770` 下两个 UFCS LCF 节点 | **有效** | UFCS 驱动从类型节点读取 LCF 曲线，并据此投 `CHG_FULL_VOTER` |
| `force_rm_lcf` 的其余 4 条 | **对 PJZ110 无效** | 上层 UFCS LCF 副本不被读取；PPS 的两个 LCF 节点在目标文件中本来就不存在 |
| `rm_dsi_timming` | **域外，未核对** | 面板 timing 属于显示驱动，不在 charger v2 范围 |
| `sh_patch_hm` | **域外，未核对** | 内核 hmbird 节点，不属于 charger v2 |
| `batt_control` / `service.sh` | **模块运行时，不是 DT 修改** | 相关 sysfs 节点在 `oplus_configfs.c` 中有定义；闭源 `opbatt_control` 的具体行为需实测 |

一句话总结：**对带电池类型子节点的 gauge/comm/ufcs/pps 设备，本机真正读取的是 `silicon_p_770` 下的属性和策略块；CPA 节点则直接读自己的属性。上层同名副本、legacy reserve 属性、`oplus,ufcs_charge_strategy_soc` 都是死数据。**

本次已从“有效修改”中删除：`oplus,reserve_chg_soc`/`oplus,reserve_dis_soc`、`oplus,ufcs_charge_strategy_soc`、上层 UFCS LCF 两条、PPS LCF 两条，以及 4.3 的 VOOC 温度效果。它们仍留在补丁/DT 里，但不再被描述为生效项。

## 选项总览

模块的菜单项由文件名自动生成（`tools.sh` 的 `load_config_keys`），选择结果写入 `/data/opbatt_$model.conf`。PJZ110 实际存在的键如下：

| 选项键 | 音量+（值 1） | 音量-（值 0） | 补丁文件 | 作用对象 |
|---|---|---|---|---|
| `patch_ddrc` | 解除电池容量锁定,以及FCC值修正 | 官方默认电池容量参数 | `patch_ddrc_1/_0.dts` | `&oplus_mms_gauge` |
| `patch_soc_smooth` | 实际电量值(建议) | 官方平滑电量(还原官方参数) | `patch_soc_smooth_1/_0.dts` | `&oplus_chg_comm` |
| `patch_batt_therm` | 官方电池温控策略(还原官方参数) | 充电48度撞墙,伪装后53度撞墙(所有充电协议) | `patch_batt_therm_1/_0.dts` | `&oplus_ufcs_charge`、`&oplus_pps_charge`、`&oplus_adsp_voocphy` |
| `patch_chg_boost` | 开启UFCS/150W/13.7A及PPS/6.5A支持 | 官方充电策略优化 | `patch_chg_boost_1/_0.dts` | `&oplus_cpa`、`&oplus_ufcs_charge`、`&oplus_pps_charge` |
| `rm_dsi_timming` | 保持原有DTBO中刷新率策略 | 面板刷新率移除补丁 | `rm_dsi_timming`（只有删除清单，无 dts/sh） | 5 个面板的 60/90Hz timing 节点 |
| `sh_patch_hm` | 官方内核模式 | 非官方内核GKI模式,不选择可能无限重启 | `sh_patch_hm_1/_0.sh` | 二进制 dtb 里的 `oplus,hmbird/version_type` |
| 无菜单 | — | — | `force_rm_lcf` | 强制删除 UFCS/PPS 的 LCF 策略节点 |

`set_default_config` 会把所有键先置 0，再逐项让用户选择；已有配置时从 `/data/opbatt_$model.conf` 读取。`patch_soc_battery`、`patch_pdqc` 只有说明字符串，PJZ110 目录没有对应文件，`load_config_keys` 不会生成这两个键。

## 1. 解容及 FCC 修正（`patch_ddrc`）

### 1.1 有效部分：`silicon_p_770` 下的 deep_spec

目标节点：

```text
/fragment@52/__overlay__/oplus,mms_gauge/silicon_p_770
```

`oplus_gauge_parse_deep_spec()` 通过 `oplus_get_node_by_type()` 选中这个子节点，读取 `deep_spec,count_thr`、`deep_spec,vbat_soc`、`deep_spec,count_step`、`deep_spec,term_coeff`、`deep_spec,uv_thr`。补丁把前四项改为：

```dts
deep_spec,count_thr = <0x0>;
deep_spec,vbat_soc = <0x0>;
deep_spec,count_step = <0x0 0x0 0x0>;
deep_spec,term_coeff = <0x0 0x0 0x0>;
```

当前仓库的 `dts.dtb.5` 和 `dts.dtb.5.bak` 里这四项已经是 0，补丁对它们只是重复写；如果基线是未改过的原厂 dtbo，仍需按补丁写入。真正会改变低电端行为的是下面的六组 `strategy_temp_*` 曲线。

这几项的含义需要说清楚：

- `term_coeff` 每三个数是一组 `{term_voltage, fcc_coeff, soh_coeff}`，不是容量或 FCC 数值本身。清零后，终止电压判断会命中最后一组，FCC/SOH 系数变成 0，不再按终止电压做容量折减。这是 DTS 层“FCC 修正”的实际内容。
- `count_step` 每三个数是一组 `{temp, step, index}`。清零后深放电步进为 0，不再按温度阶梯调整计数。
- `deep_spec,count_thr` 和 `deep_spec,vbat_soc` 清零后，DD RC 不再用“循环计数/低 SOC 电压”提前限制放电深度。

换句话说，**“解容”不是把 `oplus,batt_capacity_mah` 改大**。补丁里没有 `fcc`、`capacity`、`wired-ffc-fcc-ma` 任何一项；真正的统计侧动作在运行时 `service.sh`（见第 10 节）。

该节点的 `ddrc_strategy` 内，六组曲线都需要修改：

| 子节点 | 原属性行号 |
|---|---|
| `strategy_ratio_range_min` | 4202–4205 |
| `strategy_ratio_range_low` | 4209–4212 |
| `strategy_ratio_range_mid_low` | 4216–4219 |
| `strategy_ratio_range_mid` | 4223–4226 |
| `strategy_ratio_range_mid_high` | 4230–4233 |
| `strategy_ratio_range_high` | 4237–4240 |

每组四项在 `patch_ddrc_1.dts` 中统一为：

```dts
strategy_temp_cold = <0x0 0xaf0 0xaf0 0x0>;
strategy_temp_cool = <0x0 0xaf0 0xaf0 0x0>;
strategy_temp_normal = <0x0 0xaf0 0xaf0 0x0>;
strategy_temp_warm = <0x0 0xaf0 0xaf0 0x0>;
```

每组四个数对应 `struct ddrc_strategy_data { count, vbat0, vbat1, index }`：

- `vbat0` 投给 `TARGET_SHUTDOWN_VOLTAGE`，是关机电压；
- `vbat1` 投给 `TARGET_TERM_VOLTAGE`，是终止电压；
- `count` 和 `index` 参与低电端的计数/阶梯选择。

`0xaf0` = 2800 mV。六组比例区间全部压到同一个 2.8V 点后，DD RC 在低电端不再按比例区间抬高关机/终止电压，原来被保护逻辑保留的低电容量就放出来了。

### 1.2 当前 dts 与模块补丁的数值差异

当前仓库的 `dts.dtb.5` 在提交 `09eaba9` 中已经把 `silicon_p_770` 下的六组曲线改成了 `0xb54`（2900 mV），但 `patch/PJZ110/patch_ddrc_1.dts` 仍然是 `0xaf0`（2800 mV）。两者不是同一个版本：

- 手工改 `dts.dtb.5` 并打包时，当前文件是 **2900 mV**；
- 走模块安装时，生效的是补丁里的 **2800 mV**；
- `deep_spec,uv_thr` 在两处都仍是 `0xaf0`。

这个差异会直接影响第 3 节的实际关机点，不能混用。

### 1.3 无效部分：上层同名副本

`patch_ddrc` 也会写上层 `/fragment@52/__overlay__/oplus,mms_gauge` 的 `deep_spec` 和 `ddrc_strategy`。但 gauge 只从 `silicon_p_770` 子节点读取，上层副本不参与策略分配，也不参与投票。补丁里上层值与机内一致，所以这部分本身也是空操作。

同理，`deep_spec,ddbc_curve` 未在补丁中改变，仍然是原值；`oplus,batt_capacity_mah`（上层 4159、子层 4168）和满充/FFC 截止电压也都没有改。

## 2. 实际电量值（`patch_soc_smooth`）

### 2.1 有效部分：`smooth_strategy` 预留表

目标节点：

```text
/fragment@58/__overlay__/oplus,comm/silicon_p_770
```

真正起作用的是该节点内 `smooth_strategy` 的 `oplus_spec,reserve_table_centipercent`。当前第 4615 行是：

```dts
oplus_spec,reserve_table_centipercent = <0x0 0x64 0x0 0x0 0x0 0x64>;
```

`_1` 补丁写入同样的 6 个值；`_0` 补丁写入 18 个值：

```dts
/* patch_soc_smooth_0.dts */
<0x00 0x14 0x00 0x00 0xc8 0x64
 0x15 0x63 0xc8 0x00 0xc8 0x64
 0x64 0x64 0xc8 0x00 0xc8 0x64>
```

驱动在 `strategy/oplus_strategy_battery_smooth.c` 里按每 6 个数一组解析 `{start_soc, end_soc, dischg_reserve, full_reserve, chg_reserve, chg_split_soc}`，并检查：

- 元素个数必须是 6 的倍数；
- 第一组必须从 0% 开始，最后一组必须在 100% 结束；
- 相邻组必须首尾相接，不能有缺口或重叠；
- 每个 reserve 值在 0–1000（0.00%–10.00%）之间，split SOC 在 20–100 之间。

所以 6 个值不是“数组长度异常”：它表示 0–100% 只有一段；18 个值表示三段。`_1` 的三个 reserve 全为 0，等于不做预留，UI 直接显示实际 SOC；`_0` 在 0–20% 段保留 2% 的充电预留，在 21–100% 段保留 2% 的放电+充电预留，`full_reserve` 仍为 0，是官方平滑风格。

### 2.2 无效部分：两个 reserve 属性

`patch_soc_smooth` 还在 `silicon_p_770` 内新增：

```dts
oplus,reserve_chg_soc = <0x0>;
oplus,reserve_dis_soc = <0x0>;
```

这两个属性在本机是死数据，应该从“有效修改”里删掉：

- `oplus,reserve_dis_soc` 在整棵 charger v2 里没有任何 `of_property_read_*`，写了也不会被读。
- `oplus,reserve_chg_soc` 只在 `oplus_comm_parse_smooth_soc_dt()` 里读取，而且前提是 `oplus,smooth_switch` 为真或 RUS 启动参数设置了预留。本机 DT 没有 `oplus,smooth_switch`；并且 `oplus_comm_smooth_strategy_init()` 在解析后会执行 `chip->config.smooth_switch = false`，把旧的平滑开关交给 `bs` 策略接管。因此这个属性也不会进入实际路径。

补丁保留这两行没有坏处，但不要把它们当作“实际电量”的开关；实际开关是 `reserve_table_centipercent`。

## 3. 关机相关电压

当前文件中的以下阈值已经是 2.8V 一线，不需要再改：

| 行号 | 所属节点 | 参数 | 当前值 |
|---|---|---|---|
| 4179 | `oplus,mms_gauge/silicon_p_770` | `deep_spec,uv_thr` | `0xaf0`，2800 mV |
| 4594 | `oplus,comm/silicon_p_770` | `oplus_spec,vbat_uv_thr_mv` | `0xaf0`，2800 mV |
| 4595 | `oplus,comm/silicon_p_770` | `oplus_spec,vbat_charging_uv_thr_mv` | `0xa8c`，2700 mV |
| 4606 | `oplus,comm/silicon_p_770` | `oplus,chg_shutdown_max_mv` | `0xaf0`，2800 mV |

但要注意：**这些显式阈值不等于最终关机点**。charger v2 的 `TARGET_SHUTDOWN_VOLTAGE` votable 使用 `VOTE_MAX`，DD RC 曲线会把 `vbat0` 投进去（`oplus_sili.c` 的 `oplus_gauge_update_ddrc_data()`），最终取所有 vote 的最大值。

- 当前 `dts.dtb.5` 的曲线 `vbat0` 是 `0xb54` = 2900 mV，高于显式阈值的 2800 mV，所以实际关机点更可能是 2900 mV；
- `patch_ddrc_1.dts` 把曲线压到 `0xaf0` = 2800 mV，才和这些显式阈值一致，真正把关机点拉到 2.8V。

因此旧版文档里“这些阈值已是 2.8V，但当前 DDRC 曲线仍包含更高电压值”这句话需要改成：**当前曲线是 2900 mV，模块补丁是 2800 mV；显式阈值只是其中一票，不能单独决定关机点。** 模块的 `patch_ddrc_1.dts` 也没有改这四个显式阈值，只改了 `deep_spec,uv_thr` 和曲线。

## 4. 电池温控（`patch_batt_therm`）

这项取值方向与其它 `patch_*` 选项相反：这里是 0 对应修改版、1 对应官方原值。先看数值：

- `patch_batt_therm_1.dts` 写入的是机内原值（400/420/430 一线），选择“官方电池温控策略”时实际不改变任何数值。
- `patch_batt_therm_0.dts` 才是 48/53 度墙的修改版，选择“充电48度撞墙,伪装后53度撞墙”时生效。

所有温度单位都是 0.1°C。

### 4.1 UFCS 节点（有效）

`/fragment@61/__overlay__/oplus,ufcs_charge/silicon_p_770`：

| 行号 | 属性 | 原值 | 改为 |
|---|---|---|---|
| 5024 | `oplus,ufcs_strategy_batt_high_temp` | `<400 420 430 390 410 420>` | `<530 530 530 530 530 530>` |
| 5030 | `oplus,ufcs_charge_strategy_temp` | `<0 50 120 160 350 440 510>` | `<0 50 120 160 400 480 530>` |
| 5063 | `ufcs_charge_third_strategy/oplus,temp_range` | `<0 50 120 160 210 350 440 510>` | `<0 50 120 160 210 400 480 530>` |
| 5129 | `ufcs_charge_oplus_strategy/oplus,temp_range` | `<0 50 120 160 210 350 440 510>` | `<0 50 120 160 210 400 480 530>` |

源码里的映射关系：

- `oplus,ufcs_strategy_batt_high_temp` 的 6 个数依次是 `high_temp0/1/2` 和 `low_temp0/1/2`，和 `oplus,ufcs_strategy_high_current` 的 6 个数一一对应。全部写成 530 后，高/低温阈值合并，`low_current0` 这条低温支路会在温度回落到阈值以下时被用到；它不是一个按顺序递增的“第 4 档”。
- `oplus,ufcs_charge_strategy_temp` 的 7 个数依次是 `over_low` 基值、`little_cold`、`cool`、`little_cool`、`normal_low`、`normal_high`、`over_high`。补丁把 `normal_low` 从 350 提到 400、`normal_high` 从 440 提到 480、`over_high` 从 510 提到 530；`little_cool_high` 由单独的 `oplus,ufcs_little_cool_high_temp`（210）控制，补丁未改。
- `oplus,temp_range` 是 8 个数（7 个边界 + 末尾上界），由 `pps_ufcs_curve_v2` 读取；长度必须是 8，补丁保持了长度。

### 4.2 PPS 节点（有效）

`/fragment@71/__overlay__/oplus,pps_charge/silicon_p_770`：

| 行号 | 属性 | 原值 | 改为 |
|---|---|---|---|
| 6218 | `oplus,pps_strategy_batt_high_temp` | `<410 420 430 400 410 420>` | `<530 530 530 530 530 530>` |
| 6223 | `oplus,pps_charge_strategy_temp` | `<0 50 120 160 350 440 510>` | `<0 50 120 160 400 480 530>` |
| 6228 | `pps_charge_third_strategy/oplus,temp_range` | `<0 50 120 160 210 350 440 510>` | `<0 50 120 160 210 400 480 530>` |
| 6294 | `pps_charge_oplus_strategy/oplus,temp_range` | `<0 50 120 160 210 350 440 510>` | `<0 50 120 160 210 400 480 530>` |

PPS 的解析路径与 UFCS 相同：`oplus,pps_strategy_batt_high_temp` 在 `oplus_chg_pps.c` 中读取，`oplus,pps_charge_strategy_temp` 也用 7 个边界，`oplus,temp_range` 由曲线策略读取。这四行是有效的。

### 4.3 VOOC 温度档位（存疑，本机 AP 内核侧无消费者）

`patch_batt_therm_0.dts` 还会把 `&oplus_adsp_voocphy` 的 9 个档位写成：

```text
0, 0, 0, 100, 150, 420, 480, 530, 550
```

对应 `oplus_spec,vooc_low_temp`、`little_cold`、`cool`、`little_cool`、`little_cool_high`、`normal_low`、`normal_high`、`high`、`over_high`。`patch_batt_therm_1.dts` 会把这组值写回原值。

但 charger v2 里这组属性只有两条解析路径：

- `voocphy/oplus_ap_voocphy.c`：AP voocphy 路径，由充电泵驱动调用 `oplus_register_voocphy()`；
- `oplus_chg_vooc.c`：从 `oplus,vooc` 节点读取。

本机 `oplus,vooc` 节点的 `oplus,voocphy_support = <0x1>`，即 `ADSP_VOOCPHY`；该节点本身没有 `oplus_spec,vooc_*` 属性，`oplus_chg_vooc.c` 会回退到默认值（0/50/120/160/250/430/440 一线）。`voocphy/oplus_adsp_voocphy.c` 只注册虚拟 vphy，不解析温度。也就是说，**这 9 个值在当前内核的 ADSP 路径上没有明确消费者**，不能把它当作“48/53°C 全协议墙”已经生效的依据。是否被 ADSP 固件另行采用，需要实测确认。本文不再把 4.3 计入有效修改。

### 4.4 与温控配套的 batt_control 表（模块运行时有效）

`customize.sh` 会根据本项选择，在 `/data/opbatt/batt_control` 头部追加温度-电流偏移表：

- 选择 0（48/53 度墙）：`temp_range=42,43,44,45,46`，`temp_curr_offset=800,1200,1800,2500,4500`。
- 选择 1（官方）：`temp_range=39,40,41,42,43`，`temp_curr_offset=500,1000,1500,2000,4000`。

这段逻辑在 `customize.sh:149-157`，与 DT 无关，属于模块运行时配置。

## 5. 充电增强（`patch_chg_boost`）

这项补丁把 UFCS/PPS 的协议功率、电流上限、满充电压和 SOC 分档整体改写，涉及 171 处属性值。下面区分“真正进内核”的部分和“只是能力表/死数据”的部分。

### 5.1 CPA 协议表（有效，但只影响仲裁）

`/fragment@61/__overlay__/oplus,cpa`：

| 行号 | 属性 | 原值 | 改为 |
|---|---|---|---|
| 4744 | `oplus,protocol_list` | `<0x4 0x64 0x3 0x64 0x2 0x37 0x1 0x12 0x5 0x12>` | `<0x4 0x96 0x3 0x64 0x2 0x55 0x1 0x12 0x5 0x12>` |

按协议号配对读：4 = UFCS，3 = VOOC，2 = PPS，1 = PD，5 = QC。`_1` 把 UFCS 的 100W 提到 150W；PPS 的 55W→85W 在 `_0` 和 `_1` 里都已存在，不是 `_1` 独有的变化。

但要明确：`oplus_chg_cpa.c` 把这个数转换成 `max_power_mw`，用于协议优先级、能力表和切换判断，**不是直接设定 150W/85W 的电流环**。实际功率仍由 UFCS/PPS 的 `curr_max_ma`、曲线目标、适配器协商和 votable 共同决定。`oplus,default_protocol_list` 不变。

### 5.2 UFCS 标量属性（除一行外均有效）

`/fragment@61/__overlay__/oplus,ufcs_charge/silicon_p_770`：

| 行号 | 属性 | 原值 | 改为 | 说明 |
|---|---|---|---|---|
| 5004 | `oplus,curr_max_ma` | `0x238c` | `0x3908` | 9100 → 14600 mA |
| 5008 | `oplus,ufcs_strategy_normal_current` | `0x238c` | `0x3908` | 9100 → 14600 mA |
| 5009 | `oplus,ufcs_over_high_or_low_current` | `0x238c` | `0x3908` | 9100 → 14600 mA |
| 5012 | `oplus,ufcs_ibat_over_third` | `0x1518` | `0x3908` | 5400 → 14600 mA |
| 5013 | `oplus,ufcs_ibat_over_oplus` | `0x2904` | `0x3908` | 10500 → 14600 mA |
| 5014 | `oplus,ufcs_ibus_over_oplus` | `0x2af8` | `0x3778` | 11000 → 14200 mA |
| 5017 | `oplus,ufcs_full_normal_hw_vbat` | `0x1202` | `0x11da` | 4610 → 4570 mV，硬件满充阈值 |
| 5020 | `oplus,ufcs_full_cool_sw_vbat_third` | `0x1194` | `0x11f8` | 4500 → 4600 mV |
| 5021 | `oplus,ufcs_full_normal_sw_vbat_third` | `0x1194` | `0x11f8` | 4500 → 4600 mV |
| 5022 | `oplus,ufcs_full_normal_hw_vbat_third` | `0x11bc` | `0x11da` | 4540 → 4570 mV |
| 5025 | `oplus,ufcs_strategy_high_current` | `<0x1388 0xfa0 0xbb8 0x238c 0x1388 0xfa0>` | `<0x1388 0xfa0 0xbb8 0x3908 0x1388 0xfa0>` | 第 4 个元素 `low_current0` 9100 → 14600 mA |
| 5028 | `oplus_spec,ufcs_high_soc` | `0x5f` | `0x63` | 95 → 99 |
| 5062 | `ufcs_charge_third_strategy/oplus,soc_range` | `... 0x55 0x5f` | `... 0x55 0x63` | 末档 95 → 99 |
| 5128 | `ufcs_charge_oplus_strategy/oplus,soc_range` | `... 0x55 0x5f` | `... 0x55 0x63` | 末档 95 → 99 |

**已删掉的一行：`oplus,ufcs_charge_strategy_soc`。** 补丁里还有这一行（第 5029 行，末档改成 0x63），但 charger v2 全树没有任何代码读取它。UFCS 实际使用的是 `ufcs_charge_*_strategy/oplus,soc_range`，所以这一行的修改没有效果；保留也不会坏，但不能算作“提升到 99% 快充”的依据。

几个容易误读的点：

- `oplus,ufcs_strategy_high_current` 的 6 个数不是“6 个档位依次升高”，而是 `high0/high1/high2/low0/low1/low2`。第 4 个是 `low0`，对应温度低于 `strategy_batt_low_temp0` 的低温支路；不要按序号把它理解成“第 4 档”。
- `oplus,curr_max_ma` 只是 `UFCS_CURR` votable 的 `MAX_VOTER` 上限。实际电流是所有 vote 的最小值，曲线目标、`BATT_SOC_VOTER`、`IBUS_OVER_VOTER` 都可能更低。
- `oplus,curr_max_ma_percent = <0xdac 0x7d0>`（3500/2000）仍然生效：在电流开始下降后，UI SOC > 85% 时 `BATT_SOC_VOTER` 会投 2000 mA，> 75% 时投 3500 mA。因此 14600 mA 主要是在较低 SOC 段的上限，高 SOC 段会明显收窄。
- `oplus,ufcs_full_normal_hw_vbat` 是硬件满充阈值，补丁把它从 4610 mV 降到 4570 mV；它不是“把满充电压调高”，实际是否更早触发取决于适配器的硬件满信号。

### 5.3 UFCS 策略块（整块替换，有效）

| 行号范围 | 节点 | 替换内容 |
|---|---|---|
| 5060–5124 | `silicon_p_770/ufcs_charge_third_strategy` | `patch_chg_boost_1.dts` 第 46–109 行 |
| 5126–5190 | `silicon_p_770/ufcs_charge_oplus_strategy` | `patch_chg_boost_1.dts` 第 111–174 行 |

每块包含 6 个 SOC 区间的 7 个温度段曲线。补丁把原来的末尾温区从 350/440/510 扩到 400/480/530，并整体改写各段的电压/电流组合；数值以补丁文件为准，不要按原块逐项微调，直接整块替换更安全。

`oplus,ufcs_charge` 下还有两份同名策略副本在第 4856–4920、4922–4986 行，那是模块没有覆盖的上层副本。**上层副本不被 `oplus_get_node_by_type()` 选中，属于死数据**；保持原样即可，不需要为了“完整”再去改它们。

### 5.4 PPS 标量属性（有效）

`/fragment@71/__overlay__/oplus,pps_charge/silicon_p_770`：

| 行号 | 属性 | 原值 | 改为 | 说明 |
|---|---|---|---|---|
| 6200 | `oplus,curr_max_ma` | `0x1388` | `0x1964` | 5000 → 6500 mA |
| 6203 | `oplus,pps_strategy_normal_current` | `0x1388` | `0x1964` | 5000 → 6500 mA |
| 6207 | `oplus,pps_ibat_over_third` | `0x1900` | `0x1964` | 6400 → 6500 mA |
| 6208 | `oplus,pps_ibat_over_oplus` | `0x1900` | `0x1964` | 6400 → 6500 mA |
| 6209 | `oplus,pps_full_cool_sw_vbat` | `0x1194` | `0x11f8` | 4500 → 4600 mV |
| 6210 | `oplus,pps_full_normal_sw_vbat` | `0x1194` | `0x11f8` | 4500 → 4600 mV |
| 6211 | `oplus,pps_full_normal_hw_vbat` | `0x11bc` | `0x11da` | 4540 → 4570 mV |
| 6214 | `oplus,pps_full_cool_sw_vbat_third` | `0x1194` | `0x11f8` | 4500 → 4600 mV |
| 6215 | `oplus,pps_full_normal_sw_vbat_third` | `0x1194` | `0x11f8` | 4500 → 4600 mV |
| 6216 | `oplus,pps_full_normal_hw_vbat_third` | `0x11bc` | `0x11da` | 4540 → 4570 mV |
| 6219 | `oplus,pps_strategy_high_current` | `<0x1388 0x1388 0xbb8 0x1388 0x1388 0x1388>` | `<0x1964 0x1964 0x1964 0x1964 0x1964 0x1964>` | 全部 5000 → 6500 mA |
| 6222 | `oplus,pps_charge_strategy_soc` | `... 0x55 0x5f` | `... 0x55 0x63` | 末档 95 → 99 |
| 6227 | `pps_charge_third_strategy/oplus,soc_range` | `... 0x55 0x5f` | `... 0x55 0x63` | 同上 |
| 6293 | `pps_charge_oplus_strategy/oplus,soc_range` | `... 0x55 0x5f` | `... 0x55 0x63` | 同上 |

与 UFCS 不同，`oplus,pps_charge_strategy_soc` 在 `oplus_chg_pps.c:5819` 有解析，并用于 SOC 档位判断，所以这一行是有效的。

### 5.5 PPS 策略块（整块替换，有效）

| 行号范围 | 节点 | 替换内容 |
|---|---|---|
| 6225–6289 | `silicon_p_770/pps_charge_third_strategy` | `patch_chg_boost_1.dts` 第 207–270 行 |
| 6291–6355 | `silicon_p_770/pps_charge_oplus_strategy` | `patch_chg_boost_1.dts` 第 272–335 行 |

与 UFCS 相同：6 个 SOC 区间 × 7 个温度段，整块替换。PPS 的曲线策略同样读取 `oplus,soc_range` 和 `oplus,temp_range`，所以这些块是有效的。

### 5.6 运行时上限不一致（保留，但结论要更精确）

DT 里 UFCS 上限被提到 14600 mA、PPS 提到 6500 mA，但 `/data/opbatt/batt_control` 里仍是 `ufcs_max=9100`、`pps_max=5000`，`service.sh` 又把 `bcc_current` 写成 13700。实际能跑到哪一档取决于投票与协商顺序：

- `UFCS_CURR`/`PPS_CURR` 都是 `VOTE_MIN`，有效值取所有使能 vote 的最小值；
- `MAX_VOTER` 的 14600/6500 只是“天花板”；
- 曲线目标、`BATT_SOC_VOTER`（>75% 3500、>85% 2000）、`IBUS_OVER_VOTER`（14200 以上连续 4 次会降到 2000）都可能更低；
- 闭源 `opbatt_control` 通过 `/proc/oplus-votable/UFCS_CURR/force_val` 和 `PPS_CURR/force_val` 写入自己的目标，是否与 DT 上限冲突需要实测。

因此不能只看 DT 值就断言“稳定 13.7A/6.5A”；高 SOC 段和线缆/适配器协商都会先限流。

## 6. 面板刷新率策略移除（`rm_dsi_timming`）

> **源码核对范围说明：** 这一节属于显示面板 timing，不在 charger v2 中，本次没有核对。下面保留的是模块删除清单本身，是否生效取决于对应面板驱动。

这是删除清单，不是 DTS 叠加。选中“面板刷新率移除补丁”（值 0）时，`PATCH_DTB` 调用 `rm_proc_from_file`，对每个 dtb 执行 `fdtput -r`，把整棵 timing 节点删掉；选“保持原有 DTBO 中刷新率策略”（值 1）时不做任何操作。

删除目标都在：

```text
/fragment@110/__overlay__/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_panel_<面板>/
    qcom,mdss-dsi-display-timings/timing@wqhd_sdc_<60|90>
```

| 面板节点 | timing | 删除行号范围 |
|---|---|---|
| `qcom,mdss_dsi_panel_AA545_P_3_A0005_dsc_cmd` | 90 | 19846–19935 |
| 同上 | 60 | 19754–19844 |
| `qcom,mdss_dsi_panel_BF262_P_3_A0021_dsc_cmd` | 90 | 20315–20403 |
| 同上 | 60 | 20224–20313 |
| `qcom,mdss_dsi_panel_AA569_P_3_A0019_dsc_cmd_evb` | 90 | 20838–20986 |
| 同上 | 60 | 20988–21131 |
| `qcom,mdss_dsi_panel_AA569_P_3_A0019_dsc_cmd_evt` | 90 | 21537–21707 |
| 同上 | 60 | 21709–21874 |
| `qcom,mdss_dsi_panel_AA569_P_3_A0019_dsc_cmd` | 90 | 22313–22485 |
| 同上 | 60 | 22487–22654 |

只删 60 和 90 两档，120 与 `qcom,mdss-dsi-display-timings` 下的 `timing@wqhd_sdc_120`、`timing@wqhd_oplus_120` 保留。清单只覆盖这 5 个面板，其他面板型号（例如 `nt37801` 系列）不受影响。

## 7. LCF 策略节点（`force_rm_lcf`）

### 7.1 LCF 是什么

**LCF = Low Current Full（低电流充满判定）**，对应的内核策略名是 `low_curr_full_strategy`。它不控制充电电压/电流曲线，也不参与协议协商；它只做一件事：

> 在恒压/涓流末端，用“电流足够小 + 电压足够高”判断电池是否真的充满，然后投 `CHG_FULL_VOTER` 停止充电。

只看电压会在内阻/线损下提前判满，只看电流会在低 SOC 大电流时误判。LCF 用分温度区的多条 `{iterm, vterm}` 曲线，并且要求连续多次命中，才认为满充。

### 7.2 配置结构

以 `dts.dtb.5` 的 UFCS 节点为例：

```text
/fragment@61/__overlay__/oplus,ufcs_charge/silicon_p_770/
    ufcs_oplus_lcf_strategy
    ufcs_third_lcf_strategy
```

每个节点包含：

```dts
oplus,temp_type = <0x1>;   /* 电池温度 */
oplus,temp_range = <0x0 0x32 0x78 0xa0 0xd2 0x17c 0x1b8>;
/* 0, 5, 12, 16, 21, 38, 44 °C */

strategy_temp_range_curves {
    strategy_temp_range_t0 = <iterm vterm exit ...>;
    ...
    strategy_temp_range_t5 = <iterm vterm exit ...>;
};
```

- 6 个温度区 `t0`–`t5`；
- 每个区最多 6 组曲线，每组三个数 `{iterm, vterm, exit}`；
- `iterm` 单位 mA，`vterm` 单位 mV；
- 当前 `lcf_strategy_get_data()` 只使用 `iterm` 和 `vterm`，`exit` 会被解析和打印，但不参与判断。

PJZ110 的 `ufcs_oplus_lcf_strategy` 和 `ufcs_third_lcf_strategy` 分别对应 OPlus 适配器和第三方适配器；本机 dts 里两份曲线内容相同，区别只在驱动按适配器类型选择哪一份。两份都是有效的。

### 7.3 运行时逻辑

调用链在 `oplus_chg_ufcs.c`：

```text
UFCS monitor（每 500 ms）
  -> oplus_ufcs_check_full()
     -> oplus_ufcs_check_sw_full()        /* 软件/硬件满充电压 */
     -> oplus_ufcs_update_low_curr_full() /* LCF */
```

`oplus_ufcs_update_low_curr_full()` 的行为：

1. 如果 `oplus_get_chg_spec_version() >= OPLUS_CHG_SPEC_VER_V3P7`，走 LCF 策略节点；
2. OPlus 适配器用 `oplus_lcf_strategy`，第三方适配器用 `third_lcf_strategy`；
3. `lcf_strategy_get_data()` 读取电池电压和电流；
4. 只要任意一组曲线满足 `ibat <= iterm && vbat >= vterm`，就认为本次采样是“低电流满”；
5. 连续命中次数 `low_curr_full_conut++`，超过 6 次（即第 7 次，约 3.5 秒）后返回 1；
6. 驱动投 `CHG_FULL_VOTER` 到 `ufcs_disable_votable`，关闭 UFCS 充电；
7. 任何一次不满足都会把计数清零。

PPS 走类似路径 `oplus_pps_update_low_curr_full()`，命中后投 `pps_disable_votable` 的 `CHG_FULL_VOTER`。但 PPS 代码会先检查两个 LCF 策略指针，任一为 NULL 就直接返回，所以 PPS 节点不存在也不会崩溃。

旧 spec 路径不使用 LCF 节点，而是使用 `ufcs_charge_low_curr_full` 节点里的曲线和 `oplus,ufcs_low_curr_full_strategy_temp` 温度边界；本节说的是 V3P7 及以上的新路径。PJZ110 的 DT 没有 `ufcs_charge_low_curr_full` 节点，因此旧路径也不会提供额外的 LCF 判满。

### 7.4 LCF 的 alarm 分支

LCF 节点还支持可选的 `oplus,alarm_offset`：

- `get_custom_data("alarm")` 会把每条曲线的 `iterm` 加上 `alarm_offset`，用更宽松的阈值再判一次；
- 命中后通过 `oplus_ufcs_push_lcf_alarm_status()` 发布 `BATT_BAL_ITEM_LCF_ALARM`；
- `oplus_batt_bal.c` 用这个 bitmask（B1/B2）判断某节电池是否先到满，从而调整双电池平衡电流。

PJZ110 的两个 UFCS LCF 节点都**没有** `oplus,alarm_offset`，因此 `get_custom_data()` 直接返回 `-EINVAL`，alarm 分支不会设置任何 bit。**这台机器上的 LCF 只承担“低电流判满停充”，不承担双电池平衡告警。**

### 7.5 `force_rm_lcf` 实际删了什么

清单有 6 条，逐条核对如下：

| 清单行 | 目标节点 | 是否存在 | 是否被驱动读取 | 结论 |
|---|---|---|---|---|
| `r oplus_ufcs_charge ufcs_oplus_lcf_strategy` | 上层 `&oplus_ufcs_charge/ufcs_oplus_lcf_strategy` | 存在（4828–4840） | 否 | 空操作 |
| `r oplus_ufcs_charge ufcs_third_lcf_strategy` | 上层 `&oplus_ufcs_charge/ufcs_third_lcf_strategy` | 存在（4842–4854） | 否 | 空操作 |
| `r oplus_ufcs_charge silicon_p_770/ufcs_oplus_lcf_strategy` | 下层 OPlus 适配器 LCF | 存在（5032–5044） | 是 | **有效** |
| `r oplus_ufcs_charge silicon_p_770/ufcs_third_lcf_strategy` | 下层第三方适配器 LCF | 存在（5046–5058） | 是 | **有效** |
| `r oplus_pps_charge silicon_p_770/pps_oplus_lcf_strategy` | PPS OPlus LCF | 不存在 | — | 空操作 |
| `r oplus_pps_charge silicon_p_770/pps_third_lcf_strategy` | PPS 第三方 LCF | 不存在 | — | 空操作 |

原因：

- `oplus_ufcs_parse_lcf_strategy_dt()` 用的是 `oplus_get_node_by_type(chip->dev->of_node)`，本机电池类型是 `silicon_p_770`，所以只读下层两个节点；上层两个副本永远不会被选中。
- PPS 的两个节点在 `dts.dtb.5` 中本来就不存在；`fdtput -r` 失败后会被静默忽略，`oplus_pps_parse_lcf_strategy_dt()` 返回 `-ENODEV`，调用方也不检查，后续 `oplus_pps_update_low_curr_full()` 看到 NULL 直接返回。
- UFCS 删除下层节点后，`oplus_ufcs_parse_lcf_strategy_dt()` 统计到 0 个 LCF 节点，循环跳过；`oplus_ufcs_update_low_curr_full()` 不再投 `CHG_FULL_VOTER`。不会导致 probe 失败。

### 7.6 删除 LCF 之后会发生什么

**不会变成“永不判满”。** UFCS/PPS 还有其它停充路径：

- `oplus_ufcs_check_sw_full()` / `oplus_pps_check_sw_full()`：软件/硬件满充电压判断；
- `CHG_FULL_WARM_VOTER`：warm 温度下的满充电压；
- `TIMEOUT_VOTER`：UFCS/PPS 最大充电时间；
- `IBAT_OVER_VOTER`、`IBUS_OVER_VOTER`：过流保护。

删除 LCF 只是取消“低电流 + 高电压”的提前判满，让恒压/涓流继续把电量补满。这与 `patch/PJZ110/README.txt` 里的“移除LCF配置，以适配恒压涓流”一致。

需要注意：LCF 被删后，设备可能在 UI 显示 100% 后仍有小电流（恒压/涓流阶段），这是预期行为；如果长时间不降流，应该看温度、`batt_control` 和 `opbatt_control` 的日志，而不是把 LCF 加回来。

## 8. 内核 hmbird 模式（`sh_patch_hm`）

> **源码核对范围说明：** hmbird 节点不在 charger v2 中，本次没有核对。下面保留模块脚本的操作说明。

这一项不是 DTBO 叠加，而是对解包出来的二进制 dtb 直接写字符串。`PATCH_DTB` 在应用 `.m.dtbo` 之前先执行 `sh_patch_hm_${val}.sh`，脚本在 `__fixups__` 的 `soc` 目标里找到含 `hmbird` 的 overlay，然后写：

```text
/fragment@90/__overlay__/oplus,hmbird/version_type/type
```

对应 `dts.dtb.5` 第 7239–7244 行，当前值在第 7242 行：

```dts
type = "HMBIRD_OGKI";
```

- 值 1（官方内核模式）：`sh_patch_hm_1.sh` 写入 `HMBIRD_OGKI`，与机内原值一致。
- 值 0（非官方内核 GKI 模式）：`sh_patch_hm_0.sh` 写入 `HMBIRD_GKI`。

清单里没有这个键时不会执行；`load_config_keys` 会把 `sh_patch_hm` 生成菜单项，默认置 0，所以全新安装时如果一路选“音量-”，会写成 GKI。

## 9. 充电控制配置（`batt_control`，非 DTBO）

`customize.sh` 把 `patch/PJZ110/batt_control` 复制到 `/data/opbatt/batt_control`，再按第 4.4 节追加温度-电流表。它不写入 DTBO，而是给闭源的 `bin/opbatt_control` 在开机后读取。主要参数：

| 参数 | 值 | 含义 |
|---|---|---|
| `enabled` | 1 | 启用恒压/涓流控制 |
| `inc_step` / `dec_step` | 100 / 100 | 每次调节的电流步进（mA） |
| `ufcs_max` / `pps_max` | 9100 / 5000 | 运行时 UFCS/PPS 电流上限（mA） |
| `cable_override` | 0 | 不覆盖线缆能力 |
| `max_ufcs_chg_reset_cc` | 1 | 允许重置 UFCS 充电电流 |
| `ufcs_reset_delay` | 180 | 重置等待（秒） |
| `ufcs_soc_mon` / `ufcs_interval_ms` | 20,60 / 650,400 | UFCS SOC 监控点与采样间隔 |
| `pps_soc_mon` / `pps_interval_ms` | 20,68 / 650,400 | PPS SOC 监控点与采样间隔 |
| `batt_vol_thr` / `batt_vol_soc` | 4559,4559 / 75,85 | 恒压切换电压与 SOC 条件（mV） |
| `batt_con_soc` | 94 | 转入恒压控制的 SOC |
| `rise_quickstep_thr_mv` / `rise_wait_thr_mv` | 4250 / 3800 | 升流快慢阈值（mV） |
| `cv_vol_mv` / `cv_max_ma` | 4565 / 5000 | 恒压目标电压与最大电流 |
| `tc_vol_thr_mv` / `tc_thr_soc` | 4500 / 98 | 涓流触发电压与 SOC |
| `tc_full_ma` / `tc_vol_full_mv` | 400 / 4485 | 涓流截止电流与满充电压 |
| `curr_inc_wait_cycles` | 4 | 升流等待周期 |
| `batt_full_thr_mv` | 4570 | 判定满充的电压阈值 |

注意：这组键由闭源二进制解释，本文只能确认配置文件内容；`ufcs_max=9100` 与 DT 的 14600 mA 上限不是同一层，实际电流取投票/协商结果（见 5.6）。

## 10. 运行时行为（`service.sh`）

开机完成后执行，和菜单选项无关：

- `chg_ctl load_config` 不是“重新加载 DTBO”，而是读取 `/data/opbatt/chg_config`，恢复 PPS/UFCS/SVOOC 的使能状态和伪装温度设置；`ioauth ufcs` 在后台运行。
- 日志写入 `/data/opbatt/battchg.log`，超过 5 MiB 清空；每次循环重写 `module.prop` 的描述，写入 WebUI 地址和 DTBO 校验结果。
- 启动时校验一次 `/dev/block/bootdevice/by-name/dtbo<slot>` 与模块内 `dtbo.img` 的 md5；不一致时在模块描述里提示“DTBO 镜像已被修改，请重新刷入模块”。
- 刷新深度放电计数：

```sh
origin_ddc=$(cat /sys/class/oplus_chg/common/deep_dischg_counts)
echo 1 > /sys/class/oplus_chg/common/deep_dischg_counts
echo 1 > /sys/class/oplus_chg/common/deep_dischg_count_cali
echo $origin_ddc > /sys/class/oplus_chg/common/deep_dischg_counts
echo 0 > /sys/class/oplus_chg/common/deep_dischg_count_cali
```

这两个节点在 `oplus_configfs.c:3412-3485` 中有定义，都是 `DEVICE_ATTR_RW`，写入会调用 `oplus_gauge_set_deep_dischg_count()` 和校准值设置。它的作用是**重置深放电计数和校准标志**，让 DD RC 统计从干净状态开始；它不是直接改 FCC 寄存器。第 1 节的 `term_coeff` 清零才是 DTS 侧的 FCC/SOH 系数修正，`count_step` 清零是深放电阶梯计数修正，两者配合使用。

- 把 `bcc_current` 写为 13700，`normal_cool_down`、`cool_down` 写 0，然后把这三个节点改成只读；把 `current_now` 改成 0444。`bcc_current` 是 BCC 闭环的目标电流，不是硬性限流；`normal_cool_down`/`cool_down` 在 `oplus_configfs.c` 中分别有只写/读写属性。
- 循环执行 `$MODDIR/bin/opbatt_control`；退出码 1/2 等 10 秒重试，3–6 也等 10 秒重启服务。

因此安装提示（`customize.sh:171`）要求“重启时断开充电器”，让解容和统计刷新在无充电器状态下完成第一次校准。

## 11. 生效范围与注意事项

- 本次核对范围是 charger v2 的 DT 解析与控制路径；`rm_dsi_timming` 和 `sh_patch_hm` 属于其它子系统，未核对。
- 除 CPA 协议表外，只修改 `silicon_p_770` 子节点中的指定内容。上层同名表（如第 4539 行）和上层 UFCS/LCF 副本不会被 `oplus_get_node_by_type()` 选中，属于死数据；不要为了“改全”去动它们。
- 当前 `dts.dtb.5` 的 DD RC 曲线是 2900 mV（提交 `09eaba9`），模块 `patch_ddrc_1.dts` 仍是 2800 mV。手改 dts 与走模块安装会产生不同的关机点，不能混用。
- `patch_soc_smooth` 的两个 `oplus,reserve_*` 属性、`patch_chg_boost` 的 `oplus,ufcs_charge_strategy_soc`、`force_rm_lcf` 的上层两条和 PPS 两条，都是无效/空操作；文档已不再把它们计入有效修改。
- `oplus,ufcs_charge_strategy_soc` 虽然还在补丁里，但没有任何驱动读取；真正决定 UFCS SOC 分档的是 `ufcs_charge_*_strategy/oplus,soc_range`。
- 第 4–8 节的行号是当前 `dts.dtb.5` 的行号；第 5 节的策略块必须整块替换，不要按单个数值零散修改。
- 模块安装时是从 `patch/PJZ110/*.dts` 重新编译并叠加，不读取 `dts.dtb.5`。手改 `dts.dtb.5` 只对“手工打包 dtbo”的流程有意义；如果继续用模块刷入，必须同步修改 `patch/PJZ110/` 下的补丁文件。
- 打包、签名和刷入流程见 `PJZ110_dtbo_pack.md`。

## 附：源码索引

| 功能 | 位置 |
|---|---|
| 按电池类型选节点 | `mms/gauge/oplus_sili.c:2090` `oplus_get_node_by_type()` |
| deep_spec 解析 | `mms/gauge/oplus_sili.c:2505` `oplus_gauge_parse_deep_spec()` |
| DD RC 曲线解析 | `strategy/oplus_strategy_ddrc.c:330` 起 |
| DD RC 投票与关机电压 | `mms/gauge/oplus_sili.c:1317` `oplus_gauge_update_ddrc_data()` |
| 平滑预留表解析 | `strategy/oplus_strategy_battery_smooth.c:1310` 起 |
| smooth SOC 旧开关 | `oplus_chg_comm.c:9018`、`:9085` |
| UFCS 电流/满充属性 | `oplus_chg_ufcs.c:7400` 起 |
| UFCS LCF 解析 | `oplus_chg_ufcs.c:8288` `oplus_ufcs_parse_lcf_strategy_dt()` |
| UFCS LCF 运行 | `oplus_chg_ufcs.c:4234` `oplus_ufcs_update_low_curr_full()` |
| LCF 策略实现 | `strategy/oplus_strategy_low_curr_full.c` |
| PPS LCF 解析/运行 | `oplus_chg_pps.c:6231`、`:3193` |
| PPS SOC 分档 | `oplus_chg_pps.c:5819` |
| CPA 协议表 | `oplus_chg_cpa.c:1847` 起 |
| LCF alarm 消费 | `oplus_batt_bal.c:3358` |
| 深放电 sysfs | `oplus_configfs.c:3412-3485` |
