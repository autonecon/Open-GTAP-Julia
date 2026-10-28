# Shared setup for the checks: reads the OCGE Data Base, aggregates it to five
# regions (Gulf, China, US, EU, rest of world) and nine sectors with the energy
# commodities separate, calibrates, and leaves `mc` in the standard closure
# with `cal` as the calibrated solution.
#
#   OCGE_DATA=<folder with gsdfset.har, gsdfpar.har, gsdfdat.har> julia --project=checks checks/<script>.jl
#
# The data base is the OCGE release asset (base year 2022). ZERO_HESS=1 (set
# below unless given) uses the fast zero-Hessian solver, which gives the same
# results as the exact Hessian on this square system.
using GlobalTradeAnalysisProjectModelV7, HeaderArrayFile, JuMP, NamedArrays
haskey(ENV, "ZERO_HESS") || (ENV["ZERO_HESS"] = "1")
const REPO = normpath(joinpath(@__DIR__, ".."))
include(joinpath(REPO, "checks", "prepare_for_solve.jl"))
include(joinpath(REPO, "GTAP-modules", "GTAPModules.jl"))
note(x...) = (println(stderr, x...); flush(stderr))

const BASE_YEAR = 2022
DATA = get(ENV, "OCGE_DATA", "")
isdir(DATA) || error("set OCGE_DATA to the folder holding the OCGE gsdfset.har, gsdfpar.har and gsdfdat.har")
read_har(f) = (h = HeaderArrayFile.File(joinpath(DATA, f)); Dict(keys(h) .=> NamedArray.(values(h))))
hData0, hSets0, hPar0 = read_har("gsdfdat.har"), read_har("gsdfset.har"), read_har("gsdfpar.har")
reg_codes = string.(collect(hSets0["reg"])); com_codes = string.(collect(hSets0["comm"])); end_codes = string.(collect(hSets0["endw"]))

function group_map(codes, groups, rest)
    m = NamedArray(fill(rest, length(codes)), (codes,))
    for (label, members) in groups, c in members
        c in codes || error("code $c is not in the data base")
        m[c] = label
    end
    return m
end

# A script can set REGION_GROUPS or COMMODITY_GROUPS (label => codes) before
# including this file. Unlisted regions go to "rest", unlisted commodities to "manuf".
@isdefined(REGION_GROUPS) || (REGION_GROUPS = [
    "gulf" => ["bhr", "irn", "irq", "kwt", "omn", "qat", "sau", "are"],
    "chn" => ["chn"], "usa" => ["usa"],
    "eu" => ["aut", "bel", "bgr", "hrv", "cyp", "cze", "dnk", "est", "fin", "fra", "deu", "grc", "hun", "irl", "ita", "lva", "ltu", "lux", "mlt", "nld", "pol", "prt", "rou", "svk", "svn", "esp", "swe"],
])
@isdefined(COMMODITY_GROUPS) || (COMMODITY_GROUPS = [
    "coal" => ["coa"], "oil" => ["oil"], "gas" => ["gas"], "petro" => ["pet"], "ely" => ["ely"],
    "agri" => ["crp", "for", "fsh"],
    "eint" => ["chm", "pha", "rpl", "nmm", "stl", "nfm", "pap", "ore", "min", "msp"],
    "svces" => ["wat", "con", "trd", "rdt", "sea", "air", "whs", "pst", "hos", "pub", "tel", "its", "fin", "rle", "pro", "adm", "gov", "edu", "hea", "art", "ots", "hhe"],
])
regMap = group_map(reg_codes, REGION_GROUPS, "rest")
comMap = group_map(com_codes, COMMODITY_GROUPS, "manuf")
endMap = group_map(end_codes, ["land" => ["land"], "capital" => ["capital"], "natres" => ["natres"],
    "skilled labor" => ["tech_aspros", "off_mgr_pros"],
    "unskilled labor" => ["clerks", "service_shop", "ag_othlowsk"]], "other")

(; hData, hParameters, hSets) = aggregate_data(; hData=hData0, hParameters=hPar0, hSets=hSets0, comMap=comMap, regMap=regMap, endMap=endMap)
# RDLT can come through aggregation as a scalar or one-element array; the model wants a zero-dimensional array.
let rd = hParameters["rdlt"]
    rd isa Number ? (hParameters["rdlt"] = fill(Float64(rd))) :
        length(vec(Array(rd))) == 1 && (hParameters["rdlt"] = fill(Float64(only(vec(Array(rd))))))
end
# Drop dust trade flows (below USD 100) and their margins.
valid = hData["vxsb"] .> 1e-4
for k in ["vcif", "vmsb", "vfob", "vxsb"]; hData[k][.!valid] .= 0; end
for m in hSets["marg"], c in hSets["comm"], s in hSets["reg"], d in hSets["reg"]
    valid[c, s, d] || (hData["vtwr"][m, c, s, d] = 0)
end
n_swap, v_swap = armington_swap!(hData)
note("armington_swap!: ", n_swap, " cells, ", v_swap, " moved")

note("Calibrating...")
mc = generate_initial_model(; hSets, hData, hParameters)
# Small flows shrink along a long baseline: lower the floor on quantities; prices keep theirs.
for k in collect(keys(mc.lower))
    startswith(k, "q") && mc.lower[k] == 1e-8 && (mc.lower[k] = 1e-14)
end
set_attribute(mc.model, "print_level", 0)
start = deepcopy(mc.data)
(; fixed_calibration, data_calibration) = generate_calibration_inputs(mc, start)
fixed_default = deepcopy(mc.fixed)
mc.data = data_calibration; mc.fixed = fixed_calibration
zero_hessian!(mc.model)
_t_cal = time()
run_model!(mc; max_iter=500)
note("calibration: ", termination_status(mc.model), ", ", barrier_iterations(mc.model), " iterations, ",
    round(time() - _t_cal, digits=1), " s; ", length(mc.sets["reg"]), " regions x ", length(mc.sets["comm"]), " commodities")
cal = deepcopy(mc.data)
rebuild_model!(mc); set_attribute(mc.model, "print_level", 0)
mc.fixed = deepcopy(fixed_default); mc.data = deepcopy(cal)

regs = string.(collect(mc.sets["reg"]))
maxgap(a, b, keys) = maximum(maximum(abs, filter(isfinite, Array(Float64.(a[k]) ./ Float64.(b[k]) .- 1)); init=0.0) for k in keys)
pct(a, b) = round(100 * (a / b - 1), digits=2)
const CORE = ("qo", "qfa", "qxs", "pe", "qe", "y", "ppriv", "qinv")

# Results of the checks: name, value, tolerance (nothing = reported only).
const RESULTS = NamedTuple[]
function check(name, value; tol=nothing)
    ok = tol === nothing || abs(value) <= tol
    push!(RESULTS, (; name, value, tol, ok))
    note(ok ? "PASS " : "FAIL ", name, ": ", value, tol === nothing ? "" : " (tolerance $tol)")
    return value
end
function finish()
    bad = filter(r -> !r.ok, RESULTS)
    note(length(RESULTS) - length(bad), " of ", length(RESULTS), " checks pass")
    isempty(bad) || error("failed: " * join([r.name for r in bad], "; "))
    println("DONE")
end
