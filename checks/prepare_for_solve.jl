# From the OCGE Data Base build; keep in step with its copy there.
# Model-run preparation of an aggregated data base for GlobalTradeAnalysisProjectModelV7 (levels form).
#
# The Julia port writes each Armington nest as log(q_dom), log(q_imp) .== log(ces(...)) for every agent with
# purchases of the composite, so an agent that buys a commodity only from domestic producers or only from
# imports gives log(0) and Ipopt stops on an invalid number. GEMPACK's linear form has no such problem, and
# the GTAP data base has no such cells (every firm cell is either zero or positive on both sides). This data base keeps the structural zeros of the source tables, so an
# aggregation can have such cells.
#
# armington_swap! gives each such agent a small amount of the missing side by swapping it with the agent
# of the same commodity and region that buys most of the missing side: agent i gives eps of its only side and takes eps of the
# other; donor k does the opposite. Region totals of domestic and imported purchases at basic prices are
# unchanged (market clearing holds), and so is each agent's total at basic and at purchasers' prices. Each agent
# moves both sides at its own power on that side, so tax revenue is unchanged too (measured at 1.5e-11 on a
# small test map); the donor's average powers shift by at most a few 1e-7. eps is SHARE times the agent's purchases, at most half of what the donor holds.
# The data base itself is not changed: this runs on the aggregated copy in memory.
using NamedArrays

const SHARE = 1e-6

function armington_swap!(hData)
    agents = Tuple{String,String,Union{Nothing,String}}[]
    acts = names(hData["vdfb"], 2)
    for a in acts
        push!(agents, ("vdf", "vmf", a))
    end
    push!(agents, ("vdp", "vmp", nothing), ("vdg", "vmg", nothing), ("vdi", "vmi", nothing))
    comm = names(hData["vdfb"], 1)
    reg = names(hData["vdfb"], 3)
    get(k, a, c, r) = a === nothing ? hData[k][c, r] : hData[k][c, a, r]
    function add!(k, a, c, r, v)
        if a === nothing
            hData[k][c, r] += v
        else
            hData[k][c, a, r] += v
        end
    end
    n = 0
    moved = 0.0
    for r in reg, c in comm
        for (d, m, a) in agents
            db, mb = get(d * "b", a, c, r), get(m * "b", a, c, r)
            (db > 0) == (mb > 0) && continue
            only, other = db > 0 ? (d, m) : (m, d)
            total = db + mb
            power = get(only * "p", a, c, r) / get(only * "b", a, c, r)
            # donor: the agent with the most of the missing side
            best, bestv = nothing, 0.0
            for (d2, m2, a2) in agents
                (d2, a2) == (d, a) && continue
                v = get((other == d ? d2 : m2) * "b", a2, c, r)
                if v > bestv
                    best, bestv = (d2, m2, a2), v
                end
            end
            # A region with no purchases of the missing side at all (332 commodity-region pairs in the full data base,
            # e.g. coa in ARE: no domestic output) has no donor; a map that keeps such a pair needs it pooled.
            best === nothing && error("no donor for $c in $r: the region has no $(other == d ? "domestic" : "imported") purchases of $c by any agent; pool $c or $r on this map")
            (d2, m2, a2) = best
            o2, s2 = other == d ? (d2, m2) : (m2, d2)
            eps = min(SHARE * total, 0.5 * bestv)
            p2 = get(o2 * "p", a2, c, r) / get(o2 * "b", a2, c, r)
            add!(only * "b", a, c, r, -eps); add!(only * "p", a, c, r, -eps * power)
            add!(other * "b", a, c, r, eps); add!(other * "p", a, c, r, eps * power)
            add!(o2 * "b", a2, c, r, -eps); add!(o2 * "p", a2, c, r, -eps * p2)
            add!(s2 * "b", a2, c, r, eps); add!(s2 * "p", a2, c, r, eps * p2)
            n += 1
            moved += eps
        end
    end
    return n, moved
end
