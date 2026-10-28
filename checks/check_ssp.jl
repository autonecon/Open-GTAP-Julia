# Checks of the SSP driver table and its loader: coverage of the data base's
# regions, base-year indexes, aggregation, and a two-year SSP2 baseline.
#   OCGE_DATA=<folder> julia --project=checks checks/check_ssp.jl
include(joinpath(@__DIR__, "setup.jl"))
include(joinpath(REPO, "SSP", "ssp_indexes.jl"))

own = read_ssp_indexes(ssp="SSP2")
vars = ("population", "labour_force", "gdp_mer")
missing_series = [(r, v) for r in reg_codes, v in vars if !all(y -> haskey(own, (r, v, y)), BASE_YEAR:2100)]
check("1. data base regions without a full 2022-2100 series", length(missing_series); tol=0)
check("2. own regions: largest base-year index gap", maximum(abs(own[(r, v, BASE_YEAR)] - 1) for r in reg_codes, v in vars); tol=1e-12)

idx = read_ssp_indexes(ssp="SSP2", groups=regMap)
check("3. aggregated regions: largest base-year index gap", maximum(abs(idx[(r, v, BASE_YEAR)] - 1) for r in regs, v in vars); tol=1e-12)
check("3. China alone: aggregated equals own index", maximum(abs(idx[("chn", v, y)] - own[("chn", v, y)]) for v in vars, y in BASE_YEAR:2100); tol=1e-12)

labour = labour_endowments(mc)
apply, target = ssp_drivers(idx, cal, labour)
mc.data = deepcopy(cal)
base = run_baseline!(ModelSpec(GtapRD()), mc, cal; periods=2, base_year=BASE_YEAR, apply_shock=apply, gdp_target=target)
years = BASE_YEAR+1:BASE_YEAR+2
check("4. SSP2 baseline GDP target gap", maximum(abs(row.real_gdp_index / target(row.region, row.year) - 1) for row in base.rows if row.year in years); tol=0.003)
check("4. labour equals base times the labour-force index",
    maximum(abs(Float64(base.states[y]["qe"][e, r]) / (Float64(cal["qe"][e, r]) * idx[(r, "labour_force", y)]) - 1) for y in years, r in regs, e in labour); tol=1e-9)
check("4. population equals base times the population index",
    maximum(abs(Float64(base.states[y]["pop"][r]) / (Float64(cal["pop"][r]) * idx[(r, "population", y)]) - 1) for y in years, r in regs); tol=1e-9)
for r in regs
    note("   ", r, " labour force index 2024: ", round(idx[(r, "labour_force", 2024)], digits=4), ", gdp_mer: ", round(idx[(r, "gdp_mer", 2024)], digits=4))
end
finish()
