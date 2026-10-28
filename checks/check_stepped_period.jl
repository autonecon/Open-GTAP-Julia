# Checks that the stepped fallback for a dynamic year (GTAPRD.jl
# _solve_in_steps!) lands on the same equilibrium as a one-shot solve. A Gulf
# energy shipping shock (margins x4 from the second year) is solved over a
# two-year GTAP-RD + sticky-wage baseline twice: normally, and with every
# policy year forced through the four-step path.
#   OCGE_DATA=<folder> julia --project=checks checks/check_stepped_period.jl
include(joinpath(@__DIR__, "setup.jl"))

target(r, y) = 1.025^(y - BASE_YEAR)
function shipping!(m, year)
    m.data["α_qtmfsd"] .= cal["α_qtmfsd"]
    year >= BASE_YEAR + 2 || return
    for mg in string.(collect(mc.sets["marg"])), c in ("oil", "gas", "petro"), d in regs
        d == "gulf" && continue
        v = cal["α_qtmfsd"][mg, c, "gulf", d]
        (v isa Number && isfinite(v) && v > 0) && (m.data["α_qtmfsd"][mg, c, "gulf", d] = 4.0 * Float64(v))
    end
end
spec = ModelSpec(GtapRD(), StickyWages())
mc.data = deepcopy(cal)
b = run_baseline!(spec, mc, cal; periods=2, base_year=BASE_YEAR, gdp_target=target)
one = run_policy!(spec, mc, cal, b; apply_shock=shipping!)
FORCE_STEPS[] = true
stepped = try
    run_policy!(spec, mc, cal, b; apply_shock=shipping!)
finally
    FORCE_STEPS[] = false
end
for y in (BASE_YEAR + 1, BASE_YEAR + 2)
    check("year $(y - BASE_YEAR): stepped vs one-shot", maxgap(stepped.states[y], one.states[y], CORE); tol=1e-6)
end
finish()
