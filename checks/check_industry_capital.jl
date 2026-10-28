# Checks of the industry-specific capital module (experimental). Mechanical
# tests, not results: the dynamic part uses a uniform 2.5% a year GDP target.
#   OCGE_DATA=<folder> julia --project=checks checks/check_industry_capital.jl
include(joinpath(@__DIR__, "setup.jl"))

cap = "capital"
pairs_of(r) = [a for a in string.(collect(mc.sets["acts"])) if isfinite(Float64(cal["qes"][cap, a, r])) && Float64(cal["qes"][cap, a, r]) > 0]
oil_shock!(m) = (m.data["qesf"]["natres", "oil", "gulf"] = 0.7 * Float64(cal["qesf"]["natres", "oil", "gulf"]))
static = ModelSpec()
static_ic = ModelSpec(IndustryCapital())
flex = run_static!(static, mc, cal; shock! = oil_shock!).states[0]

# 1. Base re-solve with the module attached.
mc.data = deepcopy(cal)
attach!(static_ic, mc)
_prepare!(static_ic, mc, :policy)
mc.data = deepcopy(cal); ensure_data!(IndustryCapital(), mc)
_try_solve!(mc; max_iter=200) || error("base re-solve failed")
check("1. base re-solve with industry capital", maxgap(mc.data, cal, CORE); tol=1e-9)

# 2. Static shock: capital stays in every industry, rentals differ by industry.
st = run_static!(static_ic, mc, cal; shock! = oil_shock!).states[0]
check("2. static shock: largest change in an industry's capital",
    maximum(abs(Float64(st["qes"][cap, a, r]) / Float64(cal["qes"][cap, a, r]) - 1) for r in regs for a in pairs_of(r)); tol=1e-9)
real_rental(d, a) = Float64(d["pes"][cap, a, "gulf"]) / Float64(d["ppriv"]["gulf"])
changes = [real_rental(st, a) / real_rental(cal, a) - 1 for a in pairs_of("gulf")]
check("2. Gulf industries earn different rentals (0 = yes)", maximum(changes) - minimum(changes) > 0.01 ? 0 : 1; tol=0)
for a in ("oil", "petro", "manuf", "svces")
    note("   Gulf real capital rental, ", a, ": ", pct(real_rental(st, a), real_rental(cal, a)), "%")
end

# 3. Switched off again: standard GTAP.
mc.data = deepcopy(cal)
check("3. module off again vs standard GTAP", maxgap(run_static!(static, mc, cal; shock! = oil_shock!).states[0], flex, CORE); tol=1e-9)

# 4. Dynamic: identities on a two-year baseline, and a policy run with no shock.
first_year, periods = BASE_YEAR, 2
target(r, y) = 1.025^(y - first_year)
spec = ModelSpec(GtapRD(), IndustryCapital())
mc.data = deepcopy(cal)
base = run_baseline!(spec, mc, cal; periods, base_year=first_year, gdp_target=target)
years = first_year+1:first_year+periods
check("4. baseline GDP target gap", maximum(abs(row.real_gdp_index / target(row.region, row.year) - 1) for row in base.rows); tol=0.003)
check("4. industry stocks sum to the regional stock",
    maximum(abs(sum(Float64(base.states[y]["ic_ke"][a, r]) for a in pairs_of(r)) / Float64(base.states[y]["ke"][r]) - 1) for y in years for r in regs); tol=1e-9)
check("4. next year's opening stock equals this year's closing stock",
    maximum(abs(Float64(base.states[y+1]["ic_kb"][a, r]) / Float64(base.states[y]["ic_ke"][a, r]) - 1) for y in first(years):last(years)-1 for r in regs for a in pairs_of(r)); tol=1e-9)
p0 = run_policy!(spec, mc, cal, base)
check("4. no-shock policy vs baseline", maximum(maxgap(p0.states[y], base.states[y], CORE) for y in years); tol=1e-6)
finish()
