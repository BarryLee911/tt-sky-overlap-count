Pre-layout comparison only (not signoff). Synthesis: Yosys 0.62 `synth -flatten`, `dfflibmap`,
ABC `strash; dch; map -D 12500; buffer -p; upsize; dnsize` (run.sh). Timing: sta.py, an NLDM
lookup STA with ideal clock, no wire load, ideal fanout-8 buffer trees, 2.5 ns input delay
(`*_with_inputs.json`) or input paths excluded (`*_reg2reg.json`).
Libraries: sky130_fd_sc_hd__tt_025C_1v80 and gf180mcu_fd_sc_mcu7t5v0__ss_125C_3v00
(from OpenROAD-flow-scripts platforms).
