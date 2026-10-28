# Industry-specific capital, after GTAP-MVH (Dixon, Rimmer and Tran 2019),
# whose investment theory is GTAP's and ORANI's (Dixon et al.
# 1982).
#
# Standard GTAP moves capital freely between industries within a year at one
# regional rental. With this module each industry's capital is fixed within
# the year, so each industry earns its own rental, and new investment goes to
# the industries with the highest expected returns:
#
#   qes(cap,j,r)  = rho(r) KB(j,r)                                  stock fixed in the year
#   RORC(j,r)     = rental(j,r) / pinv(r) - delta, as GTAP's e_rorc by industry
#   RORE(j,r)     = RORC(j,r) (KE(j,r) / KB(j,r))^(-RORFLEX)        expected return
#   RORE(j,r)     = F(j,r) RORE(r)                                  investors equalise
#   sum_j KE(j,r) = KE(r) = qinv(r) + (1 - delta) KB(r)             ties to the region
#
# The last line replaces the core's regional expected-return equation e_rore;
# the first replaces the capital rows of e_qes1 (rental = regional rental).
# Regional investment is still set by GTAP's global bank, and the regional
# stock is the sum of industry stocks, so GTAP-RD's accumulation is unchanged.
# GTAP-MVH writes the industry rental as a phantom tax on capital use that sums
# to zero in each region; in levels the industry rental is the same thing.
#
# The expected-return equation is in calibrated form against the base, so it
# holds in the base whatever RORFLEX is. GTAP-MVH uses RORFLEX = 5 (GTAP: 10).
#
# Investment floor (on by default): an industry's capital can shrink only by
# depreciation, KE >= (1 - delta) KB. Where the floor binds, the industry's
# expected return is below the regional one. The complementarity
#   I(j,r) >= 0,  F RORE(r) - RORE(j,r) >= 0,  I(j,r) (F RORE(r) - RORE(j,r)) = 0
# is solved as one smooth equation (Fischer-Burmeister, smoothed by a tiny mu,
# 1e-14 by default).
#
# Data: capital rentals by activity, the regional capital stock and
# depreciation, which every GTAP-format database has. Base industry stocks
# split the regional stock in proportion to capital rentals (GTAP-MVH).

struct IndustryCapital <: ModelModule
    rorflex::Float64
    floor::Bool
    mu::Float64
end
IndustryCapital(; rorflex=5.0, floor=true, mu=1e-14) = IndustryCapital(Float64(rorflex), floor, Float64(mu))

structural(::IndustryCapital) = true
replaces(::IndustryCapital) = (:e_qes1, :e_rore)

const _IC_REF = "industry_capital_reference"
const _IC_QE_FIXED = "industry_capital_core_qe_fixed"

_ic_num(x) = (x isa Number && isfinite(Float64(x))) ? Float64(x) : NaN

# Activity-region pairs that use capital, from the built model.
function _ic_pairs(mc)
    m = mc.model
    cap = only(string.(mc.sets["endwc"]))
    [(a, r) for a in string.(collect(mc.sets["acts"])), r in string.(collect(mc.sets["reg"]))
     if is_valid(m, m[:qes][cap, a, r])] |> vec
end

function extend_model!(ic::IndustryCapital, mc)
    m = mc.model
    haskey(object_dictionary(m), :ic_kb) && error("the model already has industry-capital equations")
    for k in ("kb", "ke", "rorc", "rore", "qes", "pes")
        haskey(mc.data, k) || error("industry capital needs $k in the data; the dataset must give capital rentals by activity and the capital stock (VKB)")
    end
    cap = only(string.(mc.sets["endwc"]))
    acts = string.(collect(mc.sets["acts"]))
    regs = string.(collect(mc.sets["reg"]))
    pairs = _ic_pairs(mc)
    isempty(pairs) && error("no activity uses capital: the dataset has no capital rentals by activity")

    # Base values, stored once: the solution in mc.data when first attached.
    ref = get!(mc.parameters, _IC_REF) do
        d = mc.data
        Dict("kb" => Dict(r => _ic_num(d["kb"][r]) for r in regs),
             "ke" => Dict(r => _ic_num(d["ke"][r]) for r in regs),
             "rorc" => Dict(r => _ic_num(d["rorc"][r]) for r in regs),
             "rore" => Dict(r => _ic_num(d["rore"][r]) for r in regs),
             "share" => Dict((a, r) => _ic_num(d["pes"][cap, a, r]) * _ic_num(d["qes"][cap, a, r]) /
                 sum(_ic_num(d["pes"][cap, b, r]) * _ic_num(d["qes"][cap, b, r]) for (b, s) in pairs if s == r) for (a, r) in pairs))
    end

    # The core rows this module rewrites: rental = regional rental for
    # capital, and the regional expected return.
    for (a, r) in pairs
        c = m[:e_qes1][cap, a, r]
        is_valid(m, c) && delete(m, c)
    end
    for r in regs
        c = m[:e_rore][r]
        is_valid(m, c) && delete(m, c)
    end

    @variables(m, begin
        ic_kb[acts, regs]
        ic_ke[acts, regs]
        ic_rorc[acts, regs]
        ic_f[acts, regs]
    end)
    have = Set(pairs)
    for a in acts, r in regs
        (a, r) in have && continue
        for v in (ic_kb, ic_ke, ic_rorc, ic_f)
            delete(m, v[a, r])
        end
    end
    qes, pes, qe, pe, ρ, δ = m[:qes], m[:pes], m[:qe], m[:pe], m[:ρ], m[:δ]
    kb, ke, rore, pinv = m[:kb], m[:ke], m[:rore], m[:pinv]
    φ = ic.rorflex
    κ(r) = ref["ke"][r] / ref["kb"][r]
    cons = ConstraintRef[]
    for (a, r) in pairs
        push!(cons, @constraint(m, log(qes[cap, a, r]) == log(ρ[r] * ic_kb[a, r])))
        # GTAP's e_rorc, industry by industry.
        push!(cons, @constraint(m, log(ic_rorc[a, r] * (qes[cap, a, r] - δ[r] * ic_kb[a, r])) ==
                                   log(qes[cap, a, r] * pes[cap, a, r] / pinv[r])))
        rb, eb = ref["rorc"][r], ref["rore"][r]
        if !ic.floor
            push!(cons, @constraint(m, log(ic_f[a, r] * rore[r]) - log(eb) ==
                                       log(ic_rorc[a, r]) - log(rb) - φ * (log(ic_ke[a, r] / ic_kb[a, r]) - log(κ(r)))))
        else
            x = @expression(m, ic_ke[a, r] / ic_kb[a, r] - (1 - δ[r]))
            y = @expression(m, (ic_f[a, r] * rore[r] - eb * (ic_rorc[a, r] / rb) * ((ic_ke[a, r] / ic_kb[a, r]) / κ(r))^(-φ)) / eb)
            push!(cons, @constraint(m, x + y - sqrt(x^2 + y^2 + 2 * ic.mu) == 0))
        end
    end
    for r in regs
        js = [a for (a, s) in pairs if s == r]
        isempty(js) && continue
        push!(cons, @constraint(m, log(pe[cap, r] * qe[cap, r]) == log(sum(pes[cap, a, r] * qes[cap, a, r] for a in js))))
        push!(cons, @constraint(m, log(sum(ic_ke[a, r] for a in js)) == log(ke[r])))
    end
    m[:e_industry_capital] = cons

    # The core's closure for the regional capital quantity, restored on detach.
    mc.parameters[_IC_QE_FIXED] = Dict((e, r) => mc.fixed["qe"][e, r] for e in string.(mc.sets["endwc"]) for r in names(mc.fixed["qe"])[2])
    for k in ("ic_kb", "ic_ke", "ic_rorc", "ic_f")
        mc.lower[k] = 1e-14
        mc.fixed[k] = NamedArray(falses(length(acts), length(regs)), (acts, regs))
    end
    delete!(mc.data, "ic_kb")
    ensure_data!(ic, mc)
    set_closure!(ic, mc, :baseline)
    return nothing
end

function ensure_data!(::IndustryCapital, mc)
    haskey(mc.data, "ic_kb") && return nothing
    ref = mc.parameters[_IC_REF]
    acts = string.(collect(mc.sets["acts"]))
    regs = string.(collect(mc.sets["reg"]))
    blank() = NamedArray(fill(NaN, length(acts), length(regs)), (acts, regs))
    kbj, kej, rc, f = blank(), blank(), blank(), blank()
    for ((a, r), s) in ref["share"]
        # The current regional stocks, split as in the base.
        kbj[a, r] = s * _ic_num(mc.data["kb"][r])
        kej[a, r] = s * _ic_num(mc.data["ke"][r])
        rc[a, r] = _ic_num(mc.data["rorc"][r])
        f[a, r] = 1.0
    end
    merge!(mc.data, Dict("ic_kb" => kbj, "ic_ke" => kej, "ic_rorc" => rc, "ic_f" => f))
    return nothing
end

# Same closure in both phases: industry stocks and risk shifters are fixed,
# the regional capital quantity follows the industry stocks.
function set_closure!(::IndustryCapital, mc, phase::Symbol)
    mc.fixed["ic_kb"] .= true
    mc.fixed["ic_f"] .= true
    mc.fixed["ic_ke"] .= false
    mc.fixed["ic_rorc"] .= false
    for e in string.(mc.sets["endwc"]), r in names(mc.fixed["qe"])[2]
        mc.fixed["qe"][e, r] = false
    end
    return nothing
end

# Switched off: the regional capital quantity takes the core's closure again.
function detach!(::IndustryCapital, mc)
    for ((e, r), v) in pop!(mc.parameters, _IC_QE_FIXED, Dict())
        mc.fixed["qe"][e, r] = v
    end
end

# Before each solved year: this year's industry stocks are last year's
# end-of-year stocks. GTAP-RD has already moved the regional stock to their sum.
function before_solve!(ic::IndustryCapital, mc, year, run::ModelRun)
    ensure_data!(ic, mc)
    # A Leontief capital-energy nest with fixed industry capital can have no
    # solution (GTAP-E's ELKE = 0 for petroleum refining fixes its crude use).
    for m in run.spec.modules
        m isa GtapE || continue
        zero = sort([a for (a, v) in m.elke if a != "*" && v == 0])
        isempty(zero) || error("industry capital with GTAP-E needs ELKE > 0 in every activity; 0 for $(join(zero, ", ")). Use GtapE(...; elke_fixed=0.1)")
    end
    # A static run keeps the base stocks.
    has_module(run.spec, GtapRD) || return
    rd = get_module(run.spec, GtapRD)
    rd.drivers.step == 1 || error("industry capital supports annual steps only")
    # Industry stocks depreciate at the model's δ; an override in GtapRD would
    # apply to the regional stock only and be silently lost.
    rd.depreciation === nothing || error("GtapRD(depreciation=...) is not supported with industry capital: set δ in the data")
    # The end-of-year stock starts from last year's growth: starting it at the
    # new beginning stock (no growth) puts the investment equation far from
    # its solution, which Ipopt may not recover from (seen with GTAP-E on).
    kbj, kej = mc.data["ic_kb"], mc.data["ic_ke"]
    for ((a, r), _) in mc.parameters[_IC_REF]["share"]
        growth = kej[a, r] / kbj[a, r]
        kbj[a, r] = kej[a, r]
        kej[a, r] = growth * kbj[a, r]
    end
end

"""Industry capital by year: start and end stocks, implied gross investment and whether the floor binds."""
function industry_capital_report(mc, run::ModelRun)
    rows = NamedTuple[]
    for y in sort(collect(keys(run.states)))
        d = run.states[y]
        haskey(d, "ic_kb") || continue
        for ((a, r), _) in mc.parameters[_IC_REF]["share"]
            kb, ke = _ic_num(d["ic_kb"][a, r]), _ic_num(d["ic_ke"][a, r])
            inv = ke - (1 - _ic_num(d["δ"][r])) * kb
            push!(rows, (year=y, region=r, activity=a, kb=kb, ke=ke, investment=inv, at_floor=inv <= 1e-8 * kb))
        end
    end
    return rows
end
