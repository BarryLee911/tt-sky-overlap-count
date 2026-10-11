# Negative controls (formal flow must reject each mutant)

| Mutant (applied to src/project.v) | equiv_status |
|---|---|
| tie rule: new_ge_first_d uses `!in_ne_current` instead of `in_ge_current` | 36 unproven -> rejected |
| buffer compare: `new_ge_buffer_d` ignores a same-edge processing (`in_ge_buffer` only) | 18 unproven -> rejected |
| divider: after a strobe, `take = terminal[0]` instead of `~terminal[0]` | 2 unproven -> rejected |
| magnitude compare: drop the `x <= 128` guard | 36 unproven -> rejected |

The unmodified RTL: 2338 proven, 0 unproven (formal_equiv.log).
