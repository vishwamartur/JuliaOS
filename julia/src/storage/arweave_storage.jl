"""
ArweaveStorage.jl - Arweave storage provider for JuliaOS.

Provides permanent decentralized storage using Arweave blockchain.
Supports direct API calls and wallet management for transaction handling.
"""
module ArweaveStorage

using HTTP, JSON3, Dates, Logging, Base64
using ..StorageInterface

export ArweaveStorageProvider

# Define the Arweave storage provider
mutable struct ArweaveStorageProvider <: StorageInterface.StorageProvider
    gateway_url::String
    wallet_file::String
    wallet_key::Union{String, Nothing}
    timeout::Int
    use_bundlr::Bool
    bundlr_url::String
    currency::String
    
    function ArweaveStorageProvider(gateway_url::String="https://arweave.net";
                                   wallet_file::String="",
                                   timeout::Int=60,
                                   use_bundlr::Bool=false,
                                   bundlr_url::String="https://node1.bundlr.network",
                                   currency::String="arweave")
        new(gateway_url, wallet_file, nothing, timeout, use_bundlr, bundlr_url, currency)
    end
end

"""
    initialize_provider(provider::ArweaveStorageProvider; config::Dict=Dict())

Initialize the Arweave storage provider. Loads wallet if specified.
"""
function StorageInterface.initialize_provider(provider::ArweaveStorageProvider; config::Dict=Dict())
    # Allow configuration override
    provider.gateway_url = get(config, "gateway_url", provider.gateway_url)
    provider.wallet_file = get(config, "wallet_file", provider.wallet_file)
    provider.timeout = get(config, "timeout", provider.timeout)
    provider.use_bundlr = get(config, "use_bundlr", provider.use_bundlr)
    provider.bundlr_url = get(config, "bundlr_url", provider.bundlr_url)
    provider.currency = get(config, "currency", provider.currency)
    
    try
        # Load wallet if specified
        if !isempty(provider.wallet_file) && isfile(provider.wallet_file)
            provider.wallet_key = read(provider.wallet_file, String)
            @info "Arweave wallet loaded from: $(provider.wallet_file)"
        else
            @warn "No wallet file specified or file not found. Read-only mode enabled."
        end
        
        # Test connection to gateway
        _test_gateway_connection(provider)
        
        @info "ArweaveStorageProvider initialized successfully with gateway: $(provider.gateway_url)"
        return provider
    catch e
        @error "Error initializing Arweave storage provider" exception=(e, catch_backtrace())
        rethrow(e)
    end
end

"""
Test connection to Arweave gateway
"""
function _test_gateway_connection(provider::ArweaveStorageProvider)
    try
        response = HTTP.get("$(provider.gateway_url)/info", readtimeout=provider.timeout)
        if response.status != 200
            error("Arweave gateway not responding correctly. Status: $(response.status)")
        end
        
        info = JSON3.read(String(response.body))
        @info "Connected to Arweave network. Height: $(info.height)"
    catch e
        error("Failed to connect to Arweave gateway at $(provider.gateway_url): $e")
    end
end

"""
    save(provider::ArweaveStorageProvider, key::String, data::Any; metadata::Dict{String, Any}=Dict{String, Any}())

Save data to Arweave. Returns transaction ID as the storage key.
"""
function StorageInterface.save(provider::ArweaveStorageProvider, key::String, data::Any; metadata::Dict{String, Any}=Dict{String, Any}())
    if isnothing(provider.wallet_key)
        @error "Cannot save to Arweave without a wallet. Please configure a wallet file."
        return false
    end
    
    try
        # Create a wrapper object with metadata
        wrapper = Dict(
            "key" => key,
            "data" => data,
            "metadata" => metadata,
            "timestamp" => string(now(Dates.UTC)),
            "provider" => "arweave"
        )
        
        wrapper_json = JSON3.write(wrapper)
        
        if provider.use_bundlr
            return _save_via_bundlr(provider, wrapper_json, metadata)
        else
            return _save_via_arweave(provider, wrapper_json, metadata)
        end
    catch e
        @error "Error saving data to Arweave for key '$key'" exception=(e, catch_backtrace())
        return false
    end
end

"""
Save data via direct Arweave transaction
"""
function _save_via_arweave(provider::ArweaveStorageProvider, data::String, metadata::Dict{String, Any})
    try
        # Create transaction
        tx_data = Dict(
            "data" => base64encode(data),
            "tags" => [
                Dict("name" => base64encode("Content-Type"), "value" => base64encode("application/json")),
                Dict("name" => base64encode("App-Name"), "value" => base64encode("JuliaOS")),
                Dict("name" => base64encode("App-Version"), "value" => base64encode("1.0"))
            ]
        )
        
        # Add custom tags from metadata
        for (k, v) in metadata
            push!(tx_data["tags"], Dict("name" => base64encode(string(k)), "value" => base64encode(string(v))))
        end
        
        # Sign and submit transaction (simplified - real implementation would need proper signing)
        headers = [
            "Content-Type" => "application/json"
        ]
        
        response = HTTP.post("$(provider.gateway_url)/tx", headers, JSON3.write(tx_data), readtimeout=provider.timeout)
        
        if response.status == 200
            result = JSON3.read(String(response.body))
            tx_id = result.id
            @info "Data saved to Arweave with transaction ID: $tx_id"
            return true
        else
            @error "Failed to save to Arweave. Status: $(response.status)"
            return false
        end
    catch e
        @error "Arweave save failed" exception=(e, catch_backtrace())
        return false
    end
end

"""
Save data via Bundlr
"""
function _save_via_bundlr(provider::ArweaveStorageProvider, data::String, metadata::Dict{String, Any})
    try
        # Prepare Bundlr transaction
        headers = [
            "Content-Type" => "application/json"
        ]
        
        # Add tags as headers
        for (k, v) in metadata
            push!(headers, "Tag-$(k)" => string(v))
        end
        
        response = HTTP.post("$(provider.bundlr_url)/tx/$(provider.currency)", headers, data, readtimeout=provider.timeout)
        
        if response.status == 200
            result = JSON3.read(String(response.body))
            tx_id = result.id
            @info "Data saved to Arweave via Bundlr with ID: $tx_id"
            return true
        else
            @error "Failed to save via Bundlr. Status: $(response.status)"
            return false
        end
    catch e
        @error "Bundlr save failed" exception=(e, catch_backtrace())
        return false
    end
end

"""
    load(provider::ArweaveStorageProvider, key::String)::Union{Nothing, Tuple{Any, Dict{String, Any}}}

Load data from Arweave using transaction ID.
"""
function StorageInterface.load(provider::ArweaveStorageProvider, key::String)::Union{Nothing, Tuple{Any, Dict{String, Any}}}
    try
        url = "$(provider.gateway_url)/$key"
        response = HTTP.get(url, readtimeout=provider.timeout)
        
        if response.status == 200
            content = String(response.body)
            wrapper = JSON3.read(content)
            
            # Extract data and metadata from wrapper
            if haskey(wrapper, "data") && haskey(wrapper, "metadata")
                return (wrapper.data, wrapper.metadata)
            else
                # Fallback for direct data without wrapper
                return (wrapper, Dict{String, Any}())
            end
        else
            @warn "Failed to load from Arweave. Status: $(response.status)"
            return nothing
        end
    catch e
        @error "Error loading data from Arweave for key '$key'" exception=(e, catch_backtrace())
        return nothing
    end
end

"""
    delete_key(provider::ArweaveStorageProvider, key::String)::Bool

Note: Arweave is permanent storage - data cannot be deleted. This function always returns false.
"""
function StorageInterface.delete_key(provider::ArweaveStorageProvider, key::String)::Bool
    @warn "Arweave is permanent storage. Data cannot be deleted. Transaction ID: $key"
    return false
end

"""
    list_keys(provider::ArweaveStorageProvider, prefix::String="")::Vector{String}

List transactions. Note: This is a simplified implementation.
"""
function StorageInterface.list_keys(provider::ArweaveStorageProvider, prefix::String="")::Vector{String}
    @warn "Listing all Arweave transactions is not practical. This function returns empty list."
    return String[]
end

"""
    exists(provider::ArweaveStorageProvider, key::String)::Bool

Check if a transaction exists on Arweave.
"""
function StorageInterface.exists(provider::ArweaveStorageProvider, key::String)::Bool
    try
        url = "$(provider.gateway_url)/tx/$key/status"
        response = HTTP.get(url, readtimeout=provider.timeout)
        return response.status == 200
    catch e
        return false
    end
end

end # module ArweaveStorage
