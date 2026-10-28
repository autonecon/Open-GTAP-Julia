# SSP drivers for the OCGE Data Base

`ocge_region_indexes.csv` gives population, labour force, working-age population and GDP (at market exchange rates) paths from 2017 to 2100 for the 167 regions of the [OCGE Data Base](https://github.com/autonecon/OCGE---The-Open-CGE-Database), under each of the five Shared Socioeconomic Pathways (SSP1 to SSP5). `ssp_indexes.jl` reads the table and turns it into drivers for a GTAP-RD baseline. You do not have to use it: a baseline runs with any drivers you set in `apply_shock`.

## Use

```julia
include("GTAP-modules/GTAPModules.jl")
include("SSP/ssp_indexes.jl")

idx = read_ssp_indexes(ssp="SSP2")                  # the data base's own 167 regions
idx = read_ssp_indexes(ssp="SSP2", groups=regMap)   # regions aggregated with aggregate_data's regMap
apply, target = ssp_drivers(idx, cal, labour_endowments(mc))
run = run_baseline!(ModelSpec(GtapRD()), mc, cal; periods=5, base_year=2022, apply_shock=apply, gdp_target=target)
```

Each year `apply` sets every region's population to its base value times the population index, and every labour endowment to its base value times the labour-force index. `target` gives the real GDP index (from `gdp_mer`) that labour efficiency must hit. For an aggregated region the index is the sum of its members' levels divided by that sum in 2022.

## The table

Columns: `ssp, region, variable, year, index_2022, level`. `index_2022` is 1 in 2022. `level` is in the source's units: persons for population, labour force and working age; US dollars at 2022 market exchange rates for `gdp_mer`.

| Variable | History (to about 2023) | Projection |
| --- | --- | --- |
| `population` | World Bank WDI (`SP.POP.TOTL`) | IIASA-WiC POP 2025 |
| `gdp_mer` | World Bank WDI growth of GDP at PPP, scaled to 2022 GDP at market exchange rates (UN National Accounts Main Aggregates) | OECD ENV-Growth 2025 growth of GDP at PPP, same scaling |
| `labour_force` | World Bank WDI (`SL.TLF.TOTL.IN`, ILO modelled estimates) | grows with the SSP working-age (15–64) population after the last observed year, as GTAP-RD does |
| `working_age` | World Bank WDI (ages 15–64) | IIASA-WiC POP 2025 working age (15–64); 2015 and 2020 from the IIASA-WiC POP 2023 Historical Reference |

Rules for countries with missing series:

- A region adds only countries with a level in every year, so it never gains or loses a member along the path.
- A country with no projection follows its region's other members.
- 32 small territories that the IIASA-WiC releases do not cover take their working-age growth from the older SSP population release distributed with the GTAP-RD aggregation tool.

`notes.txt` lists every fill.

## Sources and licences

The table is derived from these sources: levels are spliced, filled, rescaled or added up, and the source series themselves are not redistributed here. GDP at PPP is left out for that reason. Please cite them when you use it:

- KC, S. (2026), *SSP Population and Human-Capital Projections, 2025-Rebased, 2025–2100* (zen2025V01), Zenodo, doi:10.5281/zenodo.21738149. CC BY 4.0.
- KC, S. et al. (2024), *Updating the Shared Socioeconomic Pathways (SSPs) Global Population and Human Capital Projections*, IIASA Working Paper WP-24-003. Data from the IIASA SSP Scenario Database, used under the IIASA licence.
- OECD ENV-Growth 2025 SSP GDP projections, from the IIASA SSP Scenario Database. Method: Dellink, R., Chateau, J., Lanzi, E. and Magné, B. (2017), Long-term economic growth projections in the Shared Socioeconomic Pathways, *Global Environmental Change* 42, 200–214.
- KC, S. and Lutz, W. (2017), The human core of the shared socioeconomic pathways: Population scenarios by age, sex and level of education for all countries to 2100, *Global Environmental Change* 42, 181–192.
- Riahi, K. et al. (2017), The Shared Socioeconomic Pathways and their energy, land use, and greenhouse gas emissions implications: An overview, *Global Environmental Change* 42, 153–168.
- World Bank, World Development Indicators. CC BY 4.0.
- United Nations Statistics Division, National Accounts Main Aggregates Database, under the UNdata terms of use.

## Checks

`checks/check_ssp.jl` checks that every data base region has a full 2022–2100 series, that indexes are 1 in 2022 (also after aggregation), that a one-country region gets the same index aggregated as on its own, and that a two-year SSP2 baseline hits its GDP targets and sets labour and population to the indexes.
