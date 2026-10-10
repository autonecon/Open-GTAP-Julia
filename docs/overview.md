# GlobalTradeAnalysisProjectModelV7 overview

This package (version 0.1.11) solves the Global Trade Analysis Project (GTAP) model, version 7, in levels. A JuMP model is handed to Ipopt. Data stay in dictionaries of `NamedArray`s whose keys follow the usual GTAP HAR headers, lowercased.

The path the README and `docs/src/index.md` walk through is the model container: `generate_initial_model`, `generate_calibration_inputs`, `run_model!`, `rebuild_model!`, then a second `run_model!` after an exogenous shock. A second, older builder, `solve_model`, is still exported and is what `calibrate` calls. The two builders are not the same equation system. The container path is the one described in the sections below; differences are called out where they matter and again under unfinished work.

There are no `TODO` or `FIXME` markers in the repository. Unfinished work shows up as an empty test, a stub variable block, commented-out equations, and an older solver kept next to the container API.

## What each file does

### Package root

| File | Role |
| --- | --- |
| `Project.toml` | Package metadata. Runtime dependencies are `JuMP`, `Ipopt`, `NamedArrays`, `JLD2`, and `ComputableGeneralEquilibriumHelpers` (`ces` and `cde`). `Documenter` and `DocumenterTools` are also main dependencies. Julia compatibility is 1.6.7. |
| `README.md` | Install notes and a full script: aggregate HAR data, or load the sample, build, calibrate, drop calibration equations, shock `tms`, then read export changes, equivalent variation, and real GDP. |
| `LICENSE` | MIT, copyright 2025 Maros Ivanic. |
| `.gitignore` | Ignores `Manifest.toml`, `docs/build/`, and `other/*`. The two scripts under `other/` are already tracked, so the ignore rule does not drop them. |
| `test/runtests.jl` | Empty test set. The body is the generated comment `# Write your tests here.` |
| `other/roberto_test.jl` | Manual script for a GTAP 11 aggregation (Oceania, China, USA, EU, MENA, SSA, and others). It calls `aggregate_data_legacy`, calibrates, rebuilds, and sets the grains-and-crops tariff from MENA into the EU to 2. The HAR files are not in the repo. |
| `other/test2.jl` | Scratch session: local HAR paths, ad hoc aggregation, trade and intermediate cutoffs, repeated `run_model!` calls, and a pasted numerical residual. Not a supported entry point. |

### `src/` — public model

| File | Role |
| --- | --- |
| `src/GlobalTradeAnalysisProjectModelV7.jl` | Module entry. Declares `model_container_struct` and `include`s every other source file. Exports the container API, both aggregators, `solve_model`, `calibrate`, and the welfare helpers. |
| `src/get_sample_data.jl` | Loads `src/assets/example.jld2` and returns `(hData, hParameters, hSets)`. |
| `src/assets/example.jld2` | Pre-aggregated slice of the free GTAP 9 database (JLD2 written by Julia 1.11). Commodity labels include `crops`, `animals`, `extract`, `processed food`, `manuf`, and `svces`. Endowment labels include `land`, `skilled labor`, `unskilled labor`, `capital`, and `other`. Region labels include `oceania`, `americas`, `other europe`, `mena`, and `sub-saharan africa`. The published examples also index `eu`. |
| `src/aggregate_data.jl` | Sums GTAP flows across user maps and value-weights the elasticities. Region-specific parameters stay region-specific. |
| `src/aggregate_data_legacy.jl` | Same aggregator, with the GTAPAgg2 / FlexAgg behavior for `esbv`, `esbd`, and `esbm`: those three are weighted with a global (region-collapsed) weight and then repeated across regions. |
| `src/generate_initial_model.jl` | Builds a `model_container_struct`: starting values, an Ipopt model, variables, equations, bounds, and the default closure. |
| `src/generate_starting_values.jl` | Runs the `prepare_*` helpers, then fills `fixed`, `lower`, and `upper`. |
| `src/build_model!.jl` | Declares JuMP variables and log-level equations on `mc.model`, drops structurally zero flows, and branches on `rordelta`. |
| `src/rebuild_model!.jl` | Replaces `mc.model` and calls `build_model!`. Default `calibration=false` omits the share-targeting equations used only while calibrating. |
| `src/initialize_model!.jl` | Writes `mc.data` into solver starts, applies bounds, and fixes every exogenous cell. |
| `src/solve_model!.jl` | Sets Ipopt `max_iter`, `constr_viol_tol`, and `bound_push`, calls `optimize!`, and throws if the solution is not feasible. |
| `src/extract_model!.jl` | Copies solved variable levels back into `mc.data`. Cells whose variables were deleted become `NaN`. |
| `src/run_model!.jl` | `initialize_model!`, then `solve_model!`, then `extract_model!`. |
| `src/generate_calibration_inputs.jl` | Returns a calibration closure and a data dict whose share targets come from a saved database snapshot. |
| `src/calibrate.jl` | Older one-shot calibration. It mutates a closure and calls `solve_model` (the legacy builder), not `run_model!`. |
| `src/solve_model.jl` | Legacy builder and solver in one function. It can reuse a JuMP model passed as `model`. `calibrate` is its only in-repo caller. |
| `src/calculate_expenditure.jl` | Small Ipopt model: income required to afford post-shock utility at pre-shock prices. Equivalent variation in the README is this income minus baseline `y`. |
| `src/calculate_ev.jl` | Deprecated wrapper. Prints a notice and calls `calculate_expenditure`. |
| `src/calculate_gdp.jl` | Real GDP at base prices: private and government and investment absorption, plus FOB exports, minus CIF imports, plus margin sales. |

### `src/helpers/` — not exported

These are internal. Users reach them through `generate_starting_values`.

| File | Role |
| --- | --- |
| `helpers/agg.jl` | Sums a `NamedArray` onto a coarser set of labels. |
| `helpers/aggComb.jl` | Weighted average onto coarser labels. The weight array supplies the weights; the unused local `wgt` is never filled. |
| `helpers/prepare_sets.jl` | Copies `reg`, `comm`, `marg`, `acts`, `endw`. Adds `endwc = ["capital"]` and splits endowments into sluggish (`endws`), mobile (`endwm`), mobile-or-sluggish (`endwms`), and fixed (`endwf`) using `eflg`. |
| `helpers/prepare_parameters.jl` | Renames HAR headers to model names (`esbt` → `esubt`, `rdlt` → `rordelta`, and so on). |
| `helpers/prepare_initial_values.jl` | Regional income from factor payments, depreciation, and indirect taxes. Most prices start at 1. Utility starts as income per capita. Value shares are computed from the HAR flows. |
| `helpers/prepare_taxes.jl` | Tax instruments are powers (purchaser value / basic value, or the analogous trade and make ratios). |
| `helpers/prepare_quantities.jl` | Quantities are values divided by the current prices. With prices at 1, quantities start equal to the dollar flows. Also stores the HAR value arrays on the data dict. |
| `helpers/prepare_initial_calibrated_parameters.jl` | Inverts CES (and CET) nests for share parameters `α` and scale parameters `γ`. Solves a one-region Ipopt problem for each region to get CDE preference parameters `β_qpa` and private utility `up`. |

### Docs and CI

| File | Role |
| --- | --- |
| `docs/make.jl` | Documenter build. Pages are `docs/src/index.md`, `functions.md` (autodocs of functions), and `types.md` (autodocs of types; the page heading still says "Functions"). Deploys to `gh-pages`. |
| `docs/src/index.md` | Same workflow as the README, plus an example that adds a constant-elasticity land-supply equation to the live JuMP model. |
| `docs/Project.toml` | Docs environment: `Documenter` only. `docs/Manifest.toml` is the resolved docs manifest. |
| `.github/workflows/CI.yml` | Julia 1.9, 1.10, 1.11, and `pre` on Ubuntu. The job runs `test/runtests.jl`, which does not execute the model. |
| `.github/workflows/Documentation.yml` | Builds docs with Julia 1.9.3. |
| `.github/workflows/TagBot.yml` | Julia registry tagging. |
| `.github/workflows/CompatHelper.yml` | Compat bounds. |
| `.github/dependabot.yml` | Weekly GitHub Actions updates. |

`HeaderArrayFile` is not a dependency. It is how a user turns GTAP HAR files into Julia dictionaries before calling this package.

## How data is loaded

GTAP input is three dictionaries.

- `hData` — dollar flows and population. Headers used by the aggregators and the initializers:

  | Header | Contents |
  | --- | --- |
  | `vdpb`, `vdpp`, `vmpb`, `vmpp` | Private domestic and imported consumption, basic and purchaser prices |
  | `vdgb`, `vdgp`, `vmgb`, `vmgp` | Government, same split |
  | `vdib`, `vdip`, `vmib`, `vmip` | Investment (gross capital formation), same split |
  | `vdfb`, `vdfp`, `vmfb`, `vmfp` | Firm intermediate use, domestic and imported |
  | `evfb`, `evfp`, `evos` | Endowment use at firm (basic and tax-inclusive) and endowment supply |
  | `maks`, `makb` | Make matrix at supplier and basic prices |
  | `vxsb`, `vfob`, `vcif`, `vmsb` | Bilateral exports at basic and FOB prices; imports at CIF and tariff-inclusive market prices |
  | `vtwr`, `vst` | International margin use by margin, commodity, source, destination; margin supply |
  | `save`, `vdep`, `vkb`, `pop` | Savings, depreciation, capital stock, population |

- `hParameters` — elasticities and flags: `esbt`, `esbc`, `esbv`, `esbd`, `esbm`, `esbq`, `esbg`, `esbs`, `etrq`, `etre`, `subp`, `incp`, `rflx`, `eflg`, `rdlt`.
- `hSets` — at least `reg`, `comm`, `marg`, `acts`, `endw`. After aggregation, `acts` is a copy of the aggregated commodity list.

Two ways to obtain that triple:

1. `get_sample_data()` reads the bundled JLD2. No HAR files and no network call.
2. User code reads HAR files (the README uses `HeaderArrayFile`) and optionally aggregates.

`aggregate_data(; hData, hParameters, hSets, comMap, regMap, endMap)` expects each map to be a `NamedArray` of new labels, indexed by the disaggregated set. Flows are summed with `agg`. Elasticities are value-weighted with `aggComb` (factor payments for `esbv`, cost for `esbt`, make-matrix values for `etrq` and `esbq`, Armington trade for `esbd` and `esbm`, and so on). `rdlt` is copied unchanged. `eflg` is summed on the endowment map against a fixed three-way map `mobile` / `sluggish` / `fixed`, then each row is divided by its maximum and negative entries are set to 0. Margin commodities are the commodity-map entries whose original names sit in `hSets["marg"]`.

`aggregate_data_legacy` is the same function except the weights for `esbv`, `esbd`, and `esbm` are collapsed across regions and broadcast back, matching an aggregation bug in GTAPAgg2 and FlexAgg.

The README’s cleaning step is outside the package: zero bilateral trade headers where `vxsb` is at most `1e-4`, and zero the matching margin slices. `other/test2.jl` uses `1e-6` and also drops tiny intermediate shares. Neither cutoff is applied inside `generate_initial_model`.

## How the model is built

`generate_initial_model` does four things.

### 1. Starting values

`prepare_sets` classifies endowments. Capital is always the string `"capital"` (`endwc`). An endowment is sluggish, mobile, or fixed when the corresponding column of normalized `eflg` equals 1.

`prepare_parameters` keeps elasticities as data, not as JuMP variables:

| HAR | Model name | Used for |
| --- | --- | --- |
| `esbt` | `esubt` | Top nest, value added versus intermediates |
| `esbc` | `esubc` | Intermediate bundle across commodities |
| `esbv` | `esubva` | Primary-factor bundle |
| `esbd` | `esubd` | Armington domestic-versus-import split (firms, households, government, investment) |
| `esbm` | `esubm` | Import sourcing across regions |
| `etrq` | `etraq` | Transformation of activity output across commodities |
| `esbq` | `esubq` | Make / commodity supply. A zero switches that market to a fixed-price rule |
| `esbs` | `esubs` | Sourcing of margin services across regions |
| `etre` | `etrae` | Transformation of sluggish endowments across activities |
| `subp`, `incp` | `subpar`, `incpar` | CDE private demand |
| `rflx` | `rorflex` | Elasticity of the expected rate of return to the capital stock |
| `rdlt` | `rordelta` | Scalar switch for investment allocation |
| `eflg` | `endowflag` | Already consumed while building sets |
| `esbg` | `esubg` | Used only while inverting the government nest for initial `α_qga` and `γ_qga`. The live government equation does not read it |

`prepare_taxes` sets powers. Generic export and import powers `tx` and `tm` are identically 1; the bilateral powers `txs = vfob/vxsb` and `tms = vmsb/vcif` carry the whole wedge. Other powers are purchaser/basic ratios (`tfd`, `tfm`, `tpd`, `tpm`, `tgd`, `tgm`, `tid`, `tim`), `to = makb/maks`, `tfe = evfp/evfb`, and `tinc = evfb/evos`. Zero or missing denominators become 1.

`prepare_quantities` sets `q = v/p` for each nest. Capital stock `kb = vkb/pinv` and end-of-period capital `ke = (vkb - vdep)/pinv + qinv`. Depreciation rate `δ = vdep/vkb` is computed later, with the CES parameters.

`prepare_initial_calibrated_parameters` recovers CES share and scale parameters from those quantities, prices, and elasticities. Special cases inside `ces_parameters`: elasticity 1 uses value shares; elasticity 0 uses quantity shares (Leontief). Investment composition is forced to elasticity 0. Private demand is CDE: for each region a tiny Ipopt model solves `β_qpa` and `up` with utility level fixed at 100, population and prices and quantities fixed at the initial guess. Income shares are `σyp = yp/y`, `σyg = yg/y`, `σsave = 1 - σyp - σyg`. The sum-to-one helpers `ϵ_*` start at 1. `ρ` starts as capital endowment supply over `vkb`. `α_qinv` starts as the regional share of global investment expenditure.

### 2. Container and closure

```julia
mutable struct model_container_struct
    model       # JuMP model with Ipopt
    data        # variables and initial levels
    parameters  # elasticities
    sets
    fixed       # true => exogenous
    lower
    upper
end
```

The default closure fixes taxes and tax powers, population, aggregate endowments `qe`, fixed-factor activity supplies `qesf`, every `α` and `γ`, income shares `σyp` and `σyg`, CDE parameters `β_qpa`, depreciation `δ`, and `ρ`. The world factor price `pfactwld` is endogenous. All purchaser prices `ppa` are endogenous except the numeraire `ppa[comm[1], reg[1]]`. Everything not listed (quantities, other prices, incomes, trade, investment, rates of return, Walras slacks) is endogenous.

Bounds live in `mc.lower` and `mc.upper` and are applied later by `initialize_model!`. They are not written on the JuMP variables inside `build_model!`.

### 3. Equations

`build_model!` adds variables with no bounds, deletes structurally absent index combinations, then adds constraints. A flow is absent when the matching share parameter is `NaN` or 0 (`α_qfe`, `α_qca`, `α_qtmfsd`, `α_qxs`, `α_qga`, `α_qia`, `α_qfa`, and `γ_qca` for a whole activity). Deleted variables stay `NaN` in the results, so a shock cannot open a flow that was zero in the base data.

With `calibration=true` (the `generate_initial_model` default) the model also contains value and share variables used only to hit database targets: `vdpp`, the `ϵ_*` sum-to-one residuals, `σsave`, and the `σ_v*` / `σ_q*` shares. `rebuild_model!` drops that block.

Equations are written in logs. `ces` and `cde` come from `ComputableGeneralEquilibriumHelpers`. Index guards on the constraints skip the same zero cells that were deleted.

Production, in each active activity and region:

- Top nest: CES of intermediate composite `qint` and value added `qva` into output `qo` (`esubt`). Zero-profit equates `po*qo` to the cost of the two bundles.
- Intermediates: CES across commodities (`esubc`), then an Armington CES of domestic `qfd` and imported `qfm` (`esubd`).
- Value added: CES across the endowments that are actually used (`esubva`).
- Sales: CET of `qo` across commodities (`etraq`). If `esubq == 0`, the activity’s basic price equals the commodity price `pds`; otherwise a CES make nest assembles `qc` from activity supplies. `pca = ps * to`.

Factors:

- Activity demand equals activity supply: `qfe = qes`.
- `pfe = peb * tfe` and `peb = pes * tinc`.
- Mobile endowments have one regional price `pe` and `qe` equal to the sum of activity demands.
- Sluggish endowments are allocated across activities by a CET (`etrae`, `α_qes2`, `γ_qes2`).
- Fixed endowments are stuck at the exogenous `qesf`.
- `pfactor` is the regional unit value of factor demand. `pfactwld` is the same average over all regions.

Income and demand:

- Factor income `fincome` is basic endowment earnings minus `δ * pinv * kb`.
- Regional income `y` adds wedges from every tax power (private, government, investment, firms, output, factor use, export, import).
- Utility price `p` is the income-share weighted average of `ppriv`, `pgov`, and `psave`. Utility per person is `u = y / (p * pop)`.
- Private income `yp = y * σyp * uelas / uepriv`. Commodity demands are CDE in per-capita form. `uepriv` and `uelas` are the usual GTAP CDE aggregates (utility elasticity of private expenditure, and the top-level elasticity).
- Each private, government, and investment commodity is an Armington CES (`esubd`).
- Government income `yg = y * σyg * uelas`. Government spends by fixed value shares `α_qga` (Cobb–Douglas). The scale `γ_qga` is not in that equation.
- Saving is the residual of the top income identity: `y*uelas = σyp*y*uelas + σyg*y*uelas + psave*qsave`.
- Investment commodities are Leontief (the elasticity argument is the literal `0`).

Trade:

- Import composite `qms` is the sum of firm, private, government, and investment import demands.
- Bilateral imports `qxs` are a CES across sources (`esubm`).
- Margin use on a route is Leontief in the bilateral flow: `qtmfsd = α_qtmfsd * qxs`.
- `pfob = pds * tx * txs`. CIF value is FOB value plus margin cost. The domestic user price is `pmds = pcif * tm * tms`.
- Domestic sales `qds` clear against intermediate, private, government, and investment domestic use. Commodity output `qc` covers domestic sales, exports, and, for margin commodities, margin supply `qst`.
- World margin demand is sourced across regions by a CES (`esubs`).

Investment and capital:

- `kb` is tied to the capital endowment by `ρ * kb = sum(qe["capital"])`. The price-inclusive form of this identity is commented out.
- `ke = qinv + (1-δ)*kb`.
- `rental` is the average supply price of capital. `rorc` converts that into a net rate using depreciation. `rore` bends `rorc` by `(ke/kb)^rorflex`.
- `pcgdswld` is the value-weighted price of net investment. `walras_sup = pcgdswld * globalcgds` and `walras_dem = sum(psave*qsave)` are reported and are not forced equal to each other.
- The savings price that is actually compiled is

  ```julia
  log(psave[r]) == log(pinv[r]) + sum(((qinv .- δ .* kb) .- qsave) .* log.(pinv) ./ sum(qinv .- δ .* kb))
  ```

  The previous form of this equation is commented immediately above it. See unfinished work.

`rordelta` changes the investment closure:

- `rordelta == 1`: expected regional rates `rore` are equalized to the world rate `rorg`, and `globalcgds` is the sum of net investment. The variable block attached to this branch is empty.
- Otherwise: net investment follows fixed shares, `qinv = α_qinv * globalcgds + δ*kb`, and `rorg` is the net-investment-weighted average of `rore`.

Calibration-only equations (present until `rebuild_model!`):

- `vdpp = ppd*qpd`.
- Each `α` vector sums to its `ϵ` (the `ϵ`s are fixed at 1 during calibration, so shares sum to 1).
- `σsave + σyp + σyg = 1`.
- Share definitions such as `σ_vdp = domestic private value / total private value`, and the analogous shares for government, investment, firms, factors, margins, import sources, savings, and capital.

### 4. Initialization

`initialize_model!` sets every free variable’s start to `1.01`, overwrites starts with `mc.data` where the name matches, unfixes everything, applies `mc.lower` and `mc.upper`, then `fix`es each exogenous cell at its data value. A fixed cell whose data is `NaN` is fixed at `0`.

## How the model is solved

`run_model!` is the only supported solve step.

1. `initialize_model!` reloads starts, bounds, and the closure from the container. Editing `mc.data` or `mc.fixed` is enough; the JuMP model is not rebuilt.
2. `solve_model!` sets three Ipopt attributes and calls `optimize!`. Defaults are `max_iter=50`, `constr_viol_tol=1e-8`, `bound_push=1e-15`. On failure it `throw`s the string `"Not solved!"`.
3. `extract_model!` writes every solved level back onto `mc.data`. Parameters are left as they were. Deleted index positions are `NaN`.

`solve_model` is a separate function. It builds its own JuMP model unless one is passed in, puts bounds on the variables at declaration, solves, and returns a named tuple `(sets, data, parameters, constraints, free_variables, all_variables, model)`. It does not check solver status. Its equation list matches an earlier draft: utility is a Cobb–Douglas nest of `up`, `ug`, and `us`; there is no rate-of-return block; structural zeros are `value > 1e-6` rather than “share is NaN or zero”; and the savings-price equation is the commented form from `build_model!`.

## How a shock is run

The intended sequence, as in the README and `docs/src/index.md`:

1. Load `(hData, hParameters, hSets)` from HAR files plus `aggregate_data`, or from `get_sample_data()`.
2. `mc = generate_initial_model(...)`. Copy `mc.data` to `start_data` and `mc.fixed` to `fixed_default`. `start_data` still holds the database value flows (`vdpp`, `evfp`, `vcif`, …) that calibration targets.
3. `generate_calibration_inputs(mc, start_data)` returns `fixed_calibration` and `data_calibration`. Assign both onto `mc` and call `run_model!`. The calibration closure frees the distribution parameters (`α_qxs`, `α_qfe`, `α_qfa`, `β_qpa`, `α_qga`, `α_qia`, `α_qtmfsd`, `α_qinv`, `ρ`, and the Armington `α`s) and fixes the observed shares instead. One share in each nest is left free so that “shares sum to one” is not over-determined: the first positive import source, the `capital` factor share, the first commodity in the other nests, and the first region’s investment share. `up` is fixed. `vdpp` is set to the database and only `vdpp[1,1]` is exogenous, which pins the price level while `ppa` is freed. Taxes, endowments, and population stay at their database values.
4. Copy the solved `mc.data` to `calibrated_data`. Restore `mc.fixed = fixed_default` so the calibrated shares and scales are exogenous again.
5. `rebuild_model!(mc)` builds a new Ipopt model without the share equations. The next `run_model!` re-initializes it.
6. Apply the shock by writing a new exogenous level into `mc.data`. The tariff example is a power, not a rate:

   ```julia
   mc.data["tms"]["crops", "mena", "eu"] = 1.2   # 20% higher power
   run_model!(mc)
   ```

   Any name in `mc.fixed` can be shocked the same way (`pop`, `qe`, `txs`, `esub*` is not a variable — elasticities are parameters and are not shocked through `mc.data`). Swapping a cell of `mc.fixed` from `true` to `false` changes the closure; a new variable added with `@variables` / `@constraints` on `mc.model`, as in the land-supply example in `docs/src/index.md`, is picked up by the next `initialize_model!` if `mc.data`, `mc.fixed`, and the bound dicts have matching keys.
7. Results are percent changes against `calibrated_data`, for example `mc.data["qxs"] ./ calibrated_data["qxs"] .- 1`. Welfare and real GDP are separate functions, evaluated at base prices:

   ```julia
   ev = calculate_expenditure(sets=mc.sets, data0=calibrated_data, data1=mc.data,
                              parameters=mc.parameters) .- calibrated_data["y"]
   qgdp = calculate_gdp(sets=mc.sets, data0=calibrated_data, data1=mc.data) ./
          calculate_gdp(sets=mc.sets, data0=calibrated_data, data1=calibrated_data)
   ```

`calculate_expenditure` builds a household-only model, fixes prices `ppa`, `pga`, and `psave` at the baseline, fixes utility, income shares, CDE parameters, government shares, and population at the simulation, and solves for income `y`. It uses looser defaults (`constr_viol_tol=1e-5`) and does not check solver status.

A shock on a bilateral link, margin, or activity input that was deleted as a structural zero does nothing: that variable is no longer in the model.

## Unfinished work, stubs, commented equations, hard-coded values

### No TODO markers, and the test suite is a stub

`grep` finds no `TODO`, `FIXME`, `XXX`, or `HACK`. `test/runtests.jl` contains only `# Write your tests here.` CI still runs that file, so a green build does not mean the model solves.

`build_model!` has an empty variable block that is the entire `rordelta == 1` extension:

```julia
if rordelta==1
    @variables(mc.model,
    begin
    end
    )
end
```

The rate-of-return equations themselves sit elsewhere. This branch adds nothing.

`calculate_ev` is a deprecated forwarder to `calculate_expenditure`.

### Two model builders

`solve_model` / `calibrate` implement an older system (Cobb–Douglas top utility with per-capita saving utility `us`, no `rore` / `rorc` / `rental` / `pfactwld`, value-flow identities for every HAR header, zeros dropped at `1e-6`). The README never calls them. Behavior of `calibrate` will not match `generate_calibration_inputs` plus `run_model!`.

`endowflag` is unpacked in `solve_model` and unused. `esubg` is unpacked in `build_model!` and unused. Government expenditure is the Cobb–Douglas share equation even though `prepare_initial_calibrated_parameters` inverts a CES with `esubg` and stores `γ_qga`.

### Commented-out equations

These are the equation lines left commented in the current builder. The line above each of them is the equation that is compiled today.

| Where | Commented equation | What runs instead |
| --- | --- | --- |
| `build_model!.jl` savings price | `log(psave[r]) == log(pinv[r] + sum(((qinv - δ*kb) - qsave) .* pinv / sum(qinv - δ*kb)))` | `log(psave[r]) == log(pinv[r]) + sum(((qinv - δ*kb) - qsave) .* log(pinv) / sum(qinv - δ*kb))`. The legacy `solve_model` still uses the commented form. |
| `build_model!.jl` inside `rordelta == 1` | Price-based `e_rorc`: net capital payments minus `δ*pinv*kb`, times `rorc`, equal capital payments times `rental/pinv` | The unconditional quantity form above it: `rorc * (sum(qes_capital) - δ*kb) = sum(qes_capital) * rental/pinv` |
| `solve_model.jl` capital stock | `log(ρ*pinv*kb) == log(sum(qe_capital .* pe_capital))` | `log(ρ*kb) == log(sum(qe_capital))`, also what `build_model!` uses |
| `solve_model.jl` | `log(psave) == log(pinv)` | Replaced by the sum form above |
| `calculate_expenditure.jl` | `u = up^σyp * ug^σyg * us^(1-σyp-σyg)` and `us = qsave/pop` | `log(u) = log(y / (p * pop))`, matching `build_model!`. The `us` variable declaration is commented out |
| `prepare_initial_values.jl` | `us = save/pop` and the Cobb–Douglas `u` | `u = y/pop` as the initial guess |
| `prepare_quantities.jl` | Recomputation of `yp`, `yg`, `fincome`, `y`, and `qe` from the quantity side | The values computed in `prepare_initial_values` are kept |

`build_model!` also comments out `delete` calls for value variables (`evos`, `evfp`, `vcif`, `vfob`, `vtwr`, `maks`, `vdgp`, `vmgp`, `vdip`, `vmip`, `vdfp`, `vmfp`). Those variables are no longer declared on the container model (only `vdpp`, and only while calibrating), so the deletes would not refer to anything. Matching `printstyled` diagnostics above them are commented out too.

In `prepare_initial_calibrated_parameters.jl` a commented check calls `demand_ces`, which this package does not define, and a commented `save_object("output.jld2", ...)` would dump a failed CDE calibration. Alternative formulas for `α_qinv` (net investment shares, and savings shares) are commented; the live formula is the share of `vdip+vmip`.

### Hard-coded values

Structural and closure choices:

- Capital is the endowment named `"capital"`. Renaming it in `endMap` leaves `endwc` pointing at a missing set element.
- The numeraire is `ppa` of the first commodity in the first region. During calibration the pinned cell is `vdpp[1,1]` instead, and the freed share in each nest is the first index (or `"capital"` for factor shares).
- `tx` and `tm` are filled with ones.
- Investment composition elasticity is the literal `0` in `e_qia` and in `prepare_initial_calibrated_parameters` (`esubg .* 0`).
- `rordelta == 1` is the only switch value with its own equations.
- Initial prices, `pcgdswld`, `pfactwld`, `rorg`, `rore`, `rorc`, and `rental` are 1. Initial `up` is 100. The per-region CDE solve fixes utility at 100 and starts `β` and utility at 0.1.
- Free-variable starts are overwritten with `1.01` before data starts are applied. A fixed `NaN` is fixed at `0`.
- Placeholder shares before the real ratios are filled: `σsave` and `σ_qinv` at `0.05`, `σ_vtwr` at `0.01`, `σ_vif` at `0.5`, `σ_ρ` at `0.01`. `uelas` and `uepriv` start at 1.
- Zero-flow cutoff in `solve_model` is `1e-6`. The README’s trade screen is `1e-4`. `other/test2.jl` uses `1e-6` for trade and for intermediate cost shares.

Bounds in `generate_starting_values` (applied on the container path):

| Group | Lower | Upper |
| --- | --- | --- |
| Quantities (`q*`, `pop`, `kb`, `ke`, `globalcgds`, Walras slacks, rates of return) | `1e-8` | `1e12` |
| `qsave` | `-1e12` | `1e12` |
| Prices, including `p`, `pfactwld`, and also `pop` and the rate-of-return names again | `1e-8` | `1e8` |
| Tax powers | `1e-8` | `1e2` |
| Share parameters `α_*` | `1e-8` | `1` |
| Scales `γ_*` and sum-to-one `ϵ_*` | `1e-8` | no upper bound stored |
| Income-share and value-share `σ_*` except `σ_qinv` | `0` | no upper bound stored |
| `σ_qinv`, `σsave` | `-1` | `1` |
| `uelas`, `uepriv` | `0` | `10` |
| `δ`, `ρ` | `0` | `1` |
| Incomes | `1e-8` | `1e12` |
| Value levels | `1e-12` | no upper bound stored |
| `β_qpa` | `1e-8` | no upper bound stored |

`solve_model` declares its own bounds and they differ: prices `1e-8` to `1e8`, quantities `1e-8` to `1e12`, tax powers `-1e2` to `1e2`, `α_qinv` from `-1` to `1`, `globalcgds` at least `1`. `calculate_expenditure` uses quantity floor `1e-9` and pins `p` and `ppriv` between `1e-2` and `1e2`.

Ipopt defaults are `max_iter=50` (`100` in `calibrate`), `constr_viol_tol=1e-8` (`1e-5` in the expenditure model), `bound_push=1e-15`.

### Other leftover inconsistencies

- `aggregate_data` and `aggregate_data_legacy` both build `esbc` from the `esbt` header. The weight array for that line is named with `esbv`’s names. The region-specific weighting expressions are commented beside the legacy global-weight expressions, and the other way around in the legacy file.
- In `generate_calibration_inputs` and `calibrate`, the `σ_vi` repeat uses `size(start_data["vmgp"])` where the neighboring lines use `vmip`. Both arrays are indexed by commodity, so the length matches, but the header is a copy from the government block.
- `prepare_quantities` writes `:qes => qfe` and then `:qes => qes` in the same dictionary, so the first entry is discarded. `prepare_initial_values` assigns `pga` twice.
- `aggComb` allocates `wgt` and never uses it. A zero weight in a bin divides by zero.
- `pop`, `rorg`, `rore`, `rorc`, and `rental` are listed in both the quantity-bound dict and the price-bound dict. `merge` keeps the price bounds.
- Several docstrings have typos that the autodocs will publish: “Retruns”, “Exttract values”, `hParamters`, `rebuild_model` without the bang, and an example fenced as `` `julia `` rather than a Julia fence. The README aggregation blurb names the module `GTAPvGlobalTradeAnalysisProjectModelV77` and binds `parameter` while the call uses `parameters`.
- `docs/src/types.md` is titled “Functions”.
- `other/test2.jl` points at `../GtapInJump/Replication/Data/*.har` and embeds a fully expanded numeric residual (`1.2499998807907104` and similar). `other/roberto_test.jl` documents that its HAR inputs are not provided.
