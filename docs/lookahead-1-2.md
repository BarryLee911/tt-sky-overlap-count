# v6 SKY26d：只做优化 1 和 2 的提前一拍（lookahead）版本

**结论：功能与 v6 逐拍完全一致（形式等价证明 + 仿真）；只改变时序结构。**
综合前估算显示峰值更新环路明显变短，但真正的布局布线时序必须以本分支的官方 `gds` 构建为准。

## 改了什么

只改 `src/project.v`。端口、参数、位宽、复位、采样相位、N / N+1 / N+2 输出节拍、
4 个工作流以外的配置、6×2、80 MHz、2.5 ns IO、AREA 0 等全部不变。v6 的所有寄存器
都保留，名字相同、每个时钟的值相同。

### 1. 峰值更新提前一拍预计算

v6 在处理沿（N+1）上同时做：10 位位置比较（候选是否过期）→ fill_second / new_is_* →
one-hot 选择 → 18 位以上的 AND-OR 选择，最差路径
`sample_position[2] → peak_second_position[4]`（SS 角 −1.37 ns，其中约 3.5 ns 是位置比较）。

新版在**采样沿（N）**就把处理沿要用到的 7 个判断算好并寄存：

| 寄存器 | 等于 v6 在处理沿上的 |
|---|---|
| `first_alive_q` | `peak_history_valid && peak_first_position != sample_position[9:0]` |
| `second_alive_q` | `peak_second_valid && peak_second_position != sample_position[9:0]` |
| `buffer_diff_first_q` / `buffer_diff_second_q` | `peak_buffer_position != peak_first/second_position` |
| `new_ge_first_q` / `new_ge_second_q` / `new_ge_buffer_q` | `sample_magnitude >= peak_first/second/buffer` |

采样沿上候选状态可能正被上一个样本更新（level 0 每拍采样）。因此把新样本与
**每一个可能成为候选的来源**（当前正处理的样本、first、second、buffer）并行比较，
再用当前处理沿已有的 one-hot 选择信号挑出结果；无处理时直接用当前状态，统计复位时用复位值。
选择信号对任意输入都恰好 one-hot，所以挑出的就是"下一状态"对应的比较结果。

幅度比较 `|code−128| ≥ x` 改写为 `code ≥ 128+x 或 (x ≤ 128 且 code ≤ 128−x)`，对所有
8 位 code/x 穷举验证相等；阈值来自寄存器，ADC 输入只经过两个比较器，不再先做减法。

### 2. 采样使能寄存化

v6：`take_sample = config_latched_valid && (prescale_count == prescale_terminal_latched)`，
27 位比较之后再扇出到 history_pointer、采样寄存器等。新版 `take_sample_q` 在前一拍算好：

- 未锁存：`config_valid && (count == 2^level − 1)`；24 个常数比较与 level 无关地并行完成，
  uio_in 只做选择，27 位比较不在输入路径上。
- 本拍刚采样：下一拍计数为 0，`take = (terminal == 0)`。
- 计数中：`count + 1 == terminal` 等价于 `count == terminal − 1`。terminal 只可能是 0 或
  2^level − 1，所以 terminal − 1 = 清掉第 0 位（terminal 为 0 时全 1），不需要加法器。
  形式证明同时证明了"terminal 只会是 0 或 2^level − 1"这一不变式。

## 验证

| 检查 | 结果 |
|---|---|
| Yosys 0.62 时序等价（equiv_make / equiv_simple / equiv_induct，k=5） | **PASS**：2338 个对应信号全部证明，含全部 24 个输出引脚位和全部 v6 寄存器 |
| 形式检查的负对照（4 个人为注入的错误：tie 规则、buffer 比较、分频 terminal=0、幅度比较 x≤128 条件） | 4 个全部被检出（2–36 个信号无法证明） |
| Icarus 12 并行仿真（v6 与新版同时从复位开始，每拍比较全部引脚和全部 v6 寄存器） | **PASS**：6 个种子 × 120 段（HANDOFF=40）+ 1 个种子 × 30 段（HANDOFF=80000），共 10,742,358 周期，引脚 0 差异、寄存器 0 差异；处理样本 5,647,128 个，其中候选过期 1,621 次、补位 2,072 次、同幅度 tie 263,894 次 |
| 分频全部档位 0–23（每档两个完整间隔，level 23 为 16,777,224 拍） | **PASS**：33,554,622 周期，采样沿、计数器、引脚 0 差异 |
| 综合后通用门级网表（Yosys generic cells，触发器初值 X，HANDOFF=40）从复位开始与 v6 RTL 逐拍比较引脚 | PASS，但只跑了 305 拍（Icarus 门级仿真约 1 拍/秒）：覆盖复位 X 传播、首次锁存、输出交接和约 260 个 level 0 样本。完整门级回归由本分支 `gds` 工作流的 gl_test（SKY130 网表）完成 |
| 原有 cocotb 引脚级回归 `test/test.py` | 未修改；由本分支 `test` 工作流运行 |
| Verilator 5.030 lint（与 LibreLane 相同参数：--Wall --Werror-LATCH --Werror-MULTIDRIVEN） | 无错误；警告与 v6 完全相同（WIDTHTRUNC HANDOFF_LAST、UNUSEDSIGNAL uio_in[7:5]） |
| `scripts/verify_inputs.py` | PASS：配置与 679dbd8 相同、v6 参考文件逐字节一致、只有 project.v 改变 |

仿真激励包括：随机长度复位、非法档位、档位 0–9、均匀随机、正弦、小字母表（大量 tie）、
接近 1024 间隔的尖峰（过期/补位）、极值 0/255/127/128、衰减包络。负对照说明：只比引脚时，
部分"只改变候选位置"的错误在有限仿真里不会反映到输出，所以测试平台同时逐拍比较全部内部寄存器，
最终以形式证明为准。

## 综合前时序估算（不是签核）

方法：Yosys 0.62 综合并用 ABC 映射到标准单元库，自写 NLDM STA：理想时钟、无连线负载、
按最大扇出 8 的理想缓冲树。只用于比较两个 RTL，不代表布局布线结果。
GF180 v6 的估算值（20.17 ns）与 v6 实际布局布线后的最差数据延迟（18.88 ns）同一量级，可作参考。

寄存器到寄存器，最差到达时间（ns）：

| 终点组 | SKY130 TT v6 | SKY130 TT 新版 | GF180 SS 125C 3.0V v6 | GF180 SS 新版 |
|---|---:|---:|---:|---:|
| peak_second / position | 3.578 | **2.234** | 20.172 | **16.843** |
| peak_first / position | 3.073 | **1.974** | 18.659 | **12.892** |
| prescale_count | 4.585 | 3.701 | 16.419 | 16.668 |
| 全部寄存器中的最差 | 4.585 | **3.701** | 20.172 | **18.237** |

- 新增 7 个标志寄存器与 take_sample_q 的寄存器输入路径（SKY130 TT 1.8–3.3 ns）都短于 v6 的最差路径 4.585 ns。
- 含 2.5 ns 输入延迟的 ADC 输入路径变长：SKY130 TT 从 3.59 ns（v6 sample_magnitude）到 4.73 ns。
  v6 在 SS 角的 ui_in 路径不在最差 1000 条路径之内（余量 > 3.75 ns），预计仍为正，但需要在构建报告中确认。
- 综合面积：SKY130 70,815 → 72,994 µm²（+3.1%）；GF180 221,011 → 226,639 µm²（+2.5%）。
  2048 位移位寄存器和 hold 缓冲问题本版没有处理（那是优化 3）。
- GF180 在 SS 角仍远超 12.5 ns；本版不能让 GF180 在 80 MHz 收敛。

## 构建方式（Tiny Tapeout 官方方法）

本仓库直接使用 TTSKY26d 官方模板（ttsky-verilog-template 68c3fd3）的工作流文件，未作修改：
`gds.yaml`（tt-gds-action@ttsky26d，sky130A：GDS → precheck、门级测试、GDS viewer）、
`docs.yaml`（info.yaml / docs/info.md 检查与 datasheet）、`test.yaml`（cocotb RTL 测试）、
`fpga.yaml`（默认不运行）。项目自己的检查只放在 `equivalence.yaml`
（verify_inputs 与 v6 等价仿真）。viewer 作业需要在仓库 Settings → Pages 选择 GitHub Actions。

## 下一步

1. 等 `gds`、`docs`、`test`、`equivalence` 全部完成。
2. 与 679dbd8 对比九角 setup/hold、slew、面积；重点看 SS 角最差 setup 和 ui_in 路径余量。
3. 只有在官方流程全部通过、门级回归通过时才考虑替换提交版本。
