# Selectable modules for the Julia GTAP v7 levels model.
#
# A run names its modules in a ModelSpec:
#     ModelSpec()                              static GTAP
#     ModelSpec(GtapRD())                      GTAP-RD recursive dynamics
#     ModelSpec(GtapRD(), StickyWages())       GTAP-RD with sticky real wages
#
# Each module can add variables and equations to the built model
# (`extend_model!`), set its part of the closure for a phase
# (`set_closure!`, phase :baseline or :policy) and act before and after each
# period's solve (`before_solve!`, `after_solve!`). A module that is attached
# to a model but left out of a run's spec is switched off: it takes its
# baseline closure, which leaves the core solution unchanged.
#
# The core model (src/) and the GTAP-RD layer (GTAP-RD/GTAPRD.jl) are
# not changed by this file.
#
# Runs:
#     run_static!(spec, mc, base; shock!)
#     baseline = run_baseline!(spec, mc, base; periods, apply_shock, gdp_target)
#     policy   = run_policy!(spec, mc, base, baseline; apply_shock)
# A policy run follows the baseline's years, starts from its first state and
# uses its solved values (labour efficiency, wages, employment) as reference.

using GlobalTradeAnalysisProjectModelV7
using JuMP
using NamedArrays

if !isdefined(@__MODULE__, :run_path!)
    include(joinpath(@__DIR__, "..", "GTAP-RD", "GTAPRD.jl"))
end

abstract type ModelModule end

module_name(m::ModelModule) = string(nameof(typeof(m)))
"""Module types that must also be in the spec."""
requires(::ModelModule) = ()
"""Add the module's variables, equations, data and closure entries to `mc`. Called once per model."""
extend_model!(::ModelModule, mc) = nothing
"""Fill any data the module's variables need that `mc.data` lacks (after `mc.data` is reset)."""
ensure_data!(::ModelModule, mc) = nothing
"""Set the module's closure for `phase` (:baseline or :policy)."""
set_closure!(::ModelModule, mc, phase::Symbol) = nothing
"""Undo the module's changes to core closure entries before the core model is rebuilt without it."""
detach!(::ModelModule, mc) = nothing
"""
True when two modules of one type build the same equations. By default
every field must match: a module attached with other options (such as a
different elasticity) is rebuilt rather than silently reused.
"""
same_equations(a::ModelModule, b::ModelModule) = typeof(a) == typeof(b) && all(f -> isequal(getfield(a, f), getfield(b, f)), fieldnames(typeof(a)))
"""Module types that must not be in the same spec."""
conflicts(::ModelModule) = ()
"""Core equation blocks the module deletes and replaces. Two modules in one spec may not replace the same block."""
replaces(::ModelModule) = ()
"""True for a module that replaces core equations: switching it off rebuilds the core model."""
structural(::ModelModule) = false
before_solve!(::ModelModule, mc, year, run) = nothing
after_solve!(::ModelModule, mc, year, run) = nothing

struct ModelSpec
    modules::Vector{ModelModule}
    function ModelSpec(modules::ModelModule...)
        ms = collect(ModelModule, modules)
        types = map(typeof, ms)
        length(unique(types)) == length(types) || error("each module can appear once")
        for m in ms, T in requires(m)
            any(x -> x isa T, ms) || error("$(module_name(m)) needs $(nameof(T)) in the same spec")
        end
        for m in ms, T in conflicts(m)
            any(x -> x isa T, ms) && error("$(module_name(m)) cannot be combined with $(nameof(T))")
        end
        for (i, a) in enumerate(ms), b in ms[i+1:end]
            both = intersect(replaces(a), replaces(b))
            isempty(both) || error("$(module_name(a)) and $(module_name(b)) both replace $(join(both, ", "))")
        end
        new(ms)
    end
end

has_module(spec::ModelSpec, T::Type) = any(m -> m isa T, spec.modules)
get_module(spec::ModelSpec, T::Type) = only(filter(m -> m isa T, spec.modules))
describe(spec::ModelSpec) = isempty(spec.modules) ? "static GTAP" : join(module_name.(spec.modules), " + ")
Base.show(io::IO, spec::ModelSpec) = print(io, "ModelSpec(", describe(spec), ")")

# Modules attached to a model are listed in its parameters, so the list
# travels with deepcopy(mc) and a run can switch off those its spec leaves
# out. rebuild_model! drops module equations but not this list: delete
# mc.parameters["attached_modules"] after calling it yourself.
const _MODULES_KEY = "attached_modules"

"""Attach every module in `spec` to `mc`: add its equations once. Returns `mc`."""
function attach!(spec::ModelSpec, mc)
    list = get!(mc.parameters, _MODULES_KEY, ModelModule[])
    for m in spec.modules
        any(x -> typeof(x) == typeof(m), list) && continue
        extend_model!(m, mc)
        push!(list, m)
    end
    return mc
end

attached(mc) = get(mc.parameters, _MODULES_KEY, ModelModule[])

# Rebuild the core model, dropping every module's equations and closure
# entries. Solver output settings carry over.
function _rebuild_core!(mc)
    level = try
        get_attribute(mc.model, "print_level")
    catch
        nothing
    end
    rebuild_model!(mc)
    level === nothing || set_attribute(mc.model, "print_level", level)
    names_now = Set(string.(keys(object_dictionary(mc.model))))
    for k in collect(keys(mc.fixed))
        k in names_now || delete!(mc.fixed, k)
    end
    for k in collect(keys(mc.lower))
        k in names_now || delete!(mc.lower, k)
    end
    delete!(mc.parameters, _MODULES_KEY)
    return mc
end

function _prepare!(spec::ModelSpec, mc, phase::Symbol)
    # A structural module cannot be switched off in place, and a module
    # attached with other options has the wrong equations: rebuild.
    stale(m) = has_module(spec, typeof(m)) ? !same_equations(m, get_module(spec, typeof(m))) : structural(m)
    if any(stale, attached(mc))
        # The rebuild detaches every module, so first hand core variables
        # (such as sticky wages' qe) back in their baseline closure.
        for m in attached(mc)
            set_closure!(m, mc, :baseline)
            detach!(m, mc)
        end
        _rebuild_core!(mc)
    end
    attach!(spec, mc)
    for m in attached(mc)
        ensure_data!(m, mc)
        has_module(spec, typeof(m)) || set_closure!(m, mc, :baseline)
    end
    for m in spec.modules
        set_closure!(m, mc, phase)
    end
end

"""
One run: its spec and phase, the rows of the GTAP-RD path, the solved data
by year, rows that modules report, a scratch store for modules, and the
baseline it follows (policy runs).
"""
mutable struct ModelRun
    spec::ModelSpec
    phase::Symbol
    rows::Vector{NamedTuple}
    states::Dict{Int,Dict{String,Any}}
    reports::Vector{NamedTuple}
    store::Dict{Symbol,Any}
    baseline::Union{Nothing,ModelRun}
end

ModelRun(spec, phase; baseline=nothing) = ModelRun(spec, phase, NamedTuple[], Dict{Int,Dict{String,Any}}(), NamedTuple[], Dict{Symbol,Any}(), baseline)

"""Solved data of the reference run in `year`: the baseline for a policy run, else the run itself."""
reference_state(run::ModelRun, year) = (run.baseline === nothing ? run : run.baseline).states[year]

# ---------------------------------------------------------------------------
# GTAP-RD as a module

"""
GTAP-RD recursive dynamics (GTAP-RD/GTAPRD.jl): capital accumulation,
resource supply curves, and labour efficiency hitting GDP targets in the
baseline. In a policy run labour efficiency is held at its baseline values,
GTAP-RD's policy closure.
"""
struct GtapRD <: ModelModule
    supply::Union{Nothing,ResourceSupply}
    depreciation::Union{Nothing,Float64}
    drivers::BaselineDrivers
end
GtapRD(; supply=GTAPRD_SUPPLY, depreciation=nothing, drivers=BaselineDrivers()) = GtapRD(supply, depreciation === nothing ? nothing : Float64(depreciation), drivers)

# GtapRD adds no equations; its options act through run_path!.
same_equations(::GtapRD, ::GtapRD) = true

function before_solve!(::GtapRD, mc, year, run::ModelRun)
    run.phase == :policy || return
    ref = run.baseline.states[year]
    mc.data["afe"] = deepcopy(ref["afe"])
    # Start land and natural resources at their baseline supply. Their supply
    # curves are solved to a tolerance, so without this a policy run with no
    # shock would land a little off the baseline.
    haskey(ref, "qesf") && (mc.data["qesf"] = deepcopy(ref["qesf"]))
    mobile_or_sluggish = Set(string.(get(mc.sets, "endwms", String[])))
    for e in land_endowments(mc), r in string.(collect(mc.sets["reg"]))
        e in mobile_or_sluggish || continue
        mc.data["qe"][e, r] = ref["qe"][e, r]
    end
end

# ---------------------------------------------------------------------------
# Runs

"""
Solve the static model once from `base` after `shock!(mc)`. Modules other
than GtapRD act as in the first year of a policy run against an unchanged
baseline.

A shock that does not solve in one go is applied in `steps` equal steps, each
solve starting from the last, like GEMPACK's multi-step solutions (Harrison
and Pearson 1996, Computational Economics 9, 83-127). The steps move every
data entry the shock changed in a straight line from its base value.
"""
function run_static!(spec::ModelSpec, mc, base; shock! = nothing, max_iter=200, steps=4)
    has_module(spec, GtapRD) && error("$(describe(spec)) is dynamic: use run_baseline! and run_policy!")
    _prepare!(spec, mc, :policy)
    reference = ModelRun(spec, :baseline)
    reference.states[0] = deepcopy(base)
    run = ModelRun(spec, :policy; baseline=reference)
    mc.data = deepcopy(base)
    foreach(m -> ensure_data!(m, mc), attached(mc))
    for m in spec.modules
        before_solve!(m, mc, 0, run)
    end
    start = deepcopy(mc.data)
    shock! === nothing || shock!(mc)
    _try_solve!(mc; max_iter=max_iter, retry=false) || _solve_in_steps!(mc, start, steps; max_iter=max_iter) ||
        error("static solve failed")
    run.states[0] = deepcopy(mc.data)
    for m in spec.modules
        after_solve!(m, mc, 0, run)
    end
    return run
end

function _run_dynamic!(spec, mc, base, run; periods, base_year, apply_shock, gdp_target, after_period, max_iter)
    rd = get_module(spec, GtapRD)
    run.states[base_year] = deepcopy(mc.data)
    shock = function (m, year)
        for x in spec.modules
            before_solve!(x, m, year, run)
        end
        apply_shock === nothing || apply_shock(m, year)
    end
    after = function (m, year, rows)
        run.states[year] = deepcopy(m.data)
        for x in spec.modules
            after_solve!(x, m, year, run)
        end
        after_period === nothing || after_period(m, year, rows)
    end
    run.rows = run_path!(mc, base; periods=periods, base_year=base_year, drivers=rd.drivers,
        apply_shock=shock, gdp_target=gdp_target, after_period=after,
        depreciation=rd.depreciation, supply=rd.supply, max_iter=max_iter)
    return run
end

"""
Baseline path from the current state of `mc` (normally `base`, the calibrated
data). `apply_shock(mc, year)` sets the year's drivers; `gdp_target(region,
year)` makes labour efficiency hit real GDP as in GTAP-RD.
"""
function run_baseline!(spec::ModelSpec, mc, base; periods, base_year=2017, apply_shock=nothing, gdp_target=nothing, after_period=nothing, max_iter=80)
    has_module(spec, GtapRD) || error("a baseline path needs GtapRD in the spec")
    _prepare!(spec, mc, :baseline)
    run = ModelRun(spec, :baseline)
    return _run_dynamic!(spec, mc, base, run; periods, base_year, apply_shock, gdp_target, after_period, max_iter)
end

"""
Policy path over the baseline's years, starting from its first state.
`apply_shock(mc, year)` sets drivers and policy shocks; it runs after the
modules, so it can change anything they set.
"""
function run_policy!(spec::ModelSpec, mc, base, baseline::ModelRun; apply_shock=nothing, after_period=nothing, max_iter=80)
    has_module(spec, GtapRD) || error("a policy path needs GtapRD in the spec")
    # A structural module changes the model itself, so the policy run must
    # have the same ones as its baseline.
    shape(sp) = sort([module_name(m) for m in sp.modules if structural(m)])
    shape(spec) == shape(baseline.spec) ||
        error("policy spec $(describe(spec)) and baseline spec $(describe(baseline.spec)) differ in structural modules; solve a baseline with the same ones")
    # "Policy with no shock = baseline" needs the same GTAP-RD options.
    rd, rd0 = get_module(spec, GtapRD), get_module(baseline.spec, GtapRD)
    (rd.supply, rd.depreciation, rd.drivers) == (rd0.supply, rd0.depreciation, rd0.drivers) ||
        error("policy GtapRD options (supply, depreciation, drivers) differ from the baseline's; use the baseline's GtapRD")
    years = sort(collect(keys(baseline.states)))
    mc.data = deepcopy(baseline.states[first(years)])
    _prepare!(spec, mc, :policy)
    run = ModelRun(spec, :policy; baseline=baseline)
    return _run_dynamic!(spec, mc, base, run; periods=length(years) - 1, base_year=first(years),
        apply_shock, gdp_target=nothing, after_period, max_iter)
end

include(joinpath(@__DIR__, "sticky-wages", "sticky_wages.jl"))
include(joinpath(@__DIR__, "gtap-e", "gtap_e.jl"))
include(joinpath(@__DIR__, "industry-capital", "industry_capital.jl"))
