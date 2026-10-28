# Industry-specific capital (experimental)

`IndustryCapital` fixes each industry's capital within the year, so each industry earns its own rental. New investment then goes where expected returns are highest. Standard GTAP instead moves capital freely between industries within a year at one regional rental. The module follows GTAP-MVH (Dixon, Rimmer and Tran 2019), whose investment theory comes from ORANI (Dixon et al. 1982). Status: experimental.

Open items:

- With GTAP-E also on, the total utility measure `u` can jump in a dynamic run while other variables look normal. This is under investigation.
- The investment floor has not been tested over several years at the floor.
- RORFLEX = 5 is GTAP-MVH's value, not an estimate. Run a sensitivity before using the investment results.

## Turn it on or off

```julia
include("GTAP-modules/GTAPModules.jl")      # loads this module too

spec = ModelSpec(GtapRD(), IndustryCapital(rorflex=5, floor=true))   # on, in a dynamic run
spec = ModelSpec(IndustryCapital())                                  # on, in a static solve
spec = ModelSpec(GtapRD())                                           # off
```

The module changes the model's structure. Switching it off rebuilds the core model, and a policy run must use it if and only if its baseline did. It needs annual steps and does not take GtapRD's `depreciation` option. With GTAP-E it needs ELKE above 0 in every activity, for example `GtapE(...; elke_fixed=0.1)`. Each of these stops with a clear error otherwise, except a uniform `GtapE(...; elke=0)`, which is not caught.

| Option | Default | Meaning |
| --- | --- | --- |
| `rorflex` | 5.0 | How fast an industry's expected return falls as its capital grows. 5 is GTAP-MVH's value; GTAP's regional RORFLEX is 10 |
| `floor` | `true` | An industry's capital can shrink only by depreciation, `KE ≥ (1 − δ) KB`. Where the floor binds, the industry's expected return is below the regional one. `false` lets an industry disinvest faster |
| `mu` | 1e-14 | Smoothing of the floor condition (a smoothed Fischer–Burmeister equation) |

## What it does

```
qes(cap,j,r)  = ρ(r) · KB(j,r)                                    stock fixed within the year
RORC(j,r)     = rental(j,r) / pinv(r) − δ(r)                      GTAP's e_rorc, by industry
RORE(j,r)     = RORC(j,r) · (KE(j,r) / KB(j,r))^(−RORFLEX)         expected return
RORE(j,r)     = F(j,r) · RORE(r)                                  investors equalise
Σ_j KE(j,r)   = KE(r) = qinv(r) + (1 − δ) KB(r)                   ties to the region
```

It replaces the capital rows of the core's `e_qes1` (rental = regional rental) and the regional expected-return equation `e_rore`. The regional stock is still the sum of industry stocks, so GTAP-RD's capital accumulation is unchanged. Because `e_rore` is replaced, a region's expected return comes from its industries' rules, so the module changes how much a region invests as well as where the investment goes. The expected-return equation is in calibrated form, so it holds in the base whatever RORFLEX is.

Data: capital rentals by activity, the regional capital stock and depreciation, which every GTAP-format data base has. Base industry stocks split the regional stock in proportion to capital rentals, as GTAP-MVH does. `industry_capital_report(mc, run)` gives each industry's opening and closing stock, gross investment and whether the floor binds.

## Checks

`checks/check_industry_capital.jl`: base re-solve with the module, a static shock (capital stays put and rentals differ by industry), switching back off reproducing standard GTAP, and over a two-year baseline: industry stocks adding to the regional stock, opening stocks equal to the previous year's closing stocks, and a policy run with no shock reproducing the baseline.

## References

- Dixon, P. B., Rimmer, M. T. and Tran, N. (2019), *GTAP-MVH, a model for analysing the worldwide effects of trade policies in the motor vehicle sector: theory and data*, CoPS Working Paper G-290, Centre of Policy Studies, Victoria University, Melbourne.
- Dixon, P. B., Parmenter, B. R., Sutton, J. and Vincent, D. P. (1982), *ORANI: A Multisectoral Model of the Australian Economy*, Contributions to Economic Analysis 142, North-Holland, Amsterdam.
- The underlying GTAP equations (`e_qes1`, `e_rorc`, `e_rore`): Corong, E. L., Hertel, T. W., McDougall, R., Tsigas, M. E. and van der Mensbrugghe, D. (2017), The Standard GTAP Model, Version 7, *Journal of Global Economic Analysis* 2(1), 1–119.
