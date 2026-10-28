# Checks of the module system and the sticky-wage module.
#   OCGE_DATA=<folder> julia --project=checks checks/check_modules.jl
include(joinpath(@__DIR__, "setup.jl"))

static = ModelSpec()
rd = ModelSpec(GtapRD())
sw = ModelSpec(GtapRD(), StickyWages())
static_sw = ModelSpec(StickyWages())

# 1. Attaching sticky wages leaves the base solution unchanged.
attach!(sw, mc)
mc.data = deepcopy(cal)
_prepare!(sw, mc, :baseline)
_try_solve!(mc; max_iter=200) || error("base re-solve failed")
check("1. base re-solve with sticky wages attached", maxgap(mc.data, cal, CORE); tol=1e-9)

# 2. Static 20-point US-China tariff: with sticky wages the real wage moves by
# alpha times the employment change (first-year rule), with flexible wages employment is fixed.
labour = labour_endowments(mc)
comm = string.(collect(mc.sets["comm"]))
function tariffs!(m)
    for c in comm, (s, d) in (("chn", "usa"), ("usa", "chn"))
        v = cal["tms"][c, s, d]
        (v isa Number && isfinite(v)) && (m.data["tms"][c, s, d] = Float64(v) + 0.20)
    end
end
flex = run_static!(static, mc, cal; shock! = tariffs!).states[0]
sticky = run_static!(static_sw, mc, cal; shock! = tariffs!).states[0]
w(d, e, r) = Float64(d["pe"][e, r]) / Float64(d["ppriv"][r])
emp(d, e, r) = Float64(d["qe"][e, r]) / Float64(cal["qe"][e, r]) - 1
check("2. flexible wages: largest employment change", maximum(abs(emp(flex, e, r)) for e in labour, r in regs); tol=1e-9)
check("2. sticky wages: wage change minus alpha x employment change",
    maximum(abs((w(sticky, e, r) / w(cal, e, r) - 1) - 0.5 * emp(sticky, e, r)) for e in labour, r in regs); tol=1e-6)
check("2. sticky wages: employment moves (0 = yes)", maximum(abs(emp(sticky, e, r)) for e in labour, r in regs) > 1e-4 ? 0 : 1; tol=0)
for r in ("usa", "chn"), e in labour
    note("   ", r, " ", e, ": flexible wage ", pct(w(flex, e, r), w(cal, e, r)), "% | sticky wage ", pct(w(sticky, e, r), w(cal, e, r)),
        "%, employment ", round(100 * emp(sticky, e, r), digits=2), "%")
end

# 3. One baseline year: the same with and without the sticky-wage module.
target(r, y) = 1.025^(y - BASE_YEAR)
mc.data = deepcopy(cal)
b_rd = run_baseline!(rd, mc, cal; periods=1, base_year=BASE_YEAR, gdp_target=target)
mc.data = deepcopy(cal)
b_sw = run_baseline!(sw, mc, cal; periods=1, base_year=BASE_YEAR, gdp_target=target)
check("3. baseline year, sticky wages on vs off", maxgap(b_sw.states[BASE_YEAR+1], b_rd.states[BASE_YEAR+1], CORE); tol=1e-6)

# 4. A policy run with no shock reproduces the baseline.
p0 = run_policy!(sw, mc, cal, b_sw)
check("4. no-shock policy vs baseline", maxgap(p0.states[BASE_YEAR+1], b_sw.states[BASE_YEAR+1], CORE); tol=1e-6)

# 5. The framework refuses unlike runs.
refused(f, msg) = try f(); 1 catch err; occursin(msg, sprint(showerror, err)) ? 0 : 2 end
check("5. policy with other GTAP-RD options is refused (0 = refused)",
    refused(() -> run_policy!(ModelSpec(GtapRD(depreciation=0.06), StickyWages()), mc, cal, b_sw), "differ from the baseline"); tol=0)
check("5. static run with GTAP-RD is refused (0 = refused)", refused(() -> run_static!(rd, mc, cal), "is dynamic"); tol=0)
finish()
