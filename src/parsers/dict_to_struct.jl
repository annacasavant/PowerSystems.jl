# Global method definition needs to be at top level in .7
# Convert bool to int
Base.convert(::Type{Bool}, x::Int) = x==0 ? false : x==1 ? true : throw(InexactError())
#############################################

function ps_dict2ps_struct(data::Dict{String,Any})
    """
    Takes a PowerSystems dictionary and return an array of PowerSystems struct for Bus, Generator, Branch and load
    """
    if haskey(data, "bus")
        Buses = PowerSystems.bus_dict_parse(data["bus"])
    else
        warn("Key Error : key 'bus' not found in PowerSystems dictionary, this will result in an empty Bus array")
        Buses =[]
    end
    if haskey(data, "gen")
        Generators, Storage = PowerSystems.gen_dict_parser(data["gen"])
    else
        warn("Key Error : key 'gen' not found in PowerSystems dictionary, this will result in an empty Generators and Storage array")
        Generators =[]
        Storage = []
    end
    if haskey(data, "branch")
        Branches = PowerSystems.branch_dict_parser(data["branch"])
    else
        warn("Key Error : key 'branch' not found in PowerSystems dictionary, this will result in an empty Branches array")
        Branches =[]
    end
    if haskey(data, "load")
        Loads = PowerSystems.load_dict_parser(data["load"])
    else
        warn("Key Error : key 'load'  not found in PowerSystems dictionary, this will result in an empty Loads array")
        Loads =[]
    end
    return Buses, Generators, Storage, Branches, Loads 
end



function add_realtime_ts(data::Dict{String,Any},time_series::Dict{String,Any})
    """
    Args:
        PowerSystems dictionary
        Dictionary of timeseries dataframes 
    Returns:
        PowerSystems dictionary with timerseries component added
    """
    if haskey(data,"gen")
        if haskey(data["gen"],"Hydro")
            if haskey(time_series,"HYDRO")
                data["gen"]["Hydro"] = PowerSystems.add_time_series(data["gen"]["Hydro"],time_series["HYDRO"]["RT"])
            end
        end
        if haskey(data["gen"],"Renewable")
            if haskey(data["gen"]["Renewable"],"PV")
                if haskey(time_series,"PV")
                    data["gen"]["Renewable"]["PV"] = PowerSystems.add_time_series(data["gen"]["Renewable"]["PV"],time_series["PV"]["RT"])
                end
            end
            if haskey(data["gen"]["Renewable"],"RTPV")
                if haskey(time_series,"RTPV")
                    data["gen"]["Renewable"]["RTPV"] = PowerSystems.add_time_series(data["gen"]["Renewable"]["RTPV"],time_series["RTPV"]["RT"])
                end
            end
            if haskey(data["gen"]["Renewable"],"WIND")
                if haskey(time_series,"WIND")
                    data["gen"]["Renewable"]["WIND"] = PowerSystems.add_time_series(data["gen"]["Renewable"]["WIND"],time_series["WIND"]["RT"])
                end
            end
        end
    end
    return data
end


function read_datetime(df)
    """
    Arg:
        Dataframes which includes a timerseries columns Year, Month, Day, Period 
    Returns:
        Dataframe with a DateTime columns 
    """
    if df[25,:Period] > 24
        df[:DateTime] = collect(DateTime(df[1,:Year],df[1,:Month],df[1,:Day],floor(df[1,:Period]/12),Int(df[1,:Period])-1):Minute(5):
                        DateTime(df[end,:Year],df[end,:Month],df[end,:Day],floor(df[end,:Period]/12)-1,5*(Int(df[end,:Period])-(floor(df[end,:Period]/12)-1)*12) -5))
    else
        df[:DateTime] = collect(DateTime(df[1,:Year],df[1,:Month],df[1,:Day],(df[1,:Period]-1)):Hour(1):
                        DateTime(df[end,:Year],df[end,:Month],df[end,:Day],(df[end,:Period]-1)))
    end
    delete!(df, [:Year,:Month,:Day,:Period])
    return df
end

function add_time_series(Device_dict,df)
    """
    Arg:
        Device dictionary - Generators/Load
        Dataframe contains device Realtime/Forecast TimeSeries
    Returns:
        Device dictionary with timeseries added
    """
    for (device_key,device) in Device_dict
        if device_key in convert(Array{String},names(df))
            ts_raw = df[:,Symbol(device_key)]
            Device_dict[device_key]["scalingfactor"] = TimeSeries.TimeArray(df[:DateTime],ts_raw)
        end
    end
    return Device_dict
end



## - Parse Dict to Struct
function bus_dict_parse(dict::Dict{Int,Any})
    Buses = Array{PowerSystems.Bus}(0)
    for (bus_key,bus_dict) in dict
        push!(Buses,PowerSystems.Bus(bus_dict["number"],
                                    bus_dict["name"],
                                    bus_dict["bustype"],
                                    bus_dict["angle"],
                                    bus_dict["voltage"],
                                    bus_dict["voltagelimits"],
                                    bus_dict["basevoltage"]
                                    ))
    end
    return Buses
end


## - Parse Dict to Array
function gen_dict_parser(dict::Dict{String,Any})
    Generators =Array{PowerSystems.Generator}(0)
    Storage_gen =Array{PowerSystems.Storage}(0)
    for (gen_type_key,gen_type_dict) in dict
        if gen_type_key =="Thermal"
            for (thermal_key,thermal_dict) in gen_type_dict
                push!(Generators,PowerSystems.ThermalDispatch(thermal_dict["name"],
                                                            thermal_dict["available"],
                                                            thermal_dict["bus"],
                                                            TechThermal(thermal_dict["tech"]["realpower"],
                                                                        thermal_dict["tech"]["realpowerlimits"],
                                                                        thermal_dict["tech"]["reactivepower"],
                                                                        thermal_dict["tech"]["reactivepowerlimits"],
                                                                        thermal_dict["tech"]["ramplimits"],
                                                                        thermal_dict["tech"]["timelimits"]),
                                                            EconThermal(thermal_dict["econ"]["capacity"],
                                                                        thermal_dict["econ"]["variablecost"],
                                                                        thermal_dict["econ"]["fixedcost"],
                                                                        thermal_dict["econ"]["startupcost"],
                                                                        thermal_dict["econ"]["shutdncost"],
                                                                        thermal_dict["econ"]["annualcapacityfactor"])
                            ))
            end
        elseif gen_type_key =="Hydro"
            for (hydro_key,hydro_dict) in gen_type_dict
                push!(Generators,PowerSystems.HydroCurtailment(hydro_dict["name"],
                                                            hydro_dict["available"],
                                                            hydro_dict["bus"],
                                                            TechHydro(  hydro_dict["tech"]["installedcapacity"],
                                                                        hydro_dict["tech"]["realpower"],
                                                                        hydro_dict["tech"]["realpowerlimits"],
                                                                        hydro_dict["tech"]["reactivepower"],
                                                                        hydro_dict["tech"]["reactivepowerlimits"],
                                                                        hydro_dict["tech"]["ramplimits"],
                                                                        hydro_dict["tech"]["timelimits"]),
                                                            hydro_dict["econ"]["curtailcost"],
                                                            hydro_dict["scalingfactor"]
                            ))
            end
        elseif gen_type_key =="Renewable"
            for (ren_key,ren_dict) in  gen_type_dict  
                if ren_key == "PV"
                    for (pv_key,pv_dict) in ren_dict
                        push!(Generators,PowerSystems.RenewableCurtailment(pv_dict["name"],
                                                                    pv_dict["available"],
                                                                    pv_dict["bus"],
                                                                    pv_dict["tech"]["installedcapacity"],
                                                                    EconRenewable(pv_dict["econ"]["curtailcost"],
                                                                                pv_dict["econ"]["interruptioncost"]),
                                                                    pv_dict["scalingfactor"]
                                    ))
                    end
                elseif ren_key == "RTPV"
                    for (rtpv_key,rtpv_dict) in ren_dict
                        push!(Generators,PowerSystems.RenewableFix(rtpv_dict["name"],
                                                                    rtpv_dict["available"],
                                                                    rtpv_dict["bus"],
                                                                    rtpv_dict["tech"]["installedcapacity"],
                                                                    rtpv_dict["scalingfactor"]
                                    ))
                    end
                elseif ren_key == "WIND"
                    for (wind_key,wind_dict) in ren_dict
                        push!(Generators,PowerSystems.RenewableCurtailment(wind_dict["name"],
                                                                    wind_dict["available"],
                                                                    wind_dict["bus"],
                                                                    wind_dict["tech"]["installedcapacity"],
                                                                    EconRenewable(wind_dict["econ"]["curtailcost"],
                                                                                wind_dict["econ"]["interruptioncost"]),
                                                                    wind_dict["scalingfactor"]
                                    ))
                    end
                end
            end
        elseif gen_type_key =="Storage"
            for (storage_key,storage_dict) in  gen_type_dict 
                push!(Storage_gen,PowerSystems.GenericBattery(storage_dict["name"],
                                                            storage_dict["available"],
                                                            storage_dict["bus"],
                                                            storage_dict["energy"],
                                                            storage_dict["capacity"],
                                                            storage_dict["realpower"],
                                                            storage_dict["inputrealpowerlimit"],
                                                            storage_dict["outputrealpowerlimit"],
                                                            storage_dict["efficiency"],
                                                            storage_dict["reactivepower"],
                                                            storage_dict["reactivepowerlimits"]
                            ))
            end
        end
    end
    return Generators, Storage_gen
end

# - Parse Dict to Array

function branch_dict_parser(dict)
    Branches = Array{PowerSystems.Branch}(0)
    for (branch_key,branch_dict) in dict
        if branch_key == "Transformers"
            for (trans_key,trans_dict) in branch_dict
                if trans_dict["tap"] ==1.0
                    push!(Branches,Transformer2W(trans_dict["name"],
                                                trans_dict["available"],
                                                trans_dict["connectionpoints"],
                                                trans_dict["r"],
                                                trans_dict["x"],
                                                trans_dict["primaryshunt"],
                                                trans_dict["rate"]
                                                ))
                elseif trans_dict["tap"] !=1.0
                    push!(Branches,TapTransformer(trans_dict["name"],
                                                trans_dict["available"],
                                                trans_dict["connectionpoints"],
                                                trans_dict["r"],
                                                trans_dict["x"],
                                                trans_dict["primaryshunt"],
                                                trans_dict["tap"],
                                                trans_dict["rate"]
                                                ))
                end
            end
        else branch_key == "Lines"
            for (line_key,line_dict) in branch_dict
                push!(Branches,Line(line_dict["name"],
                                    line_dict["available"],
                                    line_dict["connectionpoints"],
                                    line_dict["r"],
                                    line_dict["x"],
                                    line_dict["b"],
                                    line_dict["rate"],
                                    line_dict["anglelimits"]
                                    ))
            end
        end
    end
    return Branches
end


## - Parse Dict to Array

function load_dict_parser(dict)
    Loads =Array{PowerSystems.ElectricLoad}(0)
    for (load_key,load_dict) in dict
        push!(Loads,StaticLoad(load_dict["name"],
                load_dict["available"],
                load_dict["bus"],
                load_dict["model"],
                load_dict["maxrealpower"],
                load_dict["maxreactivepower"],
                load_dict["scalingfactor"]
                ))
    end
    return Loads
end