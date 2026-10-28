# Sticky real wages, after Dixon and Rimmer (2002) as used in
# GTAP-MVH (Dixon, Rimmer and Tran, 2019).
#
# In a policy run the real wage of each labour type deviates from its
# baseline path, and that deviation grows with the employment deviation:
#
#     W_t / W_t^F - 1 = (W_t-1 / W_t-1^F - 1) + alpha * (E_t / E_t^F - L_t / L_t^F) + SHIFT
#
# W is the real wage (the factor market price pe over the private consumption price ppriv),
# E employment (qe), L labour supply, and ^F the baseline. Labour supply
# follows its baseline here, so L_t / L_t^F = 1. SHIFT is endogenous in the
# baseline, where employment is fixed at the SSP labour force, and zero in a
# policy run, where employment is endogenous. A shock first moves employment;
# the wage then adjusts until employment is back on its baseline path.
# Dixon and Rimmer choose alpha so that the employment effect has largely
# gone after about five years.

struct StickyWages <: ModelModule
    alpha::Float64
end
StickyWages(; alpha=0.5) = StickyWages(Float64(alpha))

# Variables, by labour type and region:
#   sw_wreal  real wage, pe / ppriv
#   sw_wF     baseline real wage this year        (held fixed)
#   sw_eF     baseline employment this year       (held fixed)
#   sw_dlag   last year's real-wage deviation     (held fixed)
#   sw_shift  SHIFT: endogenous in the baseline, 0 in a policy run
const _SW_PARAMS = ("sw_wF", "sw_eF", "sw_dlag")

_sw_real_wage(d, e, r) = Float64(d["pe"][e, r]) / Float64(d["ppriv"][r])

function extend_model!(sw::StickyWages, mc)
    m = mc.model
    haskey(object_dictionary(m), :sw_wreal) && error("the model already has sticky-wage equations")
    labour = labour_endowments(mc)
    regs = string.(collect(mc.sets["reg"]))
    pe, ppriv, qe = m[:pe], m[:ppriv], m[:qe]
    alpha = sw.alpha
    @variables(m, begin
        sw_wreal[labour, regs]
        sw_wF[labour, regs]
        sw_eF[labour, regs]
        sw_dlag[labour, regs]
        sw_shift[labour, regs]
    end)
    @constraints(m, begin
        e_sw_wreal[e=labour, r=regs], log(sw_wreal[e, r]) == log(pe[e, r]) - log(ppriv[r])
        e_sw_rule[e=labour, r=regs], sw_wreal[e, r] == sw_wF[e, r] * (1 + sw_dlag[e, r] + alpha * (qe[e, r] / sw_eF[e, r] - 1) + sw_shift[e, r])
    end)
    ensure_data!(sw, mc)
    mc.lower["sw_wreal"] = 1e-8
    mc.lower["sw_wF"] = 1e-8
    mc.lower["sw_eF"] = 1e-14
    for k in ("sw_wreal", "sw_wF", "sw_eF", "sw_dlag", "sw_shift")
        mc.fixed[k] = NamedArray(falses(length(labour), length(regs)), (labour, regs))
    end
    set_closure!(sw, mc, :baseline)
    return nothing
end

# Starting values from the current solution for any sticky-wage data missing,
# for example after mc.data was reset to data saved before the module was attached.
function ensure_data!(::StickyWages, mc)
    haskey(mc.data, "sw_wreal") && haskey(mc.data, "sw_shift") && return nothing
    labour = labour_endowments(mc)
    regs = string.(collect(mc.sets["reg"]))
    blank() = NamedArray(zeros(length(labour), length(regs)), (labour, regs))
    w, en = blank(), blank()
    for e in labour, r in regs
        q = Float64(mc.data["qe"][e, r])
        (isfinite(q) && q > 0) || error("labour $e in $r has no employment; sticky wages need every labour type in every region")
        w[e, r] = _sw_real_wage(mc.data, e, r)
        en[e, r] = q
    end
    mc.data["sw_wreal"] = copy(w)
    mc.data["sw_wF"] = copy(w)
    mc.data["sw_eF"] = copy(en)
    mc.data["sw_dlag"] = blank()
    mc.data["sw_shift"] = blank()
    return nothing
end

function set_closure!(::StickyWages, mc, phase::Symbol)
    labour = labour_endowments(mc)
    for k in _SW_PARAMS
        mc.fixed[k] .= true
    end
    mc.fixed["sw_wreal"] .= false
    policy = phase == :policy
    # Baseline: employment is the SSP labour force and SHIFT absorbs the rule.
    # Policy: SHIFT is zero and employment follows labour demand.
    mc.fixed["sw_shift"] .= policy
    policy && (mc.data["sw_shift"] .= 0.0)
    for e in labour, r in names(mc.fixed["qe"])[2]
        mc.fixed["qe"][e, r] = !policy
    end
    return nothing
end

function before_solve!(sw::StickyWages, mc, year, run::ModelRun)
    ensure_data!(sw, mc)
    labour = labour_endowments(mc)
    regs = string.(collect(mc.sets["reg"]))
    if run.phase != :policy
        # Keep the fixed terms near the current solution so SHIFT stays small.
        for e in labour, r in regs
            mc.data["sw_wF"][e, r] = _sw_real_wage(mc.data, e, r)
            mc.data["sw_eF"][e, r] = Float64(mc.data["qe"][e, r])
            mc.data["sw_dlag"][e, r] = 0.0
        end
        return
    end
    ref = reference_state(run, year)
    dev = get!(run.store, :sw_deviation, Dict{Tuple{String,String},Float64}())
    for e in labour, r in regs
        wF = _sw_real_wage(ref, e, r)
        eF = Float64(ref["qe"][e, r])
        d = get(dev, (e, r), 0.0)
        mc.data["sw_wF"][e, r] = wF
        mc.data["sw_eF"][e, r] = eF
        mc.data["sw_dlag"][e, r] = d
        mc.data["sw_wreal"][e, r] = wF * (1 + d)
        mc.data["qe"][e, r] = eF
    end
end

function after_solve!(::StickyWages, mc, year, run::ModelRun)
    run.phase == :policy || return
    ref = reference_state(run, year)
    dev = run.store[:sw_deviation]
    for e in labour_endowments(mc), r in string.(collect(mc.sets["reg"]))
        wdev = Float64(mc.data["sw_wreal"][e, r]) / _sw_real_wage(ref, e, r) - 1
        edev = Float64(mc.data["qe"][e, r]) / Float64(ref["qe"][e, r]) - 1
        dev[(e, r)] = wdev
        push!(run.reports, (year=year, region=r, labour=e, real_wage_dev=wdev, employment_dev=edev))
    end
end

"""Write the sticky-wage report of a policy run: real wage and employment, % off baseline."""
function write_labour_report(path, run::ModelRun)
    open(path, "w") do io
        println(io, "year,region,labour,real_wage_pct,employment_pct")
        for x in run.reports
            haskey(x, :employment_dev) || continue
            println(io, x.year, ",", x.region, ",", x.labour, ",", round(100 * x.real_wage_dev, digits=4), ",", round(100 * x.employment_dev, digits=4))
        end
    end
    return path
end
