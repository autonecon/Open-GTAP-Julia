# Checks of the GTAP-E module (experimental: firms only).
#   OCGE_DATA=<folder> julia --project=checks checks/check_gtap_e.jl
include(joinpath(@__DIR__, "setup.jl"))

gtape = GtapE(coal=["coal"], noncoal=["oil", "gas", "petro"], electricity=["ely"], no_ke=["agri"])
static = ModelSpec()
static_e = ModelSpec(gtape)

# Gulf crude oil capacity (its natural resource) falls 30%.
oil_shock!(m) = (m.data["qesf"]["natres", "oil", "gulf"] = 0.7 * Float64(cal["qesf"]["natres", "oil", "gulf"]))

flex = run_static!(static, mc, cal; shock! = oil_shock!).states[0]

# 1. Attaching GTAP-E leaves the base solution unchanged.
mc.data = deepcopy(cal)
attach!(static_e, mc)
_prepare!(static_e, mc, :baseline)
_try_solve!(mc; max_iter=200) || error("base re-solve with GTAP-E failed")
check("1. base re-solve with GTAP-E", maxgap(mc.data, cal, CORE); tol=1e-9)

# 2. The shock with energy substitution, then GTAP-E off again (core rebuilt) gives standard GTAP.
withe = run_static!(static_e, mc, cal; shock! = oil_shock!).states[0]
again = run_static!(static, mc, cal; shock! = oil_shock!).states[0]
check("2. GTAP-E off again vs standard GTAP", maxgap(again, flex, CORE); tol=1e-9)

# 3. Direction: with capital-energy substitution firms outside the Gulf cut oil
# and petroleum use by more, and the world oil price rises by less.
acts = string.(collect(mc.sets["acts"]))
use(d, c, r) = sum(Float64(d["qfa"][c, a, r]) for a in acts if isfinite(Float64(d["qfa"][c, a, r])))
wp(d, c) = sum(Float64(d["pds"][c, r]) * Float64(cal["qc"][c, r]) for r in regs) / sum(Float64(cal["qc"][c, r]) for r in regs)
cpi(d) = sum(Float64(d["ppriv"][r]) * Float64(cal["yp"][r]) for r in regs) / sum(Float64(cal["yp"][r]) for r in regs)
real_oil(d) = wp(d, "oil") / cpi(d)
check("3. world oil price rises less with GTAP-E (0 = yes)", real_oil(withe) < real_oil(flex) ? 0 : 1; tol=0)
for r in ("eu", "chn", "usa")
    note("   firms' oil use ", r, ": standard ", pct(use(flex, "oil", r), use(cal, "oil", r)), "% | GTAP-E ", pct(use(withe, "oil", r), use(cal, "oil", r)),
        "%; gas ", pct(use(flex, "gas", r), use(cal, "gas", r)), "% | ", pct(use(withe, "gas", r), use(cal, "gas", r)), "%")
end
note("   world oil price vs CPI: standard ", pct(real_oil(flex), real_oil(cal)), "% | GTAP-E ", pct(real_oil(withe), real_oil(cal)), "%")

# 4. The core's technology shifters still act with GTAP-E on: +5% output-augmenting
# technical change (gamma_qintva) in Gulf services raises its output.
tech!(m) = (m.data["γ_qintva"]["svces", "gulf"] *= 1.05)
t0 = run_static!(static, mc, cal; shock! = tech!).states[0]
te = run_static!(static_e, mc, cal; shock! = tech!).states[0]
qo(d) = Float64(d["qo"]["svces", "gulf"]) / Float64(cal["qo"]["svces", "gulf"]) - 1
check("4. gamma_qintva acts under GTAP-E (output change, GTAP-E / standard - 1)", qo(te) / qo(t0) - 1; tol=0.5)
finish()
