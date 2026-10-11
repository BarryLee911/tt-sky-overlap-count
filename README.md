# v6 SKY26d: lookahead timing experiment (changes 1 and 2 only)

![gds](../../actions/workflows/gds.yaml/badge.svg) ![docs](../../actions/workflows/docs.yaml/badge.svg) ![test](../../actions/workflows/test.yaml/badge.svg) ![equivalence](../../actions/workflows/equivalence.yaml/badge.svg)

Parent: `679dbd88bb4a0062b3611c912f4d5e878e2e3574` (official-checks, all four jobs passed).
Baseline RTL: v6, SHA256 `E070E8658952FF7314BFD6CE7E69E035233953CCCED5E57FA44714AE7D9F2FE2`.

This experiment changes only `src/project.v`. Function, ports, parameters, widths,
reset, sampling phase and the N / N+1 / N+2 output pipeline are unchanged: the pins
are cycle-for-cycle identical to v6, and every v6 register is retained with the same
name and the same value on every clock.

1. **Peak-update lookahead.** Candidate expiry (10-bit position compares), buffer /
   candidate distinctness and the three 8-bit magnitude compares are evaluated on the
   edge that captures a sample and are registered (7 flags). The processing edge only
   runs the existing selector logic on registered flags.
2. **Registered sampling strobe.** `take_sample` is a flip-flop computed one edge
   early instead of a 27-bit equality compare in the same cycle.

Implementation configuration, wrapper, functional test, tiles (6x2), clock (80 MHz)
and I/O delay are identical to the parent. The build follows the official Tiny Tapeout
method: `.github/workflows/gds.yaml`, `docs.yaml`, `test.yaml` and `fpga.yaml` are the
unmodified TTSKY26d template files (`TinyTapeout/tt-gds-action@ttsky26d`, sky130A:
GDS -> precheck, gate-level test, GDS viewer; docs check and datasheet; cocotb RTL test).
Project-specific checks live only in `equivalence.yaml`. `scripts/verify_inputs.py`
checks the source, configuration and that the template workflows are unmodified.
The `viewer` job needs GitHub Pages set to "GitHub Actions" (Settings -> Pages).

Verification included here (details and numbers: [docs/lookahead-1-2.md](docs/lookahead-1-2.md)):

- `test/equivalence/run_formal.sh`: Yosys sequential equivalence (equiv_make /
  equiv_induct) against the unmodified v6 RTL. All 2338 matched signals, including
  all output pins and all v6 registers, proven.
- `test/equivalence/tb_equiv.v`: Icarus co-simulation, v6 and new side by side from
  reset, comparing pins and all v6 registers every cycle (also run in the
  `equivalence` workflow).
- `test/equivalence/tb_divider.v`: every legal level 0-23, two full intervals each.
- The existing cocotb pin-level regression (`test/test.py`) is unchanged.

Reproduce: every push runs the official `gds`, `docs` and `test` workflows plus
`equivalence`. Locally: `sh test/equivalence/run_formal.sh`
(Yosys) and the iverilog commands in `test/equivalence/README.md`.

80 MHz remains above the published SKY130 input-pad rating. A passing workflow does
not demonstrate reliable 80 MHz operation across all corners or on hardware. No
shuttle registration, payment, or fabrication submission is performed.
