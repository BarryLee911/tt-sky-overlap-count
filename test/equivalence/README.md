# Verification checks

## Continuous integration

The `equivalence` workflow checks source and configuration provenance, then compares the current RTL with `v6_reference.v` using Icarus Verilog. Seeds 101, 202 and 303 compare output pins and matched reference registers every cycle; unknown pin values count as mismatches. CI uses a shortened 40-clock handoff for this comparison. The separate pin-level regression tests the normal 80000-clock handoff.

The reference file is checked byte for byte by `scripts/verify_inputs.py`, apart from its module name. CI does not run the optional Yosys formal check or the separate all-level divider check. No current formal proof result is claimed here.

## Local checks

From the repository root:

```sh
python scripts/verify_inputs.py
cd test/equivalence
iverilog -g2005 -o eq.vvp -P tb_equiv.HANDOFF=40 -P tb_equiv.EPISODES=120 tb_equiv.v v6_reference.v ../../src/project.v
vvp -n eq.vvp +seed=101
vvp -n eq.vvp +seed=202
vvp -n eq.vvp +seed=303
```

Optional divider check, from `test/equivalence`:

```sh
iverilog -g2005 -o div.vvp tb_divider.v v6_reference.v ../../src/project.v
vvp -n div.vvp
```

This exercises levels 0-23 for two full intervals each. It is not part of CI.

Optional formal check, from the repository root, with Yosys installed:

```sh
sh test/equivalence/run_formal.sh
```

Assess the output of that run for the current revision; do not substitute historical proof counts.
