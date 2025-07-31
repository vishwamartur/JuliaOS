"""
IPFSStorage.jl - IPFS storage provider for JuliaOS.

Provides decentralized storage using IPFS (InterPlanetary File System).
Supports both HTTP API and CLI interactions with IPFS nodes.
"""
module IPFSStorage

using HTTP, JSON3, Dates, Logging, Base64
using ..StorageInterface

export IPFSStorageProvider

# Define the IPFS storage provider
mutable struct IPFSStorageProvider <: StorageInterface.StorageProvider
    api_url::String
    timeout::Int
    use_cli::Bool
    ipfs_binary_path::String
    pin_files::Bool
    gateway_url::String
    
    function IPFSStorageProvider(api_url::String="http://127.0.0.1:5001";
                                timeout::Int=30,
                                use_cli::Bool=false,
                                ipfs_binary_path::String="ipfs",
                                pin_files::Bool=true,
                                gateway_url::String="http://127.0.0.1:8080")
        new(api_url, timeout, use_cli, ipfs_binary_path, pin_files, gateway_url)
    end
end

"""
    initialize_provider(provider::IPFSStorageProvider; config::Dict=Dict())

Initialize the IPFS storage provider. Validates connection to IPFS node.
"""
function StorageInterface.initialize_provider(provider::IPFSStorageProvider; config::Dict=Dict())
    # Allow configuration override
    provider.api_url = get(config, "api_url", provider.api_url)
    provider.timeout = get(config, "timeout", provider.timeout)
    provider.use_cli = get(config, "use_cli", provider.use_cli)
    provider.ipfs_binary_path = get(config, "ipfs_binary_path", provider.ipfs_binary_path)
    provider.pin_files = get(config, "pin_files", provider.pin_files)
    provider.gateway_url = get(config, "gateway_url", provider.gateway_url)
    
    try
        # Test connection to IPFS node
        if provider.use_cli
            _test_cli_connection(provider)
        else
            _test_http_connection(provider)
        end
        
        @info "IPFSStorageProvider initialized successfully with API at: $(provider.api_url)"
        return provider
    catch e
        @error "Error initializing IPFS storage provider" exception=(e, catch_backtrace())
        rethrow(e)
    end
end

"""
Test HTTP API connection to IPFS node
"""
function _test_http_connection(provider::IPFSStorageProvider)
    try
        response = HTTP.post("$(provider.api_url)/api/v0/version", 
                           readtimeout=provider.timeout)
        if response.status != 200
            error("IPFS node not responding correctly. Status: $(response.status)")
        end
        
        version_info = JSON3.read(String(response.body))
        @info "Connected to IPFS node version: $(version_info.Version)"
    catch e
        error("Failed to connect to IPFS node at $(provider.api_url): $e")
    end
end

"""
Test CLI connection to IPFS
"""
function _test_cli_connection(provider::IPFSStorageProvider)
    try
        result = read(`$(provider.ipfs_binary_path) version`, String)
        @info "IPFS CLI available: $result"
    catch e
        error("IPFS CLI not available at $(provider.ipfs_binary_path): $e")
    end
end

"""
    save(provider::IPFSStorageProvider, key::String, data::Any; metadata::Dict{String, Any}=Dict{String, Any}())

Save data to IPFS. Returns the IPFS hash as the storage key.
"""
function StorageInterface.save(provider::IPFSStorageProvider, key::String, data::Any; metadata::Dict{String, Any}=Dict{String, Any}())
    try
        # Prepare data for upload
        data_json = JSON3.write(data)
        
        # Create a wrapper object with metadata
        wrapper = Dict(
            "key" => key,
            "data" => data,
            "metadata" => metadata,
            "timestamp" => string(now(Dates.UTC)),
            "provider" => "ipfs"
        )
        
        wrapper_json = JSON3.write(wrapper)
        
        if provider.use_cli
            return _save_via_cli(provider, wrapper_json)
        else
            return _save_via_http(provider, wrapper_json)
        end
    catch e
        @error "Error saving data to IPFS for key '$key'" exception=(e, catch_backtrace())
        return false
    end
end

"""
Save data via HTTP API
"""
function _save_via_http(provider::IPFSStorageProvider, data::String)
    try
        # Create multipart form data
        boundary = "----JuliaOSIPFSBoundary$(rand(UInt32))"
        
        body = """--$boundary\r
Content-Disposition: form-data; name="file"; filename="data.json"\r
Content-Type: application/json\r
\r
$data\r
--$boundary--\r
"""
        
        headers = [
            "Content-Type" => "multipart/form-data; boundary=$boundary"
        ]
        
        url = "$(provider.api_url)/api/v0/add"
        if provider.pin_files
            url *= "?pin=true"
        end
        
        response = HTTP.post(url, headers, body, readtimeout=provider.timeout)
        
        if response.status == 200
            result = JSON3.read(String(response.body))
            hash = result.Hash
            @info "Data saved to IPFS with hash: $hash"
            return true
        else
            @error "Failed to save to IPFS. Status: $(response.status)"
            return false
        end
    catch e
        @error "HTTP API save failed" exception=(e, catch_backtrace())
        return false
    end
end

"""
Save data via CLI
"""
function _save_via_cli(provider::IPFSStorageProvider, data::String)
    try
        # Write data to temporary file
        temp_file = tempname() * ".json"
        write(temp_file, data)
        
        try
            # Add file to IPFS
            cmd = `$(provider.ipfs_binary_path) add $temp_file`
            if provider.pin_files
                cmd = `$(provider.ipfs_binary_path) add --pin $temp_file`
            end
            
            result = read(cmd, String)
            
            # Parse result to get hash
            lines = split(strip(result), '\n')
            if length(lines) > 0
                parts = split(lines[end])
                if length(parts) >= 2
                    hash = parts[2]
                    @info "Data saved to IPFS with hash: $hash"
                    return true
                end
            end
            
            @error "Failed to parse IPFS add result: $result"
            return false
        finally
            # Clean up temp file
            isfile(temp_file) && rm(temp_file)
        end
    catch e
        @error "CLI save failed" exception=(e, catch_backtrace())
        return false
    end
end

"""
    load(provider::IPFSStorageProvider, key::String)::Union{Nothing, Tuple{Any, Dict{String, Any}}}

Load data from IPFS using the key (which should be an IPFS hash).
"""
function StorageInterface.load(provider::IPFSStorageProvider, key::String)::Union{Nothing, Tuple{Any, Dict{String, Any}}}
    try
        if provider.use_cli
            return _load_via_cli(provider, key)
        else
            return _load_via_http(provider, key)
        end
    catch e
        @error "Error loading data from IPFS for key '$key'" exception=(e, catch_backtrace())
        return nothing
    end
end

"""
Load data via HTTP API
"""
function _load_via_http(provider::IPFSStorageProvider, hash::String)
    try
        url = "$(provider.api_url)/api/v0/cat?arg=$hash"
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
            @warn "Failed to load from IPFS. Status: $(response.status)"
            return nothing
        end
    catch e
        @error "HTTP API load failed for hash '$hash'" exception=(e, catch_backtrace())
        return nothing
    end
end

"""
Load data via CLI
"""
function _load_via_cli(provider::IPFSStorageProvider, hash::String)
    try
        result = read(`$(provider.ipfs_binary_path) cat $hash`, String)
        wrapper = JSON3.read(result)

        # Extract data and metadata from wrapper
        if haskey(wrapper, "data") && haskey(wrapper, "metadata")
            return (wrapper.data, wrapper.metadata)
        else
            # Fallback for direct data without wrapper
            return (wrapper, Dict{String, Any}())
        end
    catch e
        @error "CLI load failed for hash '$hash'" exception=(e, catch_backtrace())
        return nothing
    end
end

"""
    delete_key(provider::IPFSStorageProvider, key::String)::Bool

Delete/unpin data from IPFS. Note: IPFS is content-addressed, so this only unpins the content.
"""
function StorageInterface.delete_key(provider::IPFSStorageProvider, key::String)::Bool
    try
        if provider.use_cli
            return _delete_via_cli(provider, key)
        else
            return _delete_via_http(provider, key)
        end
    catch e
        @error "Error deleting/unpinning data from IPFS for key '$key'" exception=(e, catch_backtrace())
        return false
    end
end

"""
Delete/unpin via HTTP API
"""
function _delete_via_http(provider::IPFSStorageProvider, hash::String)
    try
        url = "$(provider.api_url)/api/v0/pin/rm?arg=$hash"
        response = HTTP.post(url, readtimeout=provider.timeout)

        if response.status == 200
            @info "Successfully unpinned IPFS hash: $hash"
            return true
        else
            @warn "Failed to unpin IPFS hash. Status: $(response.status)"
            return false
        end
    catch e
        @error "HTTP API delete failed for hash '$hash'" exception=(e, catch_backtrace())
        return false
    end
end

"""
Delete/unpin via CLI
"""
function _delete_via_cli(provider::IPFSStorageProvider, hash::String)
    try
        read(`$(provider.ipfs_binary_path) pin rm $hash`, String)
        @info "Successfully unpinned IPFS hash: $hash"
        return true
    catch e
        @error "CLI delete failed for hash '$hash'" exception=(e, catch_backtrace())
        return false
    end
end

"""
    list_keys(provider::IPFSStorageProvider, prefix::String="")::Vector{String}

List pinned IPFS hashes. Note: IPFS doesn't support prefix filtering natively.
"""
function StorageInterface.list_keys(provider::IPFSStorageProvider, prefix::String="")::Vector{String}
    try
        if provider.use_cli
            return _list_keys_via_cli(provider, prefix)
        else
            return _list_keys_via_http(provider, prefix)
        end
    catch e
        @error "Error listing keys from IPFS with prefix '$prefix'" exception=(e, catch_backtrace())
        return String[]
    end
end

"""
List keys via HTTP API
"""
function _list_keys_via_http(provider::IPFSStorageProvider, prefix::String)
    try
        url = "$(provider.api_url)/api/v0/pin/ls?type=recursive"
        response = HTTP.get(url, readtimeout=provider.timeout)

        if response.status == 200
            result = JSON3.read(String(response.body))
            keys = String[]

            if haskey(result, "Keys")
                for (hash, _) in result.Keys
                    if isempty(prefix) || startswith(hash, prefix)
                        push!(keys, hash)
                    end
                end
            end

            return keys
        else
            @warn "Failed to list IPFS pins. Status: $(response.status)"
            return String[]
        end
    catch e
        @error "HTTP API list failed" exception=(e, catch_backtrace())
        return String[]
    end
end

"""
List keys via CLI
"""
function _list_keys_via_cli(provider::IPFSStorageProvider, prefix::String)
    try
        result = read(`$(provider.ipfs_binary_path) pin ls --type=recursive`, String)
        keys = String[]

        for line in split(strip(result), '\n')
            if !isempty(line)
                parts = split(line)
                if length(parts) >= 1
                    hash = parts[1]
                    if isempty(prefix) || startswith(hash, prefix)
                        push!(keys, hash)
                    end
                end
            end
        end

        return keys
    catch e
        @error "CLI list failed" exception=(e, catch_backtrace())
        return String[]
    end
end

"""
    exists(provider::IPFSStorageProvider, key::String)::Bool

Check if a key (IPFS hash) exists and is accessible.
"""
function StorageInterface.exists(provider::IPFSStorageProvider, key::String)::Bool
    try
        if provider.use_cli
            return _exists_via_cli(provider, key)
        else
            return _exists_via_http(provider, key)
        end
    catch e
        @error "Error checking existence of IPFS key '$key'" exception=(e, catch_backtrace())
        return false
    end
end

"""
Check existence via HTTP API
"""
function _exists_via_http(provider::IPFSStorageProvider, hash::String)
    try
        url = "$(provider.api_url)/api/v0/object/stat?arg=$hash"
        response = HTTP.get(url, readtimeout=provider.timeout)
        return response.status == 200
    catch e
        return false
    end
end

"""
Check existence via CLI
"""
function _exists_via_cli(provider::IPFSStorageProvider, hash::String)
    try
        read(`$(provider.ipfs_binary_path) object stat $hash`, String)
        return true
    catch e
        return false
    end
end

end # module IPFSStorage
