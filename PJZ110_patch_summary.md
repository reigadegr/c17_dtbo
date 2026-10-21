# PJZ110 解容、FCC 修正与实际电量修改结论

机型：PJZ110（一加 13）。

目标文件：`/data/local/dtbo_work_space/c17/dts.dtb.5`。

本文行号均为检查时的原文件行号，插入内容后行号会变化，应结合节点路径定位。检查时已通过 `/system/bin/rg` 定位并读取相关片段；尚未修改目标文件。

## 补丁对应关系

| 功能 | 项目补丁 | 配置 |
|---|---|---|
| 解除电池容量锁定及 FCC 值修正 | `patch/PJZ110/patch_ddrc_1.dts` | `patch_ddrc=1` |
| 实际电量值 | `patch/PJZ110/patch_soc_smooth_1.dts` | `patch_soc_smooth=1` |

解容与 FCC 修正合在同一个补丁中。对应的 `_0.dts` 用于恢复项目提供的官方默认参数。

## 1. 解容及 FCC 修正

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

该节点的 `ddrc_strategy` 内，以下六组曲线都需要修改：

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

其中 `0xaf0` 为 2800 mV。
其中 `0xb54` 为 2900 mV。

上层第 4089 行附近的同名参数、`deep_spec,ddbc_curve` 以及其他未列出的属性保留原值。

## 2. 实际电量值

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

上层原第 4539 行的同名属性保持原样。

## 3. 关机相关电压

当前文件中的以下阈值已经是补丁所需的目标值，无需修改：

| 原行号 | 所属节点 | 参数 | 当前值 |
|---|---|---|---|
| 4179 | `oplus,mms_gauge/silicon_p_770` | `deep_spec,uv_thr` | `0xaf0`，2800 mV |
| 4594 | `oplus,comm/silicon_p_770` | `oplus_spec,vbat_uv_thr_mv` | `0xaf0`，2800 mV |
| 4595 | `oplus,comm/silicon_p_770` | `oplus_spec,vbat_charging_uv_thr_mv` | `0xa8c`，2700 mV |
| 4606 | `oplus,comm/silicon_p_770` | `oplus,chg_shutdown_max_mv` | `0xaf0`，2800 mV |

这些阈值已是 2.8V，不代表 DDRC 已经解锁。当前 DDRC 曲线仍包含更高的电压值，仍需完成第 1 节的修改，才能对应项目的解容补丁。实际关机行为还受驱动和电池保护逻辑影响。

## 适用范围与生效提示

- 只修改上述两个 `silicon_p_770` 节点中的指定内容，避免全局替换同名属性。
- 目标文件部分原始参数与项目的 `_0` 补丁存在版本差异。本文是按项目 `_1` 补丁对照得到的修改结论，尚未验证当前内核上的实际效果。
- 本次仅检查文件并记录结论，未修改、编译或刷写目标 DTBO。
- 按安装脚本提示，应用后应断开充电器再重启，使解容和 FCC 统计修复修改生效。
