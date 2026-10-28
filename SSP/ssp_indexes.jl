# SSP drivers for GTAP-RD runs on the OCGE Data Base: reads the region table
# (ocge_region_indexes.csv) and turns it into `apply_shock` and `gdp_target`
# for run_path! or run_baseline!.
#
#   idx = read_ssp_indexes(ssp="SSP2", groups=regMap)   # regMap: code => aggregated region
#   apply, target = ssp_drivers(idx, cal, labour_endowments(mc))
#   run_baseline!(ModelSpec(GtapRD()), mc, cal; periods=5, base_year=2022, apply_shock=apply, gdp_target=target)

const SSP_TABLE = joinpath(@__DIR__, "ocge_region_indexes.csv")
const SSP_SUMMABLE = ("population", "labour_force", "working_age", "gdp_mer")

"""
`(region, variable, year) => index` (1 in `base_year`) for one SSP. Without
`groups` the regions are the data base's own. With `groups` (data base code =>
aggregated region, a Dict or a NamedArray from aggregate_data's regMap) an
aggregated region's index is the sum of its members' levels over that sum in
`base_year`. GDP is gdp_mer, at market exchange rates, which is what
GTAP-RD aggregates.
"""
function read_ssp_indexes(path=SSP_TABLE; ssp="SSP2", groups=nothing, base_year=2022)
    index = Dict{Tuple{String,String,Int},Float64}()
    level = Dict{Tuple{String,String,Int},Float64}()
    for line in Iterators.drop(eachline(path), 1)
        f = split(line, ',')
        f[1] == ssp || continue
        key = (String(f[2]), String(f[3]), parse(Int, f[4]))
        isempty(f[5]) || (index[key] = parse(Float64, f[5]))
        isempty(f[6]) || (level[key] = parse(Float64, f[6]))
    end
    isempty(index) && error("no rows for $ssp in $path")
    groups === nothing && return index
    label(c) = String(groups[c])
    years = sort(unique(k[3] for k in keys(level)))
    out = Dict{Tuple{String,String,Int},Float64}()
    codes = unique(k[1] for k in keys(level))
    for v in SSP_SUMMABLE, g in unique(label(c) for c in codes)
        members = [c for c in codes if label(c) == g && all(y -> haskey(level, (c, v, y)), years)]
        isempty(members) && error("no member of $g has a full $v path")
        total(y) = sum(level[(c, v, y)] for c in members)
        for y in years
            out[(g, v, y)] = total(y) / total(base_year)
        end
    end
    return out
end

"""
`apply_shock(mc, year)` that sets each region's population and every labour
endowment to their base values times the SSP population and labour-force
indexes, and `gdp_target(region, year)` from the gdp_mer index.
"""
function ssp_drivers(index, base, labour)
    function apply_shock(mc, year)
        for r in string.(collect(mc.sets["reg"]))
            mc.data["pop"][r] = Float64(base["pop"][r]) * index[(r, "population", year)]
            for e in labour
                mc.data["qe"][e, r] = Float64(base["qe"][e, r]) * index[(r, "labour_force", year)]
            end
        end
    end
    gdp_target(r, year) = index[(r, "gdp_mer", year)]
    return apply_shock, gdp_target
end
