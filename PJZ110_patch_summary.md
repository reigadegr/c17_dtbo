# PJZ110 全部功能与 DTBO 修改点清单

机型：PJZ110（一加 13，含 CPH2649/CPH2653/CPH2655 等映射型号）。

目标文件：`/data/local/dtbo_work_space/c17/dts.dtb.5`，下文简称 `dts.dtb.5`。

行号以当前仓库提交中的 `dts.dtb.5` 为准。此前的解容、平滑电量修改都是等行数替换，没有改变后续行号；如果手工插入或删除行，后续行号会变化，应重新按节点路径定位。

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

目标节点：

```text
/fragment@52/__overlay__/oplus,mms_gauge/silicon_p_770
```

原第 4180–4183 行的四项改为：

```dts
deep_spec,count_thr = <0x0>;
deep_spec,vbat_soc = <0x0>;
deep_spec,count_step = <0x0 0x0 0x0>;
deep_spec,term_coeff = <0x0 0x0 0x0>;
```

该节点的 `ddrc_strategy` 内，六组曲线都需要修改：

| 子节点 | 原属性行号 |
|---|---|
| `strategy_ratio_range_min` | 4202–4205 |
| `strategy_ratio_range_low` | 4209–4212 |
| `strategy_ratio_range_mid_low` | 4216–4219 |
| `strategy_ratio_range_mid` | 4223–4226 |
| `strategy_ratio_range_mid_high` | 4230–4233 |
| `strategy_ratio_range_high` | 4237–4240 |

每组的四项统一改为：

```dts
strategy_temp_cold = <0x0 0xaf0 0xaf0 0x0>;
strategy_temp_cool = <0x0 0xaf0 0xaf0 0x0>;
strategy_temp_normal = <0x0 0xaf0 0xaf0 0x0>;
strategy_temp_warm = <0x0 0xaf0 0xaf0 0x0>;
```

`0xaf0` 为 2800 mV。上层第 4089 行附近的同名参数、`deep_spec,ddbc_curve` 以及其他未列出的属性保留原值；补丁虽然也写了上层，但值与机内一致。

需要说清楚的两点：

- 补丁里没有 `fcc`、`capacity`、`oplus,batt_capacity_mah`、`wired-ffc-fcc-ma` 任何一项。所谓“FCC 修正”在 DTS 层面只对应 `term_coeff`/`count_step` 的终止系数清零，真正的统计侧动作在运行时 `service.sh`（见第 10 节）。
- `oplus,batt_capacity_mah`（父层 5610、子层 5920）和满充/FFC 截止电压都没有改。这里的“解容”是撤掉低电端的 DDRC 阶梯，把原本保留的低电端容量放出来，不是把标称容量改大。

## 2. 实际电量值（`patch_soc_smooth`）

目标节点：

```text
/fragment@58/__overlay__/oplus,comm/silicon_p_770
```

在原第 4542 行的 `silicon_p_770 {` 内、已有属性前新增以下两项。检查时这两个属性在目标文件中不存在：

```dts
oplus,reserve_chg_soc = <0x0>;
oplus,reserve_dis_soc = <0x0>;
```

该节点内部 `smooth_strategy` 的原第 4615 行改为：

```dts
oplus_spec,reserve_table_centipercent = <0x0 0x64 0x0 0x0 0x0 0x64>;
```

上层原第 4539 行的同名属性保持原样。注意这是把 18 个数值改成 6 个，属于数组长度变化，不是单纯替换数值；驱动按元素个数解析时行为取决于驱动的容错，手工改之前应先确认。

## 3. 关机相关电压

当前文件中的以下阈值已经是补丁所需的目标值，无需修改：

| 原行号 | 所属节点 | 参数 | 当前值 |
|---|---|---|---|
| 4179 | `oplus,mms_gauge/silicon_p_770` | `deep_spec,uv_thr` | `0xaf0`，2800 mV |
| 4594 | `oplus,comm/silicon_p_770` | `oplus_spec,vbat_uv_thr_mv` | `0xaf0`，2800 mV |
| 4595 | `oplus,comm/silicon_p_770` | `oplus_spec,vbat_charging_uv_thr_mv` | `0xa8c`，2700 mV |
| 4606 | `oplus,comm/silicon_p_770` | `oplus,chg_shutdown_max_mv` | `0xaf0`，2800 mV |

这些阈值已是 2.8V，不代表 DDRC 已经解锁。当前 DDRC 曲线仍包含更高的电压值，仍需完成第 1 节的修改。实际关机行为还受驱动和电池保护逻辑影响。模块的 `patch_ddrc_1.dts` 也没有改这四个显式关机阈值。

## 4. 电池温控（`patch_batt_therm`）

这项取值方向与其它 `patch_*` 选项相反：这里是 0 对应修改版、1 对应官方原值。先看数值：

- `patch_batt_therm_1.dts` 写入的是机内原值（400/420/430 一线），选择“官方电池温控策略”时实际不改变任何数值。
- `patch_batt_therm_0.dts` 才是 48/53 度墙的修改版，选择“充电48度撞墙,伪装后53度撞墙”时生效。

所有温度单位都是 0.1°C。

### 4.1 UFCS 节点

`/fragment@61/__overlay__/oplus,ufcs_charge/silicon_p_770`：

| 行号 | 属性 | 原值 | 改为 |
|---|---|---|---|
| 5024 | `oplus,ufcs_strategy_batt_high_temp` | `<400 420 430 390 410 420>` | `<530 530 530 530 530 530>` |
| 5030 | `oplus,ufcs_charge_strategy_temp` | `<0 50 120 160 350 440 510>` | `<0 50 120 160 400 480 530>` |
| 5063 | `ufcs_charge_third_strategy/oplus,temp_range` | `<0 50 120 160 210 350 440 510>` | `<0 50 120 160 210 400 480 530>` |
| 5129 | `ufcs_charge_oplus_strategy/oplus,temp_range` | `<0 50 120 160 210 350 440 510>` | `<0 50 120 160 210 400 480 530>` |

### 4.2 PPS 节点

`/fragment@71/__overlay__/oplus,pps_charge/silicon_p_770`：

| 行号 | 属性 | 原值 | 改为 |
|---|---|---|---|
| 6218 | `oplus,pps_strategy_batt_high_temp` | `<410 420 430 400 410 420>` | `<530 530 530 530 530 530>` |
| 6223 | `oplus,pps_charge_strategy_temp` | `<0 50 120 160 350 440 510>` | `<0 50 120 160 400 480 530>` |
| 6228 | `pps_charge_third_strategy/oplus,temp_range` | `<0 50 120 160 210 350 440 510>` | `<0 50 120 160 210 400 480 530>` |
| 6294 | `pps_charge_oplus_strategy/oplus,temp_range` | `<0 50 120 160 210 350 440 510>` | `<0 50 120 160 210 400 480 530>` |

### 4.3 VOOC 温度档位

`/fragment@52/__overlay__/oplus,adsp-voocphy`：

| 行号 | 属性 | 原值 | 改为 |
|---|---|---|---|
| 4005 | `oplus_spec,vooc_low_temp` | `<0>` | `<0>`（不变） |
| 4006 | `oplus_spec,vooc_little_cold_temp` | `<50>` | `<0>` |
| 4007 | `oplus_spec,vooc_cool_temp` | `<120>` | `<0>` |
| 4008 | `oplus_spec,vooc_little_cool_temp` | `<160>` | `<100>` |
| 4009 | `oplus_spec,vooc_little_cool_high_temp` | `<210>` | `<150>` |
| 4010 | `oplus_spec,vooc_normal_low_temp` | `<350>` | `<420>` |
| 4011 | `oplus_spec,vooc_normal_high_temp` | `<440>` | `<480>` |
| 4012 | `oplus_spec,vooc_high_temp` | `<500>` | `<530>` |
| 4013 | `oplus_spec,vooc_over_high_temp` | `<510>` | `<550>` |

`patch_batt_therm_1.dts` 会把这些 VOOC 档位写回 `<0 50 120 160 210 350 440 500 510>`。

### 4.4 与温控配套的 batt_control 表

`customize.sh` 会根据本项选择，在 `/data/opbatt/batt_control` 头部追加温度-电流偏移表：

- 选择 0（48/53 度墙）：`temp_range=42,43,44,45,46`，`temp_curr_offset=800,1200,1800,2500,4500`。
- 选择 1（官方）：`temp_range=39,40,41,42,43`，`temp_curr_offset=500,1000,1500,2000,4000`。

## 5. 充电增强（`patch_chg_boost`）

这项补丁把 UFCS/PPS 的协议功率、电流上限、满充电压和 SOC 分档整体改写，涉及 171 处属性值。标量属性逐行列在下表；四段策略曲线是整块替换，按块处理即可。

### 5.1 CPA 协议表

`/fragment@61/__overlay__/oplus,cpa`：

| 行号 | 属性 | 原值 | 改为 |
|---|---|---|---|
| 4744 | `oplus,protocol_list` | `<0x4 0x64 0x3 0x64 0x2 0x37 0x1 0x12 0x5 0x12>` | `<0x4 0x96 0x3 0x64 0x2 0x55 0x1 0x12 0x5 0x12>` |

按协议号配对读：协议 4 的功率从 100 W 提到 150 W，协议 2 从 55 W 提到 85 W，其余不变。`oplus,default_protocol_list` 不变。

### 5.2 UFCS 标量属性

`/fragment@61/__overlay__/oplus,ufcs_charge/silicon_p_770`：

| 行号 | 属性 | 原值 | 改为 | 说明 |
|---|---|---|---|---|
| 5004 | `oplus,curr_max_ma` | `0x238c` | `0x3908` | 9100 → 14600 mA |
| 5008 | `oplus,ufcs_strategy_normal_current` | `0x238c` | `0x3908` | 9100 → 14600 mA |
| 5009 | `oplus,ufcs_over_high_or_low_current` | `0x238c` | `0x3908` | 9100 → 14600 mA |
| 5012 | `oplus,ufcs_ibat_over_third` | `0x1518` | `0x3908` | 5400 → 14600 mA |
| 5013 | `oplus,ufcs_ibat_over_oplus` | `0x2904` | `0x3908` | 10500 → 14600 mA |
| 5014 | `oplus,ufcs_ibus_over_oplus` | `0x2af8` | `0x3778` | 11000 → 14200 mA |
| 5017 | `oplus,ufcs_full_normal_hw_vbat` | `0x1202` | `0x11da` | 4610 → 4570 mV |
| 5020 | `oplus,ufcs_full_cool_sw_vbat_third` | `0x1194` | `0x11f8` | 4500 → 4600 mV |
| 5021 | `oplus,ufcs_full_normal_sw_vbat_third` | `0x1194` | `0x11f8` | 4500 → 4600 mV |
| 5022 | `oplus,ufcs_full_normal_hw_vbat_third` | `0x11bc` | `0x11da` | 4540 → 4570 mV |
| 5025 | `oplus,ufcs_strategy_high_current` | `<0x1388 0xfa0 0xbb8 0x238c 0x1388 0xfa0>` | `<0x1388 0xfa0 0xbb8 0x3908 0x1388 0xfa0>` | 第 4 档 9100 → 14600 mA |
| 5028 | `oplus_spec,ufcs_high_soc` | `0x5f` | `0x63` | 95 → 99 |
| 5029 | `oplus,ufcs_charge_strategy_soc` | `... 0x55 0x5f` | `... 0x55 0x63` | 末档 95 → 99 |
| 5062 | `ufcs_charge_third_strategy/oplus,soc_range` | `... 0x55 0x5f` | `... 0x55 0x63` | 同上 |
| 5128 | `ufcs_charge_oplus_strategy/oplus,soc_range` | `... 0x55 0x5f` | `... 0x55 0x63` | 同上 |

### 5.3 UFCS 策略块（整块替换）

| 行号范围 | 节点 | 替换内容 |
|---|---|---|
| 5060–5124 | `silicon_p_770/ufcs_charge_third_strategy` | `patch_chg_boost_1.dts` 第 46–109 行 |
| 5126–5190 | `silicon_p_770/ufcs_charge_oplus_strategy` | `patch_chg_boost_1.dts` 第 111–174 行 |

每块包含 6 个 SOC 区间的 7 个温度段曲线。补丁把原来的末尾温区从 350/440/510 扩到 400/480/530，并整体改写各段的电压/电流组合；数值以补丁文件为准，不要按原块逐项微调，直接整块替换更安全。

`oplus,ufcs_charge` 下还有两份同名策略副本在第 4856–4920、4922–4986 行，那是模块没有覆盖的上层副本，保持原样。

### 5.4 PPS 标量属性

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

### 5.5 PPS 策略块（整块替换）

| 行号范围 | 节点 | 替换内容 |
|---|---|---|
| 6225–6289 | `silicon_p_770/pps_charge_third_strategy` | `patch_chg_boost_1.dts` 第 207–270 行 |
| 6291–6355 | `silicon_p_770/pps_charge_oplus_strategy` | `patch_chg_boost_1.dts` 第 272–335 行 |

与 UFCS 相同：6 个 SOC 区间 × 7 个温度段，整块替换。

### 5.6 运行时上限不一致

DT 里 UFCS 上限被提到 14600 mA、PPS 提到 6500 mA，但 `/data/opbatt/batt_control` 里仍是 `ufcs_max=9100`、`pps_max=5000`，`service.sh` 又把 `bcc_current` 写成 13700。实际能跑到哪一档取决于 `opbatt_control` 和充电器的协商顺序，需要实测确认哪一层先限流，不能只看 DT 值。

## 6. 面板刷新率策略移除（`rm_dsi_timming`）

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

## 7. LCF 策略节点移除（`force_rm_lcf`）

`force_rm_*` 不走菜单，每次安装都会执行。PJZ110 的清单有 6 条，实际命中 4 条：

| 清单行 | 目标节点 | 目标文件行号 |
|---|---|---|
| `r oplus_ufcs_charge ufcs_oplus_lcf_strategy` | `&oplus_ufcs_charge/ufcs_oplus_lcf_strategy` | 4828–4840 |
| `r oplus_ufcs_charge ufcs_third_lcf_strategy` | `&oplus_ufcs_charge/ufcs_third_lcf_strategy` | 4842–4854 |
| `r oplus_ufcs_charge silicon_p_770/ufcs_oplus_lcf_strategy` | `&oplus_ufcs_charge/silicon_p_770/ufcs_oplus_lcf_strategy` | 5032–5044 |
| `r oplus_ufcs_charge silicon_p_770/ufcs_third_lcf_strategy` | `&oplus_ufcs_charge/silicon_p_770/ufcs_third_lcf_strategy` | 5046–5058 |
| `r oplus_pps_charge silicon_p_770/pps_oplus_lcf_strategy` | 目标文件中不存在该节点 | — |
| `r oplus_pps_charge silicon_p_770/pps_third_lcf_strategy` | 目标文件中不存在该节点 | — |

删除的是整棵 LCF 曲线节点。PPS 的两条找不到符号，`fdtput` 失败后被静默忽略，不是错误。

## 8. 内核 hmbird 模式（`sh_patch_hm`）

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

`customize.sh` 把 `patch/PJZ110/batt_control` 复制到 `/data/opbatt/batt_control`，再按第 4.4 节追加温度-电流表。它不写入 DTBO，而是给 `bin/opbatt_control` 在开机后读取。主要参数：

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

## 10. 运行时行为（`service.sh`）

开机完成后执行，和菜单选项无关：

- `chg_ctl load_config` 重新加载充电器配置；`ioauth ufcs` 在后台运行。
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

这段就是第 1 节所说“FCC 统计修复”的运行时部分：它不依赖 `patch_ddrc`，每次开机都执行。

- 把 `bcc_current` 写为 13700，`normal_cool_down`、`cool_down` 写 0，然后把这三个节点改成只读；把 `current_now` 改成 0444。
- 循环执行 `$MODDIR/bin/opbatt_control`；退出码 1/2 等 10 秒重试，3–6 也等 10 秒重启服务。

因此安装提示才会要求“重启时断开充电器”，让解容和统计刷新在无充电器状态下完成第一次校准。

## 11. 生效范围与注意事项

- 只修改上述 `silicon_p_770` 子节点中的指定内容，避免全局替换同名属性；上层同名表（如第 4539 行）保持原样。
- 目标文件的部分原始参数与项目的 `_0` 补丁存在版本差异。本文是按项目 `_1` 补丁对照得到的修改结论，尚未验证当前内核上的实际效果。
- `_0` 不是机内原值：机内子节点是 `vbat_soc=0x50`、`term_coeff` 8 组大电流；`_0` 是 `0x14`、6 组。选 `_0` 是“项目提供的默认参数”，不是恢复本机原厂值。
- 第 4–8 节的行号是当前 `dts.dtb.5` 的行号；第 5 节的策略块必须整块替换，不要按单个数值零散修改。
- 模块安装时是从 `patch/PJZ110/*.dts` 重新编译并叠加，不读取 `dts.dtb.5`。手改 `dts.dtb.5` 只对“手工打包 dtbo”的流程有意义；如果继续用模块刷入，必须同步修改 `patch/PJZ110/` 下的补丁文件。
- 打包、签名和刷入流程见 `PJZ110_dtbo_pack.md`。
