# Checks

Each script reads the OCGE Data Base, aggregates it to five regions (Gulf, China, United States, EU, rest of world) and nine sectors with the energy commodities kept separate, and calibrates. It then runs a set of tests, prints PASS or FAIL for each against its tolerance, and stops with an error if any test fails. These are mechanical tests of the code, not results: the shocks and GDP paths in them are chosen only to exercise the model.

Run them all after any change to the model or the modules:

```
julia --project=checks -e "using Pkg; Pkg.instantiate()"
OCGE_DATA=<folder with the OCGE gsdfset.har, gsdfpar.har, gsdfdat.har> julia --project=checks checks/run_all.jl
```

or one at a time with `julia --project=checks checks/<script>.jl`. Each script runs in its own Julia process and takes a few minutes. `ZERO_HESS=1` (the default here) uses the fast zero-Hessian solver; set `ZERO_HESS=0` to check against the exact Hessian.

| Script | What it tests |
| --- | --- |
| `check_gtap_rd.jl` | Factor roles (land, labour, capital) from the model's sets and from a declaration. `afe` is 1 and fixed in the base, and re-solving the base changes nothing. Capital rolls forward. Endowment growth reaches every labour type. One five-year step against five annual steps. Labour efficiency against the same growth in labour quantity. GDP targets are hit. Land and natural resources sit on their supply curves |
| `check_ssp.jl` | The SSP table covers every data base region from 2022 to 2100, indexes are 1 in 2022 (also after aggregation), a one-country region gets the same index aggregated as on its own, and a two-year SSP2 baseline hits its GDP targets with labour and population set to the indexes |
| `check_modules.jl` | Sticky wages: base re-solve with the module attached; in a static tariff shock, employment is fixed with flexible wages and the wage follows the sticky-wage rule with the module; the same baseline with the module on and off; a policy run with no shock reproduces the baseline; runs with mismatched options are refused |
| `check_stepped_period.jl` | A year solved in steps matches the same year solved in one go |
| `check_gtap_e.jl` | GTAP-E: base re-solve; switching it off reproduces standard GTAP; the world oil price rises less after an oil supply shock with GTAP-E than without; the output-level productivity shifter still acts |
| `check_industry_capital.jl` | Industry-specific capital: base re-solve; capital stays put and rentals differ by industry in a static shock; switching it off reproduces standard GTAP; industry stocks add up to the regional stock and roll forward over a two-year baseline; a policy run with no shock reproduces the baseline |

`setup.jl` holds the shared data reading, aggregation and calibration. `prepare_for_solve.jl` handles agents that buy a commodity only from domestic producers or only from imports, which the levels model cannot solve (log of zero). For each one it swaps a tiny amount (one millionth of the agent's purchases) with another agent in the same region, so totals and tax revenue are unchanged. It runs on the aggregated copy in memory, and the data base itself is not changed.
