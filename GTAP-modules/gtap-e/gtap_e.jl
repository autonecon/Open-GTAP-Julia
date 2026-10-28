# Energy substitution in production, after GTAP-E (Burniaux and Truong 2002,
# GTAP Technical Paper 16; McDougall and Golub 2007).
#
# Standard GTAP puts energy with the other intermediate inputs, so firms use
# it in fixed proportion to output (ESUBC is 0). GTAP-E takes energy out of
# the intermediate nest and nests it with capital:
#
#   output                        CES(ESUBT)
#   ├─ non-energy intermediates   CES(ESUBC)   (qint, pint)
#   └─ value added and energy     CES(ESUBVA)  (qva, pva)
#      ├─ land, labour, natural resources
#      └─ capital-energy          CES(ELKE)    (ge_qkef)
#         ├─ capital
#         └─ energy               CES(ELEN)    (ge_qen)
#            ├─ electricity
#            └─ non-electric      CES(ELNEL)   (ge_qnel)
#               ├─ coal
#               └─ non-coal       CES(ELNCOAL) (ge_qncoal)
#                  └─ oil, gas, petroleum products
#
# Each energy input then splits into domestic and imported as in the core
# model. With the module on, qint/pint are the non-energy intermediate
# composite and qva/pva the value-added-and-energy composite.
#
# The nests are written in calibrated-share form against the base solution
# saved when the module is attached, so the module needs no calibration step:
#
#   x_i a_i / (x̄_i ā_i) = (Q / Q̄) ((P / P̄) / ((p_i / a_i) / (p̄_i / ā_i)))^σ
#   (P / P̄)^(1-σ) = Σ s_i ((p_i / a_i) / (p̄_i / ā_i))^(1-σ)   (Cobb-Douglas form at σ = 1)
#
# with s_i the base value shares, so P Q = Σ p_i x_i holds.
#
# where a_i is factor-augmenting technical change (afe) for primary factors
# and 1 for other inputs. All shares come from the loaded dataset; only the
# energy commodity names and the elasticities are set here.
#
# The module changes the model's structure, so switching it off rebuilds the
# core model (see `structural` in GTAPModules.jl).

const _GE_CORE_EQUATIONS = (:e_qintva, :e_qo, :e_qfa, :e_pint, :e_qfe, :e_pva)
# The core's Hicks-neutral productivity shifters of the nests GTAP-E rewrites
# (Q = γ f(x)): γ_qintva on output, γ_qfa on non-energy intermediates and
# γ_qfe on value added (with energy, under GTAP-E). GTAP-E keeps them.
const _GE_SHIFTERS = ("γ_qintva", "γ_qfa", "γ_qfe")

struct GtapE <: ModelModule
    coal::Vector{String}
    noncoal::Vector{String}
    electricity::Vector{String}
    elke::Dict{String,Float64}
    elen::Dict{String,Float64}
    elnel::Dict{String,Float64}
    elncoal::Dict{String,Float64}
end

"""
    GtapE(; coal, noncoal, electricity, elke=0.5, elen=1.0, elnel=0.5, elncoal=1.0, no_ke=String[], fixed_energy=nothing, elke_fixed=0.0)

Energy commodities are named by the dataset's own commodity codes, so a new
aggregation needs only a new mapping. Elasticities are GTAP-E's defaults
(Burniaux and Truong 2002): a number applies to every activity, a Dict sets
activities one by one (missing activities take the default).
`fixed_energy` activities (default: those producing coal, oil, gas or
petroleum products, whose energy inputs are largely feedstock) have all four
energy elasticities at 0, as in GTAP-E. `no_ke` activities have ELKE at 0
(GTAP-E does this for agriculture, forestry and fishing). `elke_fixed` sets
ELKE for both groups instead of 0 (their other energy elasticities stay 0).
The zeros are a modelling simplification; published estimates (Koetse, de
Groot and Florax 2008; Okagawa and Ban 2008) support a small positive value,
such as 0.1. With industry-specific capital a zero
ELKE can leave the model without a solution (petroleum refining, whose
capital then fixes its crude feedstock), so IndustryCapital requires
`elke_fixed > 0`.
"""
function GtapE(; coal, noncoal, electricity, elke=0.5, elen=1.0, elnel=0.5, elncoal=1.0,
    no_ke=String[], fixed_energy=nothing, elke_fixed=0.0)
    fixed = fixed_energy === nothing ? vcat(coal, noncoal) : fixed_energy
    function table(v, zero_for, value=0.0)
        d = v isa AbstractDict ? Dict{String,Float64}(string(k) => Float64(x) for (k, x) in v) : Dict{String,Float64}("*" => Float64(v))
        haskey(d, "*") || (d["*"] = v isa AbstractDict ? 0.0 : Float64(v))
        for a in zero_for
            d[string(a)] = value
        end
        return d
    end
    GtapE(string.(coal), string.(noncoal), string.(electricity),
        table(elke, vcat(fixed, no_ke), Float64(elke_fixed)), table(elen, fixed), table(elnel, fixed), table(elncoal, fixed))
end

structural(::GtapE) = true
replaces(::GtapE) = _GE_CORE_EQUATIONS
_ge_sigma(d::Dict{String,Float64}, a) = get(d, a, d["*"])
energy_commodities(ge::GtapE) = vcat(ge.coal, ge.noncoal, ge.electricity)

const _GE_COMPOSITES = ("kef", "en", "nel", "ncoal")
const _GE_REF = "gtape_reference"

_ge_num(x) = (x isa Number && isfinite(Float64(x))) ? Float64(x) : NaN
_ge_valid(m, v) = is_valid(m, v)

function _ge_delete_all!(m, c)
    if c isa ConstraintRef
        is_valid(m, c) && delete(m, c)
    else
        for x in (c isa AbstractDict ? values(c) : c)
            _ge_delete_all!(m, x)
        end
    end
end

# The nest tree of activity a in region r, from the inputs the model has.
# Each nest is (name, components, sigma); a component is (:comm, c),
# (:endw, e) or (:nest, name).
function _ge_tree(ge::GtapE, mc, a, r)
    m = mc.model
    comm = string.(collect(mc.sets["comm"]))
    endw = string.(collect(mc.sets["endw"]))
    capital = Set(string.(mc.sets["endwc"]))
    energy = Set(energy_commodities(ge))
    has_c(c) = c in comm && _ge_valid(m, m[:qfa][c, a, r])
    has_e(e) = _ge_valid(m, m[:qfe][e, a, r])
    p = mc.parameters
    nests = Dict{String,Tuple{Vector{Tuple{Symbol,String}},Float64}}()
    add!(name, comps, σ) = isempty(comps) ? false : (nests[name] = (comps, σ); true)
    ncoal = add!("ncoal", [(:comm, c) for c in ge.noncoal if has_c(c)], _ge_sigma(ge.elncoal, a))
    nel = add!("nel", vcat([(:comm, c) for c in ge.coal if has_c(c)], ncoal ? [(:nest, "ncoal")] : []), _ge_sigma(ge.elnel, a))
    en = add!("en", vcat([(:comm, c) for c in ge.electricity if has_c(c)], nel ? [(:nest, "nel")] : []), _ge_sigma(ge.elen, a))
    kef = add!("kef", vcat([(:endw, e) for e in endw if e in capital && has_e(e)], en ? [(:nest, "en")] : []), _ge_sigma(ge.elke, a))
    add!("va", vcat([(:endw, e) for e in endw if !(e in capital) && has_e(e)], kef ? [(:nest, "kef")] : []), Float64(p["esubva"][a, r]))
    int = add!("int", [(:comm, c) for c in comm if !(c in energy) && has_c(c)], Float64(p["esubc"][a, r]))
    add!("top", vcat(int ? [(:nest, "int")] : [], [(:nest, "va")]), Float64(p["esubt"][a, r]))
    return nests
end

# Value and base-price-weighted quantity of each component and nest in
# solution `d`, measured against the reference `ref`. In the reference both
# give the composite's base value (its price is 1).
function _ge_values(nests, d, ref, a, r)
    out = Dict{String,Tuple{Float64,Float64}}()
    function comp(kind, name)
        if kind == :comm
            x, p = _ge_num(d["qfa"][name, a, r]), _ge_num(d["pfa"][name, a, r])
            return (p * x, _ge_num(ref["pfa"][name, a, r]) * x)
        elseif kind == :endw
            x, p = _ge_num(d["qfe"][name, a, r]), _ge_num(d["pfe"][name, a, r])
            eff = _ge_num(d["afe"][name, a, r]) / _ge_num(ref["afe"][name, a, r])
            return (p * x, _ge_num(ref["pfe"][name, a, r]) * x * eff)
        end
        return nest(name)
    end
    function nest(name)
        haskey(out, name) && return out[name]
        v, q = 0.0, 0.0
        for (k, n) in nests[name][1]
            cv, cq = comp(k, n)
            v += cv
            q += cq
        end
        out[name] = (v, q)
    end
    for name in keys(nests)
        name == "top" || nest(name)
    end
    return out
end

function extend_model!(ge::GtapE, mc)
    m = mc.model
    haskey(object_dictionary(m), :ge_qkef) && error("the model already has GTAP-E equations")
    comm = string.(collect(mc.sets["comm"]))
    for c in energy_commodities(ge)
        c in comm || error("GTAP-E energy commodity $c is not in the model's commodities: $(join(comm, ", "))")
    end
    acts = string.(collect(mc.sets["acts"]))
    regs = string.(collect(mc.sets["reg"]))

    # The base the nests are calibrated to: the solution in mc.data the first
    # time the module is attached (attach it to the calibrated base). It is
    # kept when the module is switched off and on again.
    ref = get!(mc.parameters, _GE_REF) do
        Dict(k => deepcopy(mc.data[k]) for k in ("qfa", "pfa", "qfe", "pfe", "afe", "qo", "po"))
    end
    # Base values of the core's nest productivity shifters (kept in GTAP-E).
    for k in _GE_SHIFTERS
        haskey(ref, k) || (ref[k] = deepcopy(mc.data[k]))
    end

    for k in _GE_CORE_EQUATIONS
        _ge_delete_all!(m, m[k])
        unregister(m, k)
    end

    vars = Dict{String,Any}()
    for n in _GE_COMPOSITES
        vars["q"*n] = @variable(m, [acts, regs], base_name = "ge_q" * n)
        vars["p"*n] = @variable(m, [acts, regs], base_name = "ge_p" * n)
        m[Symbol("ge_q" * n)] = vars["q"*n]
        m[Symbol("ge_p" * n)] = vars["p"*n]
    end
    qfa, pfa, qfe, pfe, afe = m[:qfa], m[:pfa], m[:qfe], m[:pfe], m[:afe]
    qo, po, qint, pint, qva, pva = m[:qo], m[:po], m[:qint], m[:pint], m[:qva], m[:pva]
    cons = ConstraintRef[]
    trees = Dict{Tuple{String,String},Any}()
    for a in acts, r in regs
        _ge_valid(m, qo[a, r]) || continue
        nests = _ge_tree(ge, mc, a, r)
        trees[(a, r)] = nests
        base = _ge_values(nests, ref, ref, a, r)
        # Output quantity and price of each nest, and base values.
        function outvars(name)
            name == "top" && return (qo[a, r], po[a, r], _ge_num(ref["qo"][a, r]), _ge_num(ref["po"][a, r]))
            name == "int" && return (qint[a, r], pint[a, r], base[name][1], 1.0)
            name == "va" && return (qva[a, r], pva[a, r], base[name][1], 1.0)
            return (vars["q"*name][a, r], vars["p"*name][a, r], base[name][1], 1.0)
        end
        function compvars(kind, name)
            kind == :comm && return (qfa[name, a, r], pfa[name, a, r], nothing,
                _ge_num(ref["qfa"][name, a, r]), _ge_num(ref["pfa"][name, a, r]), 1.0)
            kind == :endw && return (qfe[name, a, r], pfe[name, a, r], afe[name, a, r],
                _ge_num(ref["qfe"][name, a, r]), _ge_num(ref["pfe"][name, a, r]), _ge_num(ref["afe"][name, a, r]))
            Q, P, Qb, Pb = outvars(name)
            return (Q, P, nothing, Qb, Pb, 1.0)
        end
        # Nest productivity γ (Q = γ f(x), unit cost P = c(p) / γ): demands
        # follow Q / γ and the unit cost is P γ.
        function shifter(name)
            k = name == "top" ? "γ_qintva" : name == "int" ? "γ_qfa" : name == "va" ? "γ_qfe" : nothing
            k === nothing && return (nothing, 1.0)
            v = m[Symbol(k)][a, r]
            _ge_valid(m, v) || return (nothing, 1.0)
            return (v, _ge_num(ref[k][a, r]))
        end
        for (name, (comps, σ)) in nests
            Q, P, Qb, Pb = outvars(name)
            g, gb = shifter(name)
            lQ = g === nothing ? log(Q) : log(Q) - log(g)
            lP = g === nothing ? log(P) : log(P) + log(g)
            lQb, lPb = log(Qb) - log(gb), log(Pb) + log(gb)
            parts = [compvars(k, n) for (k, n) in comps]
            for (x, p, eff, xb, pb, ab) in parts
                if eff === nothing
                    push!(cons, @constraint(m, log(x) - lQ - σ * (lP - log(p)) ==
                                               log(xb) - lQb + σ * (log(pb) - lPb)))
                else
                    push!(cons, @constraint(m, log(x) + log(eff) - lQ - σ * (lP - log(p) + log(eff)) ==
                                               log(xb) + log(ab) - lQb + σ * (log(pb) - lPb - log(ab))))
                end
            end
            # Price of the composite: the CES unit cost, with base value shares.
            # (With the value identity instead, a Cobb-Douglas nest would pin
            # only P*Q and leave the system singular.)
            vb = [pb * xb for (_, _, _, xb, pb, _) in parts]
            sh = vb ./ sum(vb)
            rel(p, eff, pb, ab) = eff === nothing ? p / pb : p / eff / (pb / ab)
            if σ == 1
                push!(cons, @constraint(m, lP - lPb == sum(sh[i] * log(rel(p, eff, pb, ab)) for (i, (_, p, eff, _, pb, ab)) in enumerate(parts))))
            else
                push!(cons, @constraint(m, (1 - σ) * (lP - lPb) == log(sum(sh[i] * rel(p, eff, pb, ab)^(1 - σ) for (i, (_, p, eff, _, pb, ab)) in enumerate(parts)))))
            end
        end
        # No intermediate composite: drop qint and pint, as the core model does.
        haskey(nests, "int") || (delete(m, qint[a, r]); delete(m, pint[a, r]))
    end
    # Drop composites an activity does not have.
    for n in _GE_COMPOSITES, a in acts, r in regs
        if !haskey(trees, (a, r)) || !haskey(trees[(a, r)], n)
            delete(m, vars["q"*n][a, r])
            delete(m, vars["p"*n][a, r])
        end
    end
    m[:e_gtape] = cons
    mc.parameters["gtape_trees"] = trees
    for n in _GE_COMPOSITES
        mc.lower["ge_q"*n] = 1e-14
        mc.lower["ge_p"*n] = 1e-8
        mc.fixed["ge_q"*n] = NamedArray(falses(length(acts), length(regs)), (acts, regs))
        mc.fixed["ge_p"*n] = NamedArray(falses(length(acts), length(regs)), (acts, regs))
    end
    delete!(mc.data, "ge_qkef")
    ensure_data!(ge, mc)
    return nothing
end

# Starting values for the composites (and for qint, pint, qva, pva in their
# GTAP-E meaning) from the current solution, when they are missing.
function ensure_data!(ge::GtapE, mc)
    haskey(mc.data, "ge_qkef") && return nothing
    ref = mc.parameters[_GE_REF]
    acts = string.(collect(mc.sets["acts"]))
    regs = string.(collect(mc.sets["reg"]))
    blank() = NamedArray(fill(NaN, length(acts), length(regs)), (acts, regs))
    out = Dict(k => blank() for k in vcat(["ge_q" * n for n in _GE_COMPOSITES], ["ge_p" * n for n in _GE_COMPOSITES]))
    for ((a, r), nests) in mc.parameters["gtape_trees"]
        vals = _ge_values(nests, mc.data, ref, a, r)
        for (name, (v, q)) in vals
            qk, pk = name == "int" ? ("qint", "pint") : name == "va" ? ("qva", "pva") : ("ge_q" * name, "ge_p" * name)
            target = startswith(qk, "ge_") ? out : mc.data
            target[qk][a, r] = q
            target[pk][a, r] = v / q
        end
    end
    merge!(mc.data, out)
    return nothing
end

"""Energy input use by activity, % change between two solutions, with the composites."""
function energy_report(ge::GtapE, mc, base, d; regions=nothing)
    rows = NamedTuple[]
    regs = regions === nothing ? string.(collect(mc.sets["reg"])) : regions
    for ((a, r), nests) in mc.parameters["gtape_trees"]
        r in regs || continue
        for c in energy_commodities(ge)
            x0, x1 = _ge_num(base["qfa"][c, a, r]), _ge_num(d["qfa"][c, a, r])
            isfinite(x0) && x0 > 0 || continue
            push!(rows, (region=r, activity=a, input=c, pct=100 * (x1 / x0 - 1)))
        end
    end
    return rows
end
