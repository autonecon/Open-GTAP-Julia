# Checks of the GTAP-RD layer (GTAP-RD/GTAPRD.jl) and the core's afe.
#   OCGE_DATA=<folder> julia --project=checks checks/check_gtap_rd.jl
include(joinpath(@__DIR__, "setup.jl"))

# 1. Factor roles come from the model's sets, not from names.
note("labour: ", labour_endowments(mc), " | land: ", land_endowments(mc), " | capital: ", mc.sets["endwc"], " | fixed: ", mc.sets["endwf"])
check("1. land is the sluggish factor (0 = yes)", land_endowments(mc) == ["land"] ? 0 : 1; tol=0)
check("1. labour is the two labour types (0 = yes)", Set(labour_endowments(mc)) == Set(["skilled labor", "unskilled labor"]) ? 0 : 1; tol=0)
set_land_endowments!(mc, String[])
check("1. declared: no land, so land counts as labour (0 = yes)", "land" in labour_endowments(mc) ? 0 : 1; tol=0)
delete!(mc.sets, "endwl")

# 2. afe is in the model, 1 in the base, fixed, and the base re-solves to calibration.
c = deepcopy(mc); run_model!(c)
check("2. afe in the base minus 1", maximum(abs.(filter(isfinite, Array(cal["afe"])) .- 1)); tol=0)
check("2. afe fixed everywhere (0 = yes)", all(mc.fixed["afe"]) ? 0 : 1; tol=0)
check("2. base re-solve: largest change", maxgap(c.data, cal, CORE); tol=1e-9)

# 3. No drivers, one year: next year's opening capital equals this year's closing capital.
z = deepcopy(mc); run_path!(z, cal; periods=1, base_year=BASE_YEAR, supply=nothing)
check("3. next kb vs this ke", maximum(abs(z.data["kb"][r] / cal["ke"][r] - 1) for r in regs); tol=1e-12)

# 4. 2% endowment growth grows labour only; land and natural resources stay put.
a = deepcopy(mc)
run_path!(a, cal; periods=1, base_year=BASE_YEAR, supply=nothing, drivers=BaselineDrivers(step=1, endowment_growth=0.02))
for e in labour_endowments(mc)
    check("4. $e grows 2%", maximum(abs(a.data["qe"][e, r] / cal["qe"][e, r] - 1.02) for r in regs); tol=1e-9)
end

# 5. One 5-year step against five annual steps: capital after 5 years.
b5 = deepcopy(mc); run_path!(b5, cal; periods=1, base_year=BASE_YEAR, supply=nothing, drivers=BaselineDrivers(step=5))
b1 = deepcopy(mc); run_path!(b1, cal; periods=5, base_year=BASE_YEAR, supply=nothing, drivers=BaselineDrivers(step=1))
check("5. capital after 5 years, one step vs five", maximum(abs(b5.data["kb"][r] / b1.data["kb"][r] - 1) for r in regs); tol=0.01)

# 6. 2% labour efficiency gives the same GDP as 2% more labour.
d = deepcopy(mc); rows_d = run_path!(d, cal; periods=1, base_year=BASE_YEAR, supply=nothing, drivers=BaselineDrivers(step=1, productivity_growth=0.02))
q = deepcopy(mc); rows_q = run_path!(q, cal; periods=1, base_year=BASE_YEAR, supply=nothing, drivers=BaselineDrivers(step=1, endowment_growth=0.02))
gdp(rows) = Dict(r.region => r.real_gdp_index for r in rows if r.year == BASE_YEAR + 1)
check("6. GDP, 2% labour efficiency vs 2% labour", maximum(abs(gdp(rows_d)[r] / gdp(rows_q)[r] - 1) for r in regs); tol=1e-4)

# 7. A 3% real GDP target in every region, with the supply curves on.
e = deepcopy(mc); rows_e = run_path!(e, cal; periods=1, base_year=BASE_YEAR, gdp_target=(r, y) -> 1.03)
check("7. GDP target 3%: worst gap", maximum(abs(r.real_gdp_index / 1.03 - 1) for r in rows_e if r.year == BASE_YEAR + 1); tol=1e-4)

# 8. In that run land and natural resources sit on their supply curves:
# log(q/q0) = 0.5 log(real price / base real price), to the supply loop's tolerance (1e-3 in logs).
rp(d, p, idx, r) = Float64(d[p][idx...]) / Float64(d["ppriv"][r])
curve(q, q0, p, p0) = abs(log(q / q0) - 0.5 * log(p / p0))
land_gap = maximum(curve(Float64(e.data["qe"]["land", r]), Float64(cal["qe"]["land", r]), rp(e.data, "pe", ("land", r), r), rp(cal, "pe", ("land", r), r)) for r in regs)
nat = [(a, r) for a in string.(collect(mc.sets["acts"])), r in regs if isfinite(Float64(cal["qesf"]["natres", a, r])) && Float64(cal["qesf"]["natres", a, r]) > 0]
nat_gap = maximum(curve(Float64(e.data["qesf"]["natres", a, r]), Float64(cal["qesf"]["natres", a, r]), rp(e.data, "pes", ("natres", a, r), r), rp(cal, "pes", ("natres", a, r), r)) for (a, r) in nat)
check("8. land on its supply curve (log gap)", land_gap; tol=1e-3)
check("8. natural resources on their supply curves (log gap)", nat_gap; tol=1e-3)
check("8. land moved at all (0 = yes)", maximum(abs(Float64(e.data["qe"]["land", r]) / Float64(cal["qe"]["land", r]) - 1) for r in regs) > 1e-6 ? 0 : 1; tol=0)
finish()
