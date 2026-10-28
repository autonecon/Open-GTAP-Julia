# GTAP-E energy substitution (experimental)

`GtapE` lets firms substitute between energy types and between energy and capital, following GTAP-E (Burniaux and Truong 2002; McDougall and Golub 2007). Standard GTAP treats energy as an ordinary intermediate input in fixed proportions to output. Status: experimental. It covers firms only.

Open items before it can be called complete:

- Households and government have no energy nest yet (GTAP-E has one).
- The fossil producers' value-added-and-energy nest uses ESUBVA, not GTAP-E's calibrated ELFVAEN.
- There are no carbon accounts or carbon taxes.

## Turn it on or off

```julia
include("GTAP-modules/GTAPModules.jl")      # loads this module too

ge = GtapE(coal=["coal"], noncoal=["oil", "gas", "petro"], electricity=["ely"])
spec = ModelSpec(GtapRD(), ge)              # on, in a dynamic run
spec = ModelSpec(ge)                        # on, in a static solve
spec = ModelSpec(GtapRD())                  # off
```

Name the energy commodities with your aggregation's own codes. GTAP-E changes the model's structure: switching it off rebuilds the core model, and a policy run must use it if and only if its baseline did (the framework refuses a mismatch). Attach it to the calibrated base, because its shares are calibrated from the solution in `mc.data` when it is first attached.

| Option | Default | Meaning |
| --- | --- | --- |
| `coal`, `noncoal`, `electricity` | required | Commodity codes in each energy group |
| `elke` | 0.5 | Capital–energy substitution (ELKE) |
| `elen` | 1.0 | Electricity against non-electric energy (ELEN) |
| `elnel` | 0.5 | Coal against non-coal (ELNEL) |
| `elncoal` | 1.0 | Among oil, gas and petroleum products (ELNCOAL) |
| `fixed_energy` | coal and non-coal producers | Activities with all four elasticities at 0, because their energy inputs are mostly feedstock (as in GTAP-E) |
| `no_ke` | none | Activities with ELKE at 0 (GTAP-E does this for agriculture, forestry and fishing) |
| `elke_fixed` | 0.0 | ELKE for the two groups above instead of 0. Needed above 0 when combined with industry-specific capital |

An elasticity can be a number for every activity or a `Dict` by activity. The defaults are GTAP-E's.

## What it does

Energy leaves the intermediate nest and joins capital:

```
output                       CES(ESUBT)
├─ non-energy intermediates  CES(ESUBC)
└─ value added and energy    CES(ESUBVA)
   ├─ land, labour, natural resources
   └─ capital-energy         CES(ELKE)
      ├─ capital
      └─ energy              CES(ELEN)
         ├─ electricity
         └─ non-electric     CES(ELNEL)
            ├─ coal
            └─ non-coal      CES(ELNCOAL): oil, gas, petroleum products
```

The nests are written in calibrated-share form, so the base solution is unchanged. With the module on, `qint`/`pint` are the non-energy intermediate composite and `qva`/`pva` the value-added-and-energy composite. Household and government demand are unchanged (CDE and Cobb-Douglas).

## Checks

`checks/check_gtap_e.jl`: base re-solve with the module, switching back off reproducing standard GTAP, an oil supply shock in which the world oil price rises less with GTAP-E than without (firms can substitute away from oil), and the output-level productivity shifter `γ_qintva` still acting with the module on.

## References

- Burniaux, J.-M. and Truong, T. P. (2002), *GTAP-E: An Energy-Environmental Version of the GTAP Model*, GTAP Technical Paper 16, Center for Global Trade Analysis, Purdue University.
- McDougall, R. and Golub, A. (2007), *GTAP-E: A Revised Energy-Environmental Version of the GTAP Model*, GTAP Research Memorandum 15, Center for Global Trade Analysis, Purdue University.
