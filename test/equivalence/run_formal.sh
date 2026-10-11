#!/bin/sh
# Formal sequential equivalence (Yosys equiv_make / equiv_simple / equiv_induct).
#
# gold = v6 RTL (v6_reference.v: byte-identical to SHA256 E070E865... apart from the
#        module name), copied to gold_observed.v with ONE extra observation wire:
#          prescale_terminal_is_mask = (terminal & (terminal + 1)) == 0
# gate = ../../src/project.v, copied to gate_observed.v with the matching wire tied to 1.
#
# Matching the two wires makes the induction also prove that v6's latched terminal is
# always 0 or 2^level - 1, which the new RTL relies on to form terminal - 1 without an
# adder. The observation wires drive nothing; neither design's behaviour is altered.
set -e
cd "$(dirname "$0")"
sed 's/^endmodule/    (* keep *) wire prescale_terminal_is_mask =\n        ((prescale_terminal_latched \& (prescale_terminal_latched + 27'"'"'d1)) == 27'"'"'d0);\nendmodule/' \
    v6_reference.v > gold_observed.v
sed 's/^endmodule/    (* keep *) wire prescale_terminal_is_mask = 1'"'"'b1;\nendmodule/' \
    ../../src/project.v > gate_observed.v
${YOSYS:-yosys} -q -l formal.log equiv.ys
grep -E "are proven and" formal.log
