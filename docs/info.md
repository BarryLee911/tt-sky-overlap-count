# How it works

Counts sign agreement with a 2048-sample internal square reference and tracks an approximate peak over 1024 samples. Area and peak alternate on the result pins.

# How to test

Drive unsigned ADC data on ui[7:0]. Hold a valid level 0-23 on uio[4:0] after reset.
The first valid level is latched. Sampling starts one full divider interval later.
Release external drive on uio[0] before 80000 clocks; the chip then drives the result type there.
Result bits are uo[7:0] and uio[7:5]. Type 0 is area, type 1 is peak.
Use the matching branch frequency: 40 MHz on main, 80 MHz on experiment/80mhz.
The 80 MHz target exceeds the SKY130 input-pad rating.

# External hardware

FPGA clock and synchronized excitation, external ADC, and the impedance measurement front end.
