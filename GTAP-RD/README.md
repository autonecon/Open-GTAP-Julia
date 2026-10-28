# GTAP-RD: recursive dynamics

`GTAPRD.jl` turns the static GTAP v7 model into a recursive dynamic one, after GTAP-RD v1.0 (Aguiar, Corong and van der Mensbrugghe 2019, chapter 3). Each year is a static solve. Between years, capital rolls forward and the year's drivers are applied. Inside a year, investment follows the static model's closure.

```julia
using GlobalTradeAnalysisProjectModelV7
include("GTAP-RD/GTAPRD.jl")
rows = run_path!(mc, cal; periods=5, base_year=2022, gdp_target=(region, year) -> index)
```

Most users will run it through the module system instead, which adds baseline and policy runs and lets other modules join in.

## Turn it on or off

```julia
include("GTAP-modules/GTAPModules.jl")      # loads GTAP-RD too

spec = ModelSpec(GtapRD())                  # on: recursive dynamic baseline and policy runs
spec = ModelSpec()                          # off: one static GTAP v7 solve with run_static!
```

| Option | Default | Meaning |
| --- | --- | --- |
| `supply` | elasticity 0.5 for land and natural resources | Supply curves (`ResourceSupply`); `nothing` holds both fixed |
| `depreciation` | the data base rate | Depreciation rate for capital accumulation between years |
| `drivers` | no growth | Uniform yearly rates in `BaselineDrivers`: `population_growth`, `endowment_growth` (labour only), `productivity_growth`, and `step` (years per period); region-specific paths go in `apply_shock` instead, for example the SSP drivers in [`SSP/`](../SSP/README.md) |

A policy run must use the same GtapRD options as its baseline, or it stops. See [`GTAP-modules/`](../GTAP-modules/README.md) for the run functions.

## What it does

| Piece | How |
| --- | --- |
| Capital | `kb' = kb(1−δ)^n + qinv((1+g)^n − (1−δ)^n)/(g+δ)` for a step of `n` years, with investment growing at `g` across the step. `run_path!` re-solves a multi-year step until capital and investment agree |
| Land and natural resources | Move along iso-elastic supply curves in their real price (price over the private consumption price), elasticity 0.5 for both (`ResourceSupply`, `GTAPRD_SUPPLY`). Solved jointly with the GDP target each year |
| Labour | Grows with the drivers you give it (for example SSP labour force) |
| Productivity | Labour-augmenting: `afe` on every labour endowment, uniform across activities. With `gdp_target`, it moves region by region until real GDP hits the target |
| Policy runs | Labour efficiency and resource supplies start from the baseline, and labour efficiency stays there. A policy run must use the same GTAP-RD options as its baseline, or it stops | GTAP-RD's policy closure |
| Hard years | A year that does not solve in one go is applied in steps, each starting from the last, like GEMPACK's multi-step solutions | — |

Factor roles come from the model's sets: capital is `endwc`, natural resources `endwf`, and land the one sluggish factor in `endws` (where standard GTAP aggregations put land). If your aggregation has more than one sluggish factor, or land that is not sluggish, declare land with `set_land_endowments!(mc, ["land"])`; with more than one sluggish factor and no declaration the run stops rather than guess. Every other endowment counts as labour.

## The `afe` addition to the core

`src/build_model!.jl` has `afe[endw, acts, reg]`, GTAP's factor-augmenting technical change, in the value-added nest:

```
qfe[e,a,r] * afe[e,a,r] = CES demand at the effective price pfe[e,a,r] / afe[e,a,r]
```

This is the levels form of GEMPACK's `qfe = −afe + qva − ESUBVA·(pfe − afe − pva)`. It is 1 in the base and fixed, so a base solve is unchanged. Every factor has its own entry, so capital, land or resource efficiency can be set too.

## Fast solver

`zero_hessian.jl` gives Ipopt an identically zero Hessian (set `ZERO_HESS=1`). The model is a square system with a zero objective, so the solution does not depend on the Hessian; only the iterations on the way can differ. Building the exact Hessian is most of the solve time on larger maps.

## Differences from GTAP-RD v1.0

- The GDP target is a fixed-base index of total real GDP in each region, with population set by the drivers.
- Sector-specific labour efficiency (`afelabadd`) and the optional twist preferences are not implemented.
- The GDP target is met within a tolerance of 0.3%.
- The `depreciation` option changes accumulation between years only; the static model keeps the data base rate.

## Checks

`checks/check_gtap_rd.jl` on the OCGE Data Base; what it tests is described in [`checks/README.md`](../checks/README.md).
