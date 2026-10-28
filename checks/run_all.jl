# Runs every check in its own Julia process (each calibrates its own model).
#   OCGE_DATA=<folder> julia --project=checks checks/run_all.jl
const SCRIPTS = ["check_gtap_rd.jl", "check_ssp.jl", "check_modules.jl", "check_stepped_period.jl", "check_gtap_e.jl", "check_industry_capital.jl"]
julia = Base.julia_cmd()
project = @__DIR__
failed = String[]
for s in SCRIPTS
    println("== ", s)
    ok = success(pipeline(`$julia --project=$project $(joinpath(@__DIR__, s))`; stdout=stdout, stderr=stderr))
    ok || push!(failed, s)
end
isempty(failed) ? println("All checks pass") : error("failed: " * join(failed, ", "))
