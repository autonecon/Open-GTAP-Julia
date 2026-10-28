# GTAP modules

Each run picks its model from a list of modules. Every module lives in its own folder with its own README:

| Module | Folder | What it adds | Status |
| --- | --- | --- | --- |
| `GtapRD` | [`GTAP-RD/`](../GTAP-RD/README.md) | Recursive dynamics: capital accumulation, supply curves for land and natural resources, labour efficiency that hits a GDP path | Reviewed and tested |
| `StickyWages` | [`sticky-wages/`](sticky-wages/README.md) | Real wages that adjust slowly, so shocks move employment for a few years | Reviewed and tested |
| `GtapE` | [`gtap-e/`](gtap-e/README.md) | GTAP-E energy substitution in production | Experimental |
| `IndustryCapital` | [`industry-capital/`](industry-capital/README.md) | Capital fixed by industry within the year, investment by expected return | Experimental |

## Turning modules on and off

A module is on when it is in the run's `ModelSpec` and off when it is not:

```julia
include("GTAP-modules/GTAPModules.jl")   # loads GTAP-RD and every module

ModelSpec()                                  # static GTAP v7, all modules off
ModelSpec(GtapRD())                          # GTAP-RD recursive dynamics
ModelSpec(GtapRD(), StickyWages(alpha=0.5))  # GTAP-RD with sticky real wages
ModelSpec(StickyWages())                     # static, first-year sticky-wage response
ModelSpec(GtapRD(), StickyWages(), GtapE(coal=["coal"], noncoal=["oil", "gas", "petro"], electricity=["ely"]))
ModelSpec(GtapRD(), IndustryCapital(rorflex=5, floor=true))
```

The core model (`src/`) and the GTAP-RD layer are never changed by a module. Two kinds of module behave differently when switched off:

- **Closure modules** (`StickyWages`) add equations that sit in a neutral closure when the module is off. A model that has the module attached reproduces standard GTAP exactly when the module is left out of the spec, so the same model can be run with it on or off without a rebuild.
- **Structural modules** (`GtapE`, `IndustryCapital`) replace parts of the core model. Leaving one out of the spec rebuilds the core model. A policy run must have the same structural modules as its baseline.

Modules are attached to a model once (`attach!`, called by the run functions). The list is kept in `mc.parameters`, so it survives `deepcopy(mc)`. The run functions rebuild and re-attach as needed. If you call `rebuild_model!(mc)` yourself, it drops the module equations but not the list, so also `delete!(mc.parameters, "attached_modules")` before the next run. A module attached with other options (for example another α) is rebuilt, not reused.

## Runs

| Call | Spec | What it does |
| --- | --- | --- |
| `run_static!(spec, mc, base; shock!)` | no `GtapRD` | One solve from `base` after `shock!(mc)` |
| `run_baseline!(spec, mc, base; periods, base_year, apply_shock, gdp_target)` | with `GtapRD` | Baseline path; `gdp_target(region, year)` makes labour efficiency hit real GDP |
| `run_policy!(spec, mc, base, baseline; apply_shock)` | with `GtapRD` | Policy path over the baseline's years, deviations measured against it |

Each returns a `ModelRun`: `rows` (the GTAP-RD path), `states` (solved data by year) and `reports` (rows modules add). In `apply_shock(mc, year)` set the year's drivers and shocks. It runs after the modules, so it can override what they set. [`SSP/`](../SSP/README.md) gives ready-made population, labour and GDP drivers for the OCGE Data Base.

## Combining modules

Each module declares `requires` (modules it needs), `conflicts` (modules it cannot run with), `replaces` (core equation blocks it deletes and rewrites) and `structural`. `ModelSpec` refuses a spec that breaks these, or in which two modules replace the same block. `run_policy!` refuses a policy spec whose structural modules or GtapRD options differ from the baseline's.

All four modules can be combined, with three conditions, each enforced with a clear error:

- `IndustryCapital` needs annual steps.
- `IndustryCapital` does not take GtapRD's `depreciation` option.
- `IndustryCapital` with `GtapE` needs ELKE above zero for every activity (`GtapE(...; elke_fixed=0.1)`). The run stops if any activity has ELKE set to 0, but a uniform `elke=0` is not caught, so do not use it with IndustryCapital.

## Adding a module

Define a `struct <: ModelModule` in its own folder, include it at the end of `GTAPModules.jl`, and write the hooks it needs:

- `extend_model!`: add JuMP variables and equations to `mc.model`, with their entries in `mc.data`, `mc.fixed` and `mc.lower`.
- `ensure_data!`
- `set_closure!(m, mc, phase)`
- `before_solve!` and `after_solve!(m, mc, year, run)`
- `requires`, `conflicts`, `replaces` or `structural` if they apply.

[`sticky-wages/sticky_wages.jl`](sticky-wages/sticky_wages.jl) is the worked example.

## Checks

The module checks are in [`checks/`](../checks/README.md). `checks/check_stepped_period.jl` also tests the stepped fallback every run uses for a year that does not solve in one go.
