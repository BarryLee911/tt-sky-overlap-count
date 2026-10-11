# Equivalence checks: lookahead RTL vs v6

`v6_reference.v` is the v6 RTL (SHA256 E070E865...) with only the module name changed to
`tt_um_sine_area_detector_v6`; `scripts/verify_inputs.py` checks this byte for byte.

## Formal (Yosys 0.62 tested)

    sh run_formal.sh            # or YOSYS=/path/to/yosys sh run_formal.sh

Expected last line: `Of those cells 2338 are proven and 0 are unproven.`

Register correspondence is by name (all v6 registers keep their names). The v6
combinational terms in `blacklist.txt` exist only on a processing edge; in the new RTL
the same names are registered lookahead flags, so they are not matched. The script adds
one observation wire to temporary copies (`prescale_terminal_is_mask`: v6 expression on
gold, constant 1 on gate) so the induction also proves that the latched terminal is
always 0 or 2^level - 1. Nothing in either design is driven by it.

## Simulation (Icarus Verilog 12)

    iverilog -g2005 -o eq.vvp -P tb_equiv.HANDOFF=40 -P tb_equiv.EPISODES=120 \
        tb_equiv.v v6_reference.v ../../src/project.v
    vvp -n eq.vvp +seed=101

    iverilog -g2005 -o div.vvp tb_divider.v v6_reference.v ../../src/project.v
    vvp -n div.vvp                       # levels 0-23, ~33.5 M clocks

`tb_equiv` starts with a reset edge, then runs random-length resets, invalid levels,
levels 0-9 and eleven stimulus families (uniform, sine, small alphabets for ties, sparse
spikes near 1024 spacing for expiry/refill, extremes, decaying envelopes). Every cycle
it compares all output pins (X counts as a mismatch) and every v6 register. Define
`PINS_ONLY` and `GL_NETLIST` to run it against a synthesized netlist.
