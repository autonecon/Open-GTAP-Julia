# Sticky wages

`StickyWages` makes real wages adjust slowly after a shock, so a shock moves employment first and wages catch up over the following years. It is the lagged real-wage rule of the MONASH model (Dixon and Rimmer 2002) as used in GTAP-MVH (Dixon, Rimmer and Tran 2019). Status: reviewed and tested.

## Turn it on or off

```julia
include("GTAP-modules/GTAPModules.jl")      # loads this module too

spec = ModelSpec(GtapRD(), StickyWages(alpha=0.5))   # on, in a dynamic run
spec = ModelSpec(StickyWages())                      # on, in a single static solve
spec = ModelSpec(GtapRD())                           # off
```

To turn it off, leave it out of the `ModelSpec`. Nothing else changes. If the model already has the module attached from an earlier run, leaving it out of the spec puts it in its baseline closure, which reproduces standard GTAP exactly, so you do not need to rebuild the model. The baseline is the same with or without the module, so one baseline can serve policy runs with and without sticky wages.

| Option | Default | Meaning |
| --- | --- | --- |
| `alpha` | 0.5 | How fast the real wage responds to the gap between employment and its baseline. Dixon and Rimmer choose it so most of the employment effect is gone after about five years |

## What it does

For each labour type and region:

```
W_t / W_t^F − 1 = (W_t−1 / W_t−1^F − 1) + α · (E_t / E_t^F − L_t / L_t^F) + SHIFT
```

`W` is the real wage (the factor price over the consumer price, `pe / ppriv`), `E` is employment (`qe`), `L` is labour supply, and `^F` marks the baseline value. Labour supply follows its baseline, so `L_t / L_t^F = 1`.

- **Baseline:** employment is fixed at the labour-force path, and `SHIFT` takes whatever value that needs. So the baseline is standard GTAP-RD.
- **Policy:** `SHIFT = 0` and employment is free. A shock first moves employment; the real wage then moves each year until employment is back on its baseline path.
- **Static run:** the same rule for one year, starting from the base (the first-year response).

Labour types are every endowment that is not capital, land or a fixed factor (see [`GTAP-RD/`](../../GTAP-RD/README.md)). The module needs no data beyond the baseline. `write_labour_report(path, run)` writes the real-wage and employment deviations of a policy run to a CSV file.

## Checks

`checks/check_modules.jl`: base re-solve with the module attached, flexible against sticky wages in a static tariff shock (the wage moves by α times the employment change), the same baseline with the module on and off, and a policy run with no shock reproducing the baseline.

## References

- Dixon, P. B. and Rimmer, M. T. (2002), *Dynamic General Equilibrium Modelling for Forecasting and Policy: A Practical Guide and Documentation of MONASH*, Contributions to Economic Analysis 256, North-Holland, Amsterdam.
- Dixon, P. B., Rimmer, M. T. and Tran, N. (2019), *GTAP-MVH, a model for analysing the worldwide effects of trade policies in the motor vehicle sector: theory and data*, CoPS Working Paper G-290, Centre of Policy Studies, Victoria University, Melbourne.
