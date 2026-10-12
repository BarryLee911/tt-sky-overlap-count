# How it works

Counts sign agreement between input samples and an internal reference, with amplitude tracking.

The input is an unsigned 8-bit sample centered on 128. Values below 128 have sign 0; values at or above 128 have sign 1. The internal square reference repeats every 2048 captured samples, with 1024 samples in each half-period.

COUNT reports sign agreement over the most recent 2048 samples. Unfilled positions count as zero at startup, and the 11-bit result saturates at 2047. MAGNITUDE tracks the approximate peak of `abs(SAMPLE - 128)` over about 1024 samples, in the range 0-128. It is not an exact sliding maximum.

# How to test

## Pins

| Pin | Direction | Function |
| --- | --- | --- |
| `ui[7:0]` | Input | Unsigned 8-bit SAMPLE |
| `uo[7:0]` | Output | Result bits 7:0 |
| `uio[7:5]` | Output | Result bits 10:8; do not drive externally |
| `uio[4:1]` | Input | LEVEL bits 4:1 during configuration |
| `uio[0]` | Input, then output | LEVEL bit 0 during configuration; TYPE after handoff |
| `clk` | Input | Clock |
| `rst_n` | Input | Low-active synchronous reset |
| `ena` | Input | Not used as an operation control |

## Reset and configuration

1. Apply a clock and hold `rst_n` low for at least two rising edges.
2. Set LEVEL on `uio[4:0]` to a value from 0 to 23, then release reset. The first rising edge with a valid level latches it. Levels 24-31 do not start operation.
3. Keep SAMPLE stable around each capture edge. The first sample is captured `2^LEVEL` clocks after the configuration edge; subsequent samples use the same interval. LEVEL 0 captures on every clock, starting on the next edge.
4. Release external drive on `uio[0]` after configuration and before the 80000th clock after the configuration edge. At that edge the chip drives TYPE on this pin. At the 80 MHz build target this interval is 1 ms.

The level remains latched until reset. Reset is required to change it. Sampling rate is `f_clk / 2^LEVEL`; window lengths are measured in captured samples rather than clocks.

## Reading results

Combine `{uio[7:5], uo[7:0]}` as an 11-bit value and read TYPE at the same time:

| TYPE | Result | Range |
| --- | --- | --- |
| 0 | COUNT | 0-2047 |
| 1 | MAGNITUDE | 0-128 |

The handoff edge presents COUNT; the next edge presents MAGNITUDE. Results then alternate every clock, independently of the sampling interval. Capture the registered outputs after they settle following each rising edge.

A sample captured at edge N updates statistics at N+1 and can appear from N+2 in the next slot for its result type. Read TYPE with each result rather than treating adjacent words as a simultaneous pair, especially at LEVEL 0. With slow sampling, handoff can occur before the first sample; zero results during this wait are normal.

## Build target

The current design targets 80 MHz on SKY130 with 6x2 tiles. This exceeds the published input-pad rating. The verified hardware revision is `e28004b`; its worst-corner setup slack is approximately -0.111 ns. Passing the build and simulation checks does not establish reliable 80 MHz operation on fabricated hardware.

# External hardware

A clock source, an 8-bit digital sample source, configuration drivers and a device to capture the result pins. Synchronize SAMPLE to the clock and release the shared configuration/TYPE pin before handoff.
