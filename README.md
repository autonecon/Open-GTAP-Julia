# Open GTAP Julia

Extensions to Maros Ivanic's [GlobalTradeAnalysisProjectModelV7.jl](https://github.com/mivanic/GlobalTradeAnalysisProjectModelV7.jl), the GTAP version 7 levels model in Julia. This repository is a fork of that package. The package itself is unchanged apart from one addition (factor-augmenting technical change, `afe`); everything else sits in its own folders beside it. The extensions are maintained by Matra contributors and are not endorsed by the GTAP Center.

| Folder | What it adds | Status |
| --- | --- | --- |
| [`GTAP-RD/`](GTAP-RD/README.md) | Recursive dynamics after GTAP-RD: capital accumulation, supply curves for land and natural resources, labour efficiency that hits a GDP path, and a stepped fallback for hard years | Reviewed and tested |
| [`GTAP-modules/`](GTAP-modules/README.md) | Choose model pieces per run, and turn each on or off | Framework reviewed and tested |
| [`GTAP-modules/sticky-wages/`](GTAP-modules/sticky-wages/README.md) | Sticky real wages (MONASH, GTAP-MVH) | Reviewed and tested |
| [`GTAP-modules/gtap-e/`](GTAP-modules/gtap-e/README.md) | GTAP-E energy substitution in production | Experimental |
| [`GTAP-modules/industry-capital/`](GTAP-modules/industry-capital/README.md) | Industry-specific capital (GTAP-MVH) | Experimental |
| [`SSP/`](SSP/README.md) | Population, labour and GDP paths to 2100 under SSP1–5 for the OCGE Data Base regions, and a loader that turns them into baseline drivers | Tested |
| [`checks/`](checks/README.md) | Checks of all of the above on the open OCGE Data Base | Run them after any change |

Data: the checks and examples use the [OCGE (Open CGE) Data Base](https://github.com/autonecon/OCGE---The-Open-CGE-Database), a GTAP-format data base for 2022 with 167 regions and 51 sectors, published under CC BY 4.0. Any GTAP-format data base works with the model.

Quick start:

```
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=checks -e "using Pkg; Pkg.instantiate()"
OCGE_DATA=<folder with the OCGE gsdfset.har, gsdfpar.har, gsdfdat.har> julia --project=checks checks/run_all.jl
```

Licence: MIT, as the upstream package. Its copyright notice is kept in [`LICENSE`](LICENSE); see [`NOTICE.md`](NOTICE.md) for what was added and changed.

The upstream package's own documentation follows.

---

# GlobalTradeAnalysisProjectModelV7

[![Build Status](https://github.com/mivanic/GlobalTradeAnalysisProjectModelV7.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/mivanic/GlobalTradeAnalysisProjectModelV7.jl/actions/workflows/CI.yml?query=branch%3Amaster)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mivanic.github.io/GlobalTradeAnalysisProjectModelV7.jl/dev/)
## Purpose of the package

The purpose of this package is to allow CGE modelers to run GTAP model version 7 in Julia, from start to finish, i.e. from data aggregation to results.

To run the GTAP version 7 model, you need to follow the following steps:

## Prerequisites

- Get GTAP sets, data and parameters prepared for version 7 of the GTAP model
    - The sets, data and parameters need to be provided as a dictionary with the correct keys matching the headers of the model file for GEMPACK in lower case. For example, the data should contain key "vfob" with a three dimensional array with the value of bilateral trade measured FOB
    - If you are interested in actual GTAP data, you may obtain a free dataset from [the GTAP Center's website](https://www.gtap.agecon.purdue.edu/)
    - To turn a Fortran-style HAR file into a Julia dictionary, you may use package [HeaderArrayFile](https://github.com/mivanic/HeaderArrayFile.jl)
    - You may either aggregate your data outside module `GlobalTradeAnalysisProjectModelV7`, e.g., by using GTAPAgg or FlexAgg programs also distributed by the GTAP Center, or you can use function `aggregate_data` in module `GlobalTradeAnalysisProjectModelV7` as explained below
- A sample aggregation of the free GTAP version 9 database is provided with the package for testing using function get_sample_data()

## Install the package

```
using Pkg
Pkg.add("GlobalTradeAnalysisProjectModelV7")
```

## Import the package

```
using GlobalTradeAnalysisProjectModelV7
```

## Aggregating the data

- To aggregate GTAP data in module `GTAPvGlobalTradeAnalysisProjectModelV77`, you can run function `aggregate_data(; hData, hParameters, hSets, comMap, regMap, endMap)` with the following arguments:
    - `hData`: a Dict object with the keys appropriate for the GTAP version 7 model data (e.g., "vfob", "evos", etc.)
    - `hParameters`: a Dict object with the keys appropriate for the GTAP version 7 model parameters (e.g., "esbq", etc.)
    - `comMap`: a Named Vector which maps original commodities to the new ones 
    - `regMap`: a Named Vector which maps original regions to the new ones
    - `endMap`: a Named Vector which maps original endowments to the new ones
        

```
# Use packages HeaderArrayFile and NamedArrays to process the initial data
using HeaderArrayFile, NamedArrays

# Load the disaggregated data (e.g., from FlexAgg)
data_har = HeaderArrayFile.File("./gsdfdat.har")
sets_har = HeaderArrayFile.File("./gsdfset.har")
parameters_har = HeaderArrayFile.File("./gsdfpar.har")

# Turn the HeaderArray format into NamedArrays inside dictionaries
data = Dict(keys(data_har) .=> NamedArray.(values(data_har)))
sets = Dict(keys(sets_har) .=> NamedArray.(values(sets_har)))
parameter = Dict(keys(parameters_har) .=> NamedArray.(values(parameters_har)))

# Aggregate the data (assuming version 11 data)

## Prepare the mapping vectors
## You can start by reading the regions, commodities and endowments from the disaggregated data and modifying them
regMap = NamedArray(deepcopy(sets["reg"]), sets["reg"])
regMap[1:3] .= "oceania"
regMap[4:27] .= "asia"
regMap[28:55] .= "americas"
regMap[56:82] .= "eu"
regMap[83:98] .= "other europe"
regMap[99:121] .= "mena"
regMap[122:160] .= "subsaharan africa"


comMap = NamedArray(deepcopy(sets["comm"]), sets["comm"])
comMap[1:8] .= "crops"
comMap[9:12] .= "animals"
comMap[13:18] .= "extract"
comMap[19:26] .= "processed food"
comMap[27:45] .= "manuf"
comMap[46:65] .= "svces"

endMap = NamedArray(deepcopy(sets["endw"]), sets["endw"])
endMap[:] .= "other"
endMap[1:1] .= "land"
endMap[[2,5]] .= "skilled labor"
endMap[[3,4,6]] .= "unskilled labor"
endMap["capital"] = "capital"

# Do the aggregation
(; hData, hParameters, hSets) = aggregate_data(hData=data, hParameters=parameters, hSets=sets, comMap=comMap, regMap=regMap, endMap=endMap)

```

# Clean the data: trade below 1e-4 (100 dollars) makes little sense

```
valid_trade = hData["vxsb"].>1e-4
for k ∈ ["vcif","vmsb","vfob","vxsb"]
    hData[k][.!valid_trade].=0
end
for k ∈ ["vtwr"]
    for m ∈ hSets["marg"]
        for c ∈ hSets["comm"]
            for s ∈ hSets["reg"]
                for d ∈ hSets["reg"]
                    if !valid_trade[c, s, d]
                        hData[k][m,c,s,d] .= 0
                    end
                end
            end
        end
    end
end
```

# Alternatively, get a sample dataset

```

(; hData, hParameters, hSets) = get_sample_data()

```

# Generating initial model

```
# Starting model (a container with model, data, parameters, fixed value indicators, lower bounds, upper bounds)
mc=generate_initial_model(hSets=hSets, hData=hData, hParameters=hParameters)

# Save the initial data because it contains actual values to which we can calibrate later
start_data = deepcopy(mc.data)
```

# Calibrate the data and parameters

```
# Obtain the closure for calibration (fixed_calibration) and data with target values (start_data)
(;fixed_calibration, data_calibration)=generate_calibration_inputs(mc, start_data)

# Before calibrating, let's save the standard closure as we will need it for simulations
fixed_default = deepcopy(mc.fixed)

# Load the model with the calibration data and closure
mc.data = data_calibration
mc.fixed = fixed_calibration

# Calibrate
run_model!(mc)

# Save the calibrate data---this is the starting point for all simulations
calibrated_data = deepcopy(mc.data)
```

# Drop unnecessary equations

The initial model contains equations that are only used for calibration, e.g., equations targeting value shares. These are not necessary to run scenarios and are best removed.

```
rebuild_model!(mc)
```

# Bring back the standard closure

```
mc.fixed = deepcopy(fixed_default)
```

# Running a scenario (increase power of tariff on crops between MENA and EU by 20 percent)

```
# Set the tariff on crops from ssafrica to eu to 1.2 (20 percent)
mc.data["tms"]["crops", "mena", "eu"] = 1.2

# Run the model
run_model!(mc)

```

# Analyzing the results

## View changes in variables

```
# Show the change in exports (percent)
((mc.data["qxs"]./calibrated_data["qxs"])[:, :, "eu"] .- 1) .* 100

```

## Calculate equivalent variation

```
ev = calculate_expenditure(
                    sets=mc.sets, 
                    data0=calibrated_data, 
                    data1=mc.data, 
                    parameters=mc.parameters
                  ) .- calibrated_data["y"]
```

## Calculate change in real GDP

```
qgdp1 = calculate_gdp(sets =mc.sets, data0=calibrated_data, data1=mc.data)
qgdp0 = calculate_gdp(sets =mc.sets, data0=calibrated_data, data1=calibrated_data)
(qgdp1 ./ qgdp0 .- 1) .* 100
```
