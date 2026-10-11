# SKY130 80 MHz：AREA 0／DELAY 0 对照结果

两组从同一 80 MHz 基线提交创建，并分别重新构建。固定 6×2 tiles，功能 RTL、管脚、档位和 80000 拍等待不变。

时钟 12.5 ns；I/O 延迟 2.5 ns；转换时间上限 0.75 ns；扇出上限 10；负载沿用库限制；margin、工具和 PDK 与基线一致。

## 结果摘要

| 检查项 | AREA 0 | DELAY 0 |
| --- | ---: | ---: |
| 完整 GDS／网表 | 已生成 | 已生成 |
| 工具／配置／源码审计 | 通过 | 通过 |
| GitHub GDS 工作流 | 未通过 | 未通过 |
| RTL 功能 | 通过 | 通过 |
| 门级功能 | 通过 | 通过 |
| DRC／LVS／天线指标 | 通过 | 通过 |
| 官方 precheck | 通过 | 通过 |
| 九角 Setup／Hold | 未通过 | 未通过 |
| 转换时间／负载／扇出 | 未通过 | 未通过 |
| 全部必需检查 | 未通过 | 未通过 |
| 最差 Setup 余量 ns | -1.967697 | -2.240875 |
| 最差 Hold 余量 ns | 0.107770 | 0.108396 |
| 综合单元面积 µm² | 77030.128000 | 79215.974400 |
| 综合单元数量 | 4987 | 5158 |
| 最终标准单元面积 µm² | 122479.000000 | 123134.000000 |
| 最终标准单元数量 | 12345.000000 | 12364.000000 |
| Hold 修复插入缓冲器总数 | 3240 | 3029 |

## 可比性和基线复现

- 两组实际解析配置：仅 SYNTH_STRATEGY 不同，可直接比较。
- 源码、封装和测试文件逐字节一致，SHA256 校验通过。
- 初始配置审计误用了四个旧参数名，导致原工作流跳过门级和 precheck。补检只按当前名称重新核验、打包已有 GDS，未修改配置或重新布局；原始审计与失败状态均保留。
- 新 AREA 0 对既有 AREA 0：九角余量、违例数、最终单元面积和数量均复现；解析配置一致。

## 构建链接

- [AREA 0 分支](https://github.com/BarryLee911/tt-sky-ucl-project-v6/tree/experiment/80mhz-area0)：[gds](https://github.com/BarryLee911/tt-sky-ucl-project-v6/actions/runs/37691499016)；[test](https://github.com/BarryLee911/tt-sky-ucl-project-v6/actions/runs/37691499019)；[80MHz area0 existing GDS postchecks](https://github.com/BarryLee911/tt-sky-ucl-project-v6/actions/runs/37693636598)；提交 `3882a2a4cda83ed034e30af1dfc7536e3742d42a`。
- [DELAY 0 分支](https://github.com/BarryLee911/tt-sky-ucl-project-v6/tree/experiment/80mhz-delay0)：[gds](https://github.com/BarryLee911/tt-sky-ucl-project-v6/actions/runs/37691507683)；[test](https://github.com/BarryLee911/tt-sky-ucl-project-v6/actions/runs/37691507784)；[80MHz delay0 existing GDS postchecks](https://github.com/BarryLee911/tt-sky-ucl-project-v6/actions/runs/37693636508)；提交 `f25182a6755a11480a2eae29e940396701fd1996`。

## 九角时序

| Corner | AREA Setup ns | DELAY Setup ns | AREA Hold ns | DELAY Hold ns |
| --- | ---: | ---: | ---: | ---: |
| nom_tt_025C_1v80 | 5.237371 | 4.820438 | 0.325747 | 0.319729 |
| nom_ss_100C_1v60 | -1.659488 | -1.940063 | 0.879768 | 0.877245 |
| nom_ff_n40C_1v95 | 7.150904 | 6.912092 | 0.109820 | 0.110258 |
| min_tt_025C_1v80 | 5.415508 | 5.044571 | 0.322690 | 0.316691 |
| min_ss_100C_1v60 | -1.338059 | -1.520860 | 0.866736 | 0.858967 |
| min_ff_n40C_1v95 | 7.217756 | 6.984654 | 0.107770 | 0.108396 |
| max_tt_025C_1v80 | 5.067901 | 4.657115 | 0.329321 | 0.322777 |
| max_ss_100C_1v60 | -1.967697 | -2.240875 | 0.889440 | 0.893006 |
| max_ff_n40C_1v95 | 7.087097 | 6.838622 | 0.111299 | 0.112705 |

## 九角电气违例

| Corner | AREA Slew | DELAY Slew | AREA Cap | DELAY Cap | AREA Fanout | DELAY Fanout |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| nom_tt_025C_1v80 | 6.000000 | 39.000000 | 0.000000 | 0.000000 | 165.000000 | 160.000000 |
| nom_ss_100C_1v60 | 296.000000 | 471.000000 | 1.000000 | 0.000000 | 165.000000 | 160.000000 |
| nom_ff_n40C_1v95 | 6.000000 | 0.000000 | 0.000000 | 0.000000 | 165.000000 | 160.000000 |
| min_tt_025C_1v80 | 6.000000 | 39.000000 | 0.000000 | 0.000000 | 165.000000 | 160.000000 |
| min_ss_100C_1v60 | 164.000000 | 415.000000 | 1.000000 | 0.000000 | 165.000000 | 160.000000 |
| min_ff_n40C_1v95 | 6.000000 | 0.000000 | 0.000000 | 0.000000 | 165.000000 | 160.000000 |
| max_tt_025C_1v80 | 6.000000 | 61.000000 | 0.000000 | 0.000000 | 165.000000 | 160.000000 |
| max_ss_100C_1v60 | 342.000000 | 530.000000 | 1.000000 | 0.000000 | 165.000000 | 160.000000 |
| max_ff_n40C_1v95 | 6.000000 | 0.000000 | 0.000000 | 0.000000 | 165.000000 | 160.000000 |

## 最差路径和 Hold 修复

### AREA 0

- 起点：`core.sample_position[2]`；终点：`core.peak_second_position[4]`。
- Arrival／Required／Slack：16.076336／14.108638／-1.967697 ns；Arrival 包含时钟到达时间，不等于纯组合逻辑延迟。
- `runs/wokwi/37-openroad-resizertimingpostcts/openroad-resizertimingpostcts.log`：插入 3240 个 Hold 缓冲器。

### DELAY 0

- 起点：`core.stats_reset`；终点：`core.overlap_history[1567]`。
- Arrival／Required／Slack：16.239674／13.998798／-2.240875 ns；Arrival 包含时钟到达时间，不等于纯组合逻辑延迟。
- `runs/wokwi/37-openroad-resizertimingpostcts/openroad-resizertimingpostcts.log`：插入 3029 个 Hold 缓冲器。

Hold 数量是工具日志记录的插入次数，不能视为最终仍存在的唯一缓冲器数量。

## 产物与限制

- 两组源码检出位于各自 `source/`；完整 ZIP、SHA256 收据、文件清单与提取产物位于各自 `artifacts/`。
- 构建日志、GDS、网表、LEF、SPEF、逐角 STA 报告和物理检查结果均保留；失败状态未隐藏。
- 门级测试使用功能模型，不含 SDF，不能证明实物 80 MHz 时序。
- 80 MHz 仍为实验条件；FPGA、ADC、管脚和实物测试另行进行。本轮不包含正式登记、付款和流片提交。
