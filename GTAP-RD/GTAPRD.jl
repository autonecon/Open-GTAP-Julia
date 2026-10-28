# GTAP-RD for the Julia GTAP v7 levels model.
#
# This is the between-period layer. It does not replace the static model.
# Each period is a standard GTAP solve with the capital stock predetermined.
# After the solve, the next period's beginning capital is the capital left by
# this period's investment, which is the GTAP-RD accumulation identity.
#
# For a one-year step that identity is the static model's end-of-period stock:
#     ke = qinv + (1 - δ) * kb
# and next year's beginning stock is that ke. For a step of n years, investment
# grows at a constant rate g across the step, as in GTAP-RD and ENVISAGE:
#     kb' = kb * (1-δ)^n + qinv * ((1+g)^n - (1-δ)^n) / (g + δ)
# run_path! takes g from the investment solved at the end of the step and
# re-solves until the stock is consistent with it. With g = 0 this is the
# constant-investment formula.
# The capital endowment qe["capital"] is scaled by kb'/kb. The static equation
# e_kb then keeps the beginning stock equal to that endowment.
#
# Labour endowments, population, and productivity are exogenous baselines.
# endowment_growth applies to labour only. Land and natural resources are not
# grown with labour: as in GTAP-RD they move along iso-elastic supply curves
# in their real price (elasticity 0.5, GTAP-RD's ESPF and ESMS).
# Productivity is labour-augmenting, as GTAP-RD's afelabreg: it scales the
# model's afe for every labour endowment, uniformly across activities in a
# region. afe for capital, land and natural resources stays at 1.
# Capital is never grown by the exogenous endowment rate.

using GlobalTradeAnalysisProjectModelV7
using JuMP
using NamedArrays
include(joinpath(@__DIR__, "zero_hessian.jl"))

struct BaselineDrivers
    step::Int
    population_growth::Float64
    endowment_growth::Float64
    productivity_growth::Float64
end

BaselineDrivers(; step=1, population_growth=0.0, endowment_growth=0.0, productivity_growth=0.0) =
    BaselineDrivers(Int(step), Float64(population_growth), Float64(endowment_growth), Float64(productivity_growth))

"""
Capital stock after `step` years of depreciation and investment.

`qinv` is the investment flow in the first year of the step. It grows at
`investment_growth` a year across the step; 0 holds it constant.
"""
function accumulate_capital(kb, qinv, depr, step; investment_growth=0.0)
    step >= 1 || error("step must be at least 1")
    (isfinite(kb) && isfinite(qinv) && kb > 0) || return kb
    g = Float64(investment_growth)
    isfinite(g) && g > -1 || error("investment growth must be above -1")
    if !(isfinite(depr) && depr > 1e-10)
        return kb + qinv * (abs(g) < 1e-12 ? step : ((1 + g)^step - 1) / g)
    end
    depr < 1 || error("depreciation rate must be below 1")
    survived = (1 - depr)^step
    abs(g + depr) < 1e-12 && return kb * survived + qinv * step * survived / (1 - depr)
    return kb * survived + qinv * ((1 + g)^step - survived) / (g + depr)
end

"""
Declare which endowments are land, stored with the model's sets as `endwl` (so
it travels with `mc` into every run). Use it when an aggregation has more than
one sluggish factor, or land that is not sluggish.
"""
set_land_endowments!(mc, names) = (mc.sets["endwl"] = string.(collect(names)))

"""
Land endowments: `endwl` if set (see `set_land_endowments!`), else the
sluggish endowments other than capital, which is where GTAP's standard
aggregations put land. With more than one such factor the choice is ambiguous
and the call stops: declare land with `set_land_endowments!`.
"""
function land_endowments(mc)
    haskey(mc.sets, "endwl") && return string.(mc.sets["endwl"])
    land = setdiff(string.(get(mc.sets, "endws", String[])), string.(mc.sets["endwc"]))
    length(land) <= 1 || error("more than one sluggish factor ($(join(land, ", "))): declare land with set_land_endowments!(mc, names)")
    return land
end

"""
Labour endowments: every endowment that is not capital, not a fixed factor
(natural resources), and not land.
"""
function labour_endowments(mc)
    other = union(Set(string.(get(mc.sets, "endwf", String[]))), Set(string.(mc.sets["endwc"])), Set(land_endowments(mc)))
    return [e for e in string.(mc.sets["endw"]) if !(e in other)]
end

"""
Update beginning capital from the current solution, then grow population,
labour, and labour efficiency. Land and natural resources are not shifted
here; `solve_period!` moves them along their supply curves.
The current rate-of-return closure is left unchanged: capital stays exogenous
inside the period.

`investment_growth` maps a region to the annual growth of investment across
the step. It only matters when `drivers.step > 1`; leave it out for 0.
"""
function advance_period!(mc, drivers::BaselineDrivers; investment_growth=nothing, depreciation=nothing)
    drivers.step >= 1 || error("step must be at least 1")
    regs = mc.sets["reg"]
    for r in regs
        g = investment_growth === nothing ? 0.0 : get(investment_growth, r, 0.0)
        _set_capital!(mc, r, Float64(mc.data["kb"][r]), Float64(mc.data["qinv"][r]), Float64(mc.data["qe"]["capital", r]), drivers.step, g; depreciation=depreciation)
        gpop = drivers.population_growth
        mc.data["pop"][r] = Float64(mc.data["pop"][r]) * (1 + gpop)^drivers.step
    end
    gend = drivers.endowment_growth
    if gend != 0
        factor = (1 + gend)^drivers.step
        qe_names = Set(string.(names(mc.data["qe"])[1]))
        for e in labour_endowments(mc)
            e in qe_names || continue
            for r in regs
                v = mc.data["qe"][e, r]
                (v isa Number && isfinite(Float64(v))) || continue
                mc.data["qe"][e, r] = Float64(v) * factor
            end
        end
    end
    if drivers.productivity_growth != 0
        for r in regs
            scale_labour_efficiency!(mc, r, (1 + drivers.productivity_growth)^drivers.step)
        end
    end
    return mc
end

"""
Multiply labour efficiency (afe for every labour endowment, all activities)
in region r by `factor`. This is GTAP-RD's afelabreg with LABMULT = 1.
"""
function scale_labour_efficiency!(mc, r, factor)
    afe = mc.data["afe"]
    n = 0
    for e in labour_endowments(mc), a in names(afe)[2]
        v = afe[e, a, r]
        if v isa Number && isfinite(Float64(v)) && Float64(v) > 0
            afe[e, a, r] = Float64(v) * factor
            n += 1
        end
    end
    return n
end

"""Set region r's capital from the stock, investment and endowment at the start of a step. Returns the relative change in kb."""
function _set_capital!(mc, r, kb, qinv, qe0, step, g; depreciation=nothing)
    (isfinite(qe0) && isfinite(kb) && kb > 0) || return 0.0
    depr = depreciation === nothing ? Float64(mc.data["δ"][r]) : Float64(depreciation)
    kb_next = accumulate_capital(kb, qinv, depr, step; investment_growth=g)
    isfinite(kb_next) || return 0.0
    old = Float64(mc.data["kb"][r])
    mc.data["qe"]["capital", r] = qe0 * (kb_next / kb)
    mc.data["kb"][r] = kb_next
    return abs(kb_next / old - 1)
end

# calculate_gdp multiplies quantities by prices; flows the model dropped are
# NaN in the data and would make every region NaN. Treat them as zero.
const _GDP_KEYS = ("qga", "qpa", "qia", "qst", "qxs", "pga", "ppa", "pia", "pds", "pfob", "pcif")

function _gdp_data(data)
    out = copy(data)
    for k in _GDP_KEYS
        haskey(out, k) || continue
        a = copy(out[k])
        for i in eachindex(a)
            v = a[i]
            (v isa Number && isfinite(v)) || (a[i] = 0.0)
        end
        out[k] = a
    end
    return out
end

function _gdp_index(mc, base_data)
    d0 = _gdp_data(base_data)
    q1 = calculate_gdp(sets=mc.sets, data0=d0, data1=_gdp_data(mc.data))
    q0 = calculate_gdp(sets=mc.sets, data0=d0, data1=d0)
    return q1 ./ q0
end

function _snapshot_rows(mc, year, gdp_index)
    rows = NamedTuple[]
    for r in mc.sets["reg"]
        push!(rows, (
            year=year,
            region=String(r),
            kb=Float64(mc.data["kb"][r]),
            ke=Float64(mc.data["ke"][r]),
            qinv=Float64(mc.data["qinv"][r]),
            qe_capital=Float64(mc.data["qe"]["capital", r]),
            pop=Float64(mc.data["pop"][r]),
            income=Float64(mc.data["y"][r]),
            real_gdp_index=Float64(gdp_index[r]),
            labour_efficiency=labour_efficiency(mc, r),
        ))
    end
    return rows
end

"""Labour efficiency (afe) in region r. It is uniform across labour types and activities when only scale_labour_efficiency! moves it."""
function labour_efficiency(mc, r)
    afe = mc.data["afe"]
    vals = [Float64(afe[e, a, r]) for e in labour_endowments(mc), a in names(afe)[2] if isfinite(Float64(afe[e, a, r])) && Float64(afe[e, a, r]) > 0]
    return isempty(vals) ? NaN : maximum(vals)
end

"""
Solve once, retrying with four times the iteration limit before giving up.
Returns false when both attempts fail; mc.data is then left as it was.
`retry=false` makes a single attempt.
"""
function _try_solve!(mc; max_iter=80, retry=true)
    for mi in (retry ? (max_iter, 4 * max_iter) : (max_iter,))
        try
            zero_hessian!(mc.model)
            run_model!(mc; max_iter=mi)
            return true
        catch e
            e == "Not solved!" || rethrow()
            println(stderr, "  solve did not converge in $mi iterations"); flush(stderr)
        end
    end
    return false
end

# Steps from `start` to the shocked data now in mc.data, each solve starting
# from the last, like GEMPACK's multi-step solutions (Harrison and Pearson
# 1996, Computational Economics 9, 83-127); false if a step fails. Every data
# entry that differs from `start` moves in a straight line.
function _solve_in_steps!(mc, start, steps; max_iter)
    target = deepcopy(mc.data)
    changed = [k for k in keys(target) if haskey(start, k) && !isequal(target[k], start[k])]
    isempty(changed) && return false
    println(stderr, "  applying the shock in $steps steps"); flush(stderr)
    mc.data = deepcopy(start)
    # Entries added since `start` (by a module's before_solve!, say) go in as they are.
    for k in keys(target)
        haskey(start, k) || (mc.data[k] = deepcopy(target[k]))
    end
    for j in 1:steps
        w = j / steps
        for k in changed
            a, b = start[k], target[k]
            if j == steps
                mc.data[k] = deepcopy(b)
            elseif a isa AbstractArray{<:Real}
                v = copy(b)
                for i in eachindex(v)
                    isfinite(a[i]) && isfinite(b[i]) && (v[i] = a[i] + w * (b[i] - a[i]))
                end
                mc.data[k] = v
            elseif a isa Real
                mc.data[k] = a + w * (b - a)
            else
                mc.data[k] = b
            end
        end
        _try_solve!(mc; max_iter=max_iter) || return false
    end
    return true
end

"""
Upward-sloping supply for natural resources and land, as GTAP-RD
(`swap qesf = qesfsupply`, `swap qe(ENDWS) = qelsupply`): supply moves with
the real price of the factor (its price over the private consumption price),
relative to the base year, with a constant elasticity. GTAP-RD's parameter
file sets both elasticities (ESPF, ESMS) to 0.5. `nothing` in their place, or
an elasticity of 0, keeps the factor fixed.
"""
struct ResourceSupply
    natres::Float64
    land::Float64
end
const GTAPRD_SUPPLY = ResourceSupply(0.5, 0.5)

# One entry per supply curve: data key and index of the quantity, its base
# value, the price key and index, the region, and the elasticity.
function _supply_items(mc, base_data, supply::ResourceSupply)
    items = NamedTuple[]
    ok(x) = x isa Number && isfinite(Float64(x)) && Float64(x) > 0
    if supply.natres != 0
        for e in string.(get(mc.sets, "endwf", String[])), a in string.(mc.sets["acts"]), r in string.(mc.sets["reg"])
            q0 = base_data["qesf"][e, a, r]
            ok(q0) && ok(base_data["pes"][e, a, r]) || continue
            push!(items, (q="qesf", qi=(e, a, r), q0=Float64(q0), p="pes", pi=(e, a, r), r=r, eps=supply.natres))
        end
    end
    if supply.land != 0
        mobile_or_sluggish = Set(string.(get(mc.sets, "endwms", String[])))
        for e in land_endowments(mc), r in string.(mc.sets["reg"])
            e in mobile_or_sluggish || continue
            q0 = base_data["qe"][e, r]
            ok(q0) && ok(base_data["pe"][e, r]) || continue
            push!(items, (q="qe", qi=(e, r), q0=Float64(q0), p="pe", pi=(e, r), r=r, eps=supply.land))
        end
    end
    return items
end

_log_real_price(d, it) = log(Float64(d[it.p][it.pi...]) / Float64(d["ppriv"][it.r]))

# Testing only (checks/check_stepped_period.jl): true sends every period with a
# `start` straight to the stepped solve.
const FORCE_STEPS = Ref(false)

"""
Solve one period with GTAP-RD's endogenous pieces, iterating until they agree:

- labour efficiency moves region by region until real GDP matches `targets`
  (region => index on the base year) within `tol`, GTAP-RD's closure swap
  afelabreg = qgdp with population exogenous. An empty `targets` leaves
  labour efficiency as it is (the policy closure);
- natural resources and land move along their supply curves (`supply`)
  until supply and price agree within `supply_tol` (in logs).

If a solve fails after a step, the step is halved and retried, up to three
times. If the period's first solve fails and `start` (the last solved data)
is given, the period's changes are applied in `steps` equal steps from it
(`_solve_in_steps!`).
"""
function solve_period!(mc, base_data, targets; supply=GTAPRD_SUPPLY, tol=0.003, supply_tol=1e-3, iterations=25, max_iter=80, start=nothing, steps=4)
    (!FORCE_STEPS[] && _try_solve!(mc; max_iter=max_iter)) || (start !== nothing && _solve_in_steps!(mc, start, steps; max_iter=max_iter)) ||
        error("period did not solve")
    items = supply === nothing ? NamedTuple[] : _supply_items(mc, base_data, supply)
    isempty(targets) && isempty(items) && return 0.0
    lp0 = [_log_real_price(base_data, it) for it in items]
    elas = Dict(r => 1.0 for r in keys(targets))
    prev = Dict{String,Tuple{Float64,Float64}}()
    prev_supply = Vector{Union{Nothing,Tuple{Float64,Float64}}}(nothing, length(items))
    for it_n in 1:iterations
        gidx = _gdp_index(mc, base_data)
        gaps = Dict(r => targets[r] / Float64(gidx[r]) - 1 for r in keys(targets))
        worst = isempty(gaps) ? 0.0 : maximum(abs, values(gaps))
        worst_r = isempty(gaps) ? "" : argmax(r -> abs(gaps[r]), collect(keys(gaps)))
        x = [log(Float64(mc.data[it.q][it.qi...]) / it.q0) for it in items]
        lp = [_log_real_price(mc.data, it) for it in items]
        f = [x[k] - items[k].eps * (lp[k] - lp0[k]) for k in eachindex(items)]
        worst_supply = isempty(f) ? 0.0 : maximum(abs, f)
        println(stderr, "  iteration $it_n: worst GDP gap $(round(100 * worst, digits=3))% $worst_r, worst supply gap $(round(100 * worst_supply, digits=3))%"); flush(stderr)
        worst < tol && worst_supply < supply_tol && return worst
        it_n == iterations && error("period did not converge after $iterations iterations")
        moves = Dict{String,Float64}()
        for (r, goal) in targets
            actual = Float64(gidx[r])
            if haskey(prev, r)
                (a0, m0) = prev[r]
                obs = log(actual / a0) / log(m0)
                (abs(log(m0)) > 1e-5 && isfinite(obs) && 0.05 < obs < 5) && (elas[r] = 0.4 * elas[r] + 0.6 * obs)
            end
            moves[r] = clamp((goal / actual)^(0.9 / elas[r]), 0.8, 1.25)
        end
        # Newton step on x = eps * (log real price - base), using the observed
        # response of the price to supply; half a step until one is observed.
        steps = zeros(length(items))
        for k in eachindex(items)
            slope = 0.0
            if prev_supply[k] !== nothing
                (x1, lp1) = prev_supply[k]
                abs(x[k] - x1) > 1e-9 && (slope = min(0.0, (lp[k] - lp1) / (x[k] - x1)))
            end
            steps[k] = prev_supply[k] === nothing ? -0.5 * f[k] : -f[k] / (1 - items[k].eps * slope)
            steps[k] = clamp(steps[k], -0.2, 0.2)
            prev_supply[k] = (x[k], lp[k])
        end
        saved = Dict(k => deepcopy(mc.data[k]) for k in ("afe", "qesf", "qe"))
        solved = false
        for _ in 0:3
            for (r, m) in moves
                scale_labour_efficiency!(mc, r, m)
            end
            for (k, item) in enumerate(items)
                mc.data[item.q][item.qi...] = item.q0 * exp(x[k] + steps[k])
            end
            _try_solve!(mc; max_iter=max_iter) && (solved = true; break)
            for (k, v) in saved
                mc.data[k] = deepcopy(v)
            end
            for (r, m) in moves
                moves[r] = sqrt(m)
            end
            steps ./= 2
            println(stderr, "  halving the step"); flush(stderr)
        end
        solved || error("solve failed even with smaller steps")
        for (r, m) in moves
            prev[r] = (Float64(gidx[r]), m)
        end
    end
end

"""Solve with labour efficiency hitting GDP `targets`; see `solve_period!`."""
solve_to_gdp!(mc, base_data, targets; kwargs...) = solve_period!(mc, base_data, targets; kwargs...)

"""
Solve a baseline path.

`mc` must already be calibrated, rebuilt, and restored to the standard closure.
`base_data` is that calibrated solution and is the real-GDP reference.
The base year is recorded without a new solve. Each later period updates the
state, applies `apply_shock!(mc, year)` when given, and solves.

With `drivers.step > 1`, investment is assumed to grow at a constant rate
across the step. That rate comes from the investment solved at the end of the
step, so the step is re-solved (at most `capital_iter` more times) until the
capital stock agrees with it to `capital_tol`.

`gdp_target(region, year)` returns the real GDP index wanted for that region
and year, or `nothing`. When it is given, each period is solved with
`solve_to_gdp!`, so labour efficiency is endogenous, as in GTAP-RD.

`after_period(mc, year, rows)` runs after each period, for example to save
progress.

`supply` gives natural resources and land GTAP-RD's upward-sloping supply
(elasticity 0.5 each by default); `nothing` holds them fixed.

`depreciation` overrides the database rate in capital accumulation between
periods only (a sensitivity test); the static model keeps its own δ.
"""
function run_path!(mc, base_data; periods::Int, base_year::Int=2017, drivers::BaselineDrivers=BaselineDrivers(), apply_shock=nothing, gdp_target=nothing, after_period=nothing, depreciation=nothing, supply=GTAPRD_SUPPLY, max_iter::Int=80, capital_iter::Int=4, capital_tol::Float64=1e-6)
    periods >= 1 || error("periods must be at least 1")
    rows = _snapshot_rows(mc, base_year, _gdp_index(mc, base_data))
    for s in 1:periods
        year = base_year + s * drivers.step
        start = Dict(r => (Float64(mc.data["kb"][r]), Float64(mc.data["qinv"][r]), Float64(mc.data["qe"]["capital", r])) for r in mc.sets["reg"])
        solved = deepcopy(mc.data)
        advance_period!(mc, drivers; depreciation=depreciation)
        apply_shock === nothing || apply_shock(mc, year)
        targets = Dict{String,Float64}()
        if gdp_target !== nothing
            for r in mc.sets["reg"]
                t = gdp_target(String(r), year)
                t === nothing || (targets[String(r)] = Float64(t))
            end
        end
        solve! = () -> solve_period!(mc, base_data, targets; supply=supply, max_iter=max_iter, start=solved)
        solve!()
        if drivers.step > 1
            for _ in 1:capital_iter
                change = 0.0
                for r in mc.sets["reg"]
                    kb0, qinv0, qe0 = start[r]
                    qinv1 = Float64(mc.data["qinv"][r])
                    g = (qinv0 > 0 && qinv1 > 0) ? (qinv1 / qinv0)^(1 / drivers.step) - 1 : 0.0
                    change = max(change, _set_capital!(mc, r, kb0, qinv0, qe0, drivers.step, g; depreciation=depreciation))
                end
                change < capital_tol && break
                solve!()
            end
        end
        append!(rows, _snapshot_rows(mc, year, _gdp_index(mc, base_data)))
        after_period === nothing || after_period(mc, year, rows)
    end
    return rows
end

function write_path(path, rows)
    open(path, "w") do io
        println(io, "year,region,kb,ke,qinv,qe_capital,pop,income,real_gdp_index,labour_efficiency")
        for row in rows
            println(io, row.year, ",", row.region, ",",
                row.kb, ",", row.ke, ",", row.qinv, ",", row.qe_capital, ",",
                row.pop, ",", row.income, ",", row.real_gdp_index, ",", row.labour_efficiency)
        end
    end
    return path
end
