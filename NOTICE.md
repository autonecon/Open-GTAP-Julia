# Notice

This repository is a fork of [GlobalTradeAnalysisProjectModelV7.jl](https://github.com/mivanic/GlobalTradeAnalysisProjectModelV7.jl), Copyright (c) 2025 Maros Ivanic, released under the MIT licence (see `LICENSE`).

## Changes to the upstream package

Two files in `src/` were changed to add GTAP's factor-augmenting technical change `afe[endw, acts, reg]` to the value-added nest:

- `src/build_model!.jl`: the variable `afe`, its use in the factor demand equation `e_qfe` (`qfe·afe` at the effective price `pfe/afe`), and default values for model containers saved without it.
- `src/generate_starting_values.jl`: `afe` starts at 1 and is fixed, so a base solve is unchanged.

Nothing else in `src/` was changed.

## Added

Everything in `GTAP-RD/`, `GTAP-modules/`, `checks/` and the code and README in `SSP/` is new, Copyright (c) 2026 Matra contributors, under the same MIT licence. `checks/prepare_for_solve.jl` comes from the OCGE Data Base build.

`SSP/ocge_region_indexes.csv` and `SSP/notes.txt` are data derived from IIASA, OECD, World Bank and United Nations sources, not covered by the MIT licence. Their sources, licences and citations are in [`SSP/README.md`](SSP/README.md).

## Models implemented

The extensions are independent implementations of published models. They contain no GEMPACK code from those models. Please cite the original work when you use them:

- GTAP-RD: Aguiar, A., Corong, E. and van der Mensbrugghe, D. (2019), *The GTAP Recursive Dynamic (GTAP-RD) Model: Version 1.0*, Center for Global Trade Analysis, Purdue University.
- GTAP-E: Burniaux, J.-M. and Truong, T. P. (2002), *GTAP-E: An Energy-Environmental Version of the GTAP Model*, GTAP Technical Paper 16; McDougall, R. and Golub, A. (2007), *GTAP-E: A Revised Energy-Environmental Version of the GTAP Model*, GTAP Research Memorandum 15.
- Sticky wages: Dixon, P. B. and Rimmer, M. T. (2002), *Dynamic General Equilibrium Modelling for Forecasting and Policy: A Practical Guide and Documentation of MONASH*, North-Holland.
- Industry-specific capital and sticky wages as used in GTAP-MVH: Dixon, P. B., Rimmer, M. T. and Tran, N. (2019), *GTAP-MVH, a model for analysing the worldwide effects of trade policies in the motor vehicle sector: theory and data*, CoPS Working Paper G-290, Centre of Policy Studies, Victoria University, Melbourne.
- Multi-step solutions: Harrison, W. J. and Pearson, K. R. (1996), Computing solutions for large general equilibrium models using GEMPACK, *Computational Economics* 9, 83–127.

"GTAP" is the name of the Global Trade Analysis Project at Purdue University. This repository is not affiliated with or endorsed by it.
