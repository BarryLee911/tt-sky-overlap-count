#!/bin/sh
# usage: run.sh <rtl> <lib> <drivecell> <load_pf> <tag>
RTL=$1; LIB=$2; DRV=$3; LOAD=$4; TAG=$5
printf 'set_driving_cell %s\nset_load %s\n' $DRV $LOAD > $TAG.constr
cat > $TAG.abc <<EOS
strash; dch; map -D 12500; buffer -p; upsize -D 12500; dnsize -D 12500; stime -p
EOS
cat > $TAG.ys <<EOS
read_verilog $RTL
synth -flatten -top tt_um_sine_area_detector
dfflibmap -liberty $LIB
opt_clean
abc -liberty $LIB -constr $TAG.constr -D 12500 -script $TAG.abc -showtmp
opt_clean
stat -liberty $LIB
write_json $TAG.json
EOS
yosys -q -l $TAG.log $TAG.ys >/dev/null 2>&1
echo "== $TAG"
grep -E "^ABC: (WireLoad|Start-point|Path|Gates)|Chip area|Delay =" $TAG.log | grep -E "Delay|Chip area" | tail -3
