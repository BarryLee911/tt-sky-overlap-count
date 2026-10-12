# Overlap Count

Counts sign agreement between input samples and an internal reference, with amplitude tracking.

[![gds](https://github.com/BarryLee911/tt-sky-overlap-count/actions/workflows/gds.yaml/badge.svg)](https://github.com/BarryLee911/tt-sky-overlap-count/actions/workflows/gds.yaml) [![docs](https://github.com/BarryLee911/tt-sky-overlap-count/actions/workflows/docs.yaml/badge.svg)](https://github.com/BarryLee911/tt-sky-overlap-count/actions/workflows/docs.yaml) [![test](https://github.com/BarryLee911/tt-sky-overlap-count/actions/workflows/test.yaml/badge.svg)](https://github.com/BarryLee911/tt-sky-overlap-count/actions/workflows/test.yaml) [![equivalence](https://github.com/BarryLee911/tt-sky-overlap-count/actions/workflows/equivalence.yaml/badge.svg)](https://github.com/BarryLee911/tt-sky-overlap-count/actions/workflows/equivalence.yaml)

## Function

- Accepts unsigned 8-bit samples centered on 128.
- Counts sign agreement over a 2048-sample window and tracks an approximate peak magnitude over about 1024 samples.
- Provides alternating count and magnitude results on an 11-bit output, with selectable sampling levels 0-23.

## Use

See the [pinout and operating instructions](docs/info.md) for reset, configuration, sampling and result capture. Results alternate every clock; read TYPE with each result.

View the layout in the [3D viewer](https://barrylee911.github.io/tt-sky-overlap-count/).

Implementation: SKY130, 6x2 tiles, 80 MHz build target.

## Build status

Hardware revision [`e28004b`](https://github.com/BarryLee911/tt-sky-overlap-count/commit/e28004be91a6c4317c196f91f2baf36358879f02) passed [GDS, precheck, gate-level test and viewer](https://github.com/BarryLee911/tt-sky-overlap-count/actions/runs/38254450471), [RTL tests](https://github.com/BarryLee911/tt-sky-overlap-count/actions/runs/38254450660), [documentation checks](https://github.com/BarryLee911/tt-sky-overlap-count/actions/runs/38254450473) and [cycle-equivalence checks](https://github.com/BarryLee911/tt-sky-overlap-count/actions/runs/38254450508). See [verification instructions](test/equivalence/README.md) for the check scope and local commands.

80 MHz is a build target and exceeds the published input-pad rating. Worst-corner setup slack is approximately -0.111 ns; operation on fabricated hardware has not been verified.
