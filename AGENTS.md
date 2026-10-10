## Cursor Cloud specific instructions

This repository is a Julia library (`GlobalTradeAnalysisProjectModelV7`) that builds and solves the GTAP version 7 computable general equilibrium model in-process with JuMP and Ipopt. There is no web server, database, or other process to start, and no application environment variables.

- `julia` on `PATH` is 1.11 (the newest stable version in `.github/workflows/CI.yml`). Run package commands with `julia --project=.`.
- Refresh dependencies with `julia --project=. -e 'using Pkg; Pkg.instantiate()'`. There is no committed root `Manifest.toml` (it is gitignored); resolution comes from `Project.toml`. Ipopt is the `Ipopt_jll` artifact, so do not install a system Ipopt.
- Tests: `julia --project=. -e 'using Pkg; Pkg.test()'`, same as `julia-actions/julia-runtest` in CI. `test/runtests.jl` is an empty `@testset`, so a passing run does not solve the model. No linter or formatter is configured.
- The working end-to-end check is the sample in `README.md`: `get_sample_data()`, `generate_initial_model`, calibrate with `run_model!`, `rebuild_model!`, shock `tms`, then `calculate_expenditure` and `calculate_gdp`. Sample data is `src/assets/example.jld2`. Full GTAP HAR files are not in the repo. `run_model!` throws `"Not solved!"` unless Ipopt returns a feasible solution (`termination_status` `LOCALLY_SOLVED`).
- Building the initial model prints several small Ipopt logs before the main calibration and scenario solves. That output is expected.
- Docs are optional and use a separate environment (`docs/Project.toml`). `docs/make.jl` calls `deploydocs` and will try to push `gh-pages`.
