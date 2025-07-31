# julia/src/api/StorageHandlers.jl
module StorageHandlers

using HTTP
using JSON3
using ..Utils
using ..framework.JuliaOSFramework.Storage

# Maximum file size for uploads (10MB by default)
const MAX_FILE_SIZE = Ref{Int}(10 * 1024 * 1024)

"""
    list_storage_providers_handler(req::HTTP.Request)

List all available storage providers and their status.
"""
function list_storage_providers_handler(req::HTTP.Request)
    try
        available_providers = Storage.get_available_providers()
        current_provider = Storage.get_current_provider_type()
        provider_info = Storage.get_provider_info()
        
        response_data = Dict(
            "available_providers" => available_providers,
            "current_provider" => current_provider,
            "provider_info" => provider_info
        )
        
        return Utils.json_response(response_data)
    catch e
        @error "Error listing storage providers" exception=(e, catch_backtrace())
        return Utils.error_response("Failed to list storage providers: $(sprint(showerror, e))", 500, 
                                   error_code=Utils.ERROR_CODE_SERVER_ERROR)
    end
end

"""
    switch_storage_provider_handler(req::HTTP.Request)

Switch to a different storage provider.
"""
function switch_storage_provider_handler(req::HTTP.Request)
    body = Utils.parse_request_body(req)
    if isnothing(body)
        return Utils.error_response("Invalid or empty request body", 400, 
                                   error_code=Utils.ERROR_CODE_INVALID_INPUT)
    end
    
    if !haskey(body, "provider_type")
        return Utils.error_response("Missing required field: provider_type", 400, 
                                   error_code=Utils.ERROR_CODE_INVALID_INPUT)
    end
    
    try
        provider_type = Symbol(body["provider_type"])
        config = get(body, "config", Dict())
        
        # Validate provider type
        available_providers = Storage.get_available_providers()
        if !(provider_type in available_providers)
            return Utils.error_response("Unsupported provider type: $provider_type. Available: $available_providers", 400,
                                       error_code=Utils.ERROR_CODE_INVALID_INPUT)
        end
        
        success = Storage.switch_provider(provider_type; config=config)
        
        if success
            provider_info = Storage.get_provider_info()
            return Utils.json_response(Dict(
                "message" => "Successfully switched to $provider_type",
                "provider_info" => provider_info
            ))
        else
            return Utils.error_response("Failed to switch to provider: $provider_type", 500,
                                       error_code=Utils.ERROR_CODE_SERVER_ERROR)
        end
    catch e
        @error "Error switching storage provider" exception=(e, catch_backtrace())
        return Utils.error_response("Failed to switch storage provider: $(sprint(showerror, e))", 500,
                                   error_code=Utils.ERROR_CODE_SERVER_ERROR)
    end
end

"""
    upload_file_handler(req::HTTP.Request)

Upload a file to the current storage provider.
"""
function upload_file_handler(req::HTTP.Request)
    try
        # Check content length
        content_length = get(Dict(req.headers), "Content-Length", "0")
        if parse(Int, content_length) > MAX_FILE_SIZE[]
            return Utils.error_response("File too large. Maximum size: $(MAX_FILE_SIZE[]) bytes", 413,
                                       error_code=Utils.ERROR_CODE_INVALID_INPUT)
        end
        
        # Parse multipart form data (simplified)
        body = String(req.body)
        
        # Extract file data and metadata from request
        # This is a simplified implementation - real multipart parsing would be more complex
        if isempty(body)
            return Utils.error_response("No file data provided", 400,
                                       error_code=Utils.ERROR_CODE_INVALID_INPUT)
        end
        
        # For now, treat the entire body as JSON data
        try
            data = JSON3.read(body)
            key = get(data, "key", "file_$(now())")
            file_data = get(data, "data", data)
            metadata = get(data, "metadata", Dict{String, Any}())
            
            # Add upload metadata
            metadata["uploaded_at"] = string(now())
            metadata["content_length"] = length(body)
            metadata["upload_method"] = "api"
            
            success = Storage.save_default(key, file_data; metadata=metadata)
            
            if success
                return Utils.json_response(Dict(
                    "message" => "File uploaded successfully",
                    "key" => key,
                    "size" => length(body),
                    "provider" => Storage.get_current_provider_type()
                ))
            else
                return Utils.error_response("Failed to save file to storage", 500,
                                           error_code=Utils.ERROR_CODE_SERVER_ERROR)
            end
        catch json_e
            return Utils.error_response("Invalid JSON data: $(sprint(showerror, json_e))", 400,
                                       error_code=Utils.ERROR_CODE_INVALID_INPUT)
        end
    catch e
        @error "Error uploading file" exception=(e, catch_backtrace())
        return Utils.error_response("Failed to upload file: $(sprint(showerror, e))", 500,
                                   error_code=Utils.ERROR_CODE_SERVER_ERROR)
    end
end

"""
    download_file_handler(req::HTTP.Request, key::String)

Download a file from the current storage provider.
"""
function download_file_handler(req::HTTP.Request, key::String)
    try
        result = Storage.load_default(key)
        
        if isnothing(result)
            return Utils.error_response("File not found: $key", 404,
                                       error_code=Utils.ERROR_CODE_NOT_FOUND)
        end
        
        data, metadata = result
        
        # Return file data with metadata
        response_data = Dict(
            "key" => key,
            "data" => data,
            "metadata" => metadata,
            "provider" => Storage.get_current_provider_type()
        )
        
        return Utils.json_response(response_data)
    catch e
        @error "Error downloading file" exception=(e, catch_backtrace())
        return Utils.error_response("Failed to download file: $(sprint(showerror, e))", 500,
                                   error_code=Utils.ERROR_CODE_SERVER_ERROR)
    end
end

"""
    delete_file_handler(req::HTTP.Request, key::String)

Delete a file from the current storage provider.
"""
function delete_file_handler(req::HTTP.Request, key::String)
    try
        success = Storage.delete_key_default(key)
        
        if success
            return Utils.json_response(Dict(
                "message" => "File deleted successfully",
                "key" => key,
                "provider" => Storage.get_current_provider_type()
            ))
        else
            return Utils.error_response("Failed to delete file: $key", 500,
                                       error_code=Utils.ERROR_CODE_SERVER_ERROR)
        end
    catch e
        @error "Error deleting file" exception=(e, catch_backtrace())
        return Utils.error_response("Failed to delete file: $(sprint(showerror, e))", 500,
                                   error_code=Utils.ERROR_CODE_SERVER_ERROR)
    end
end

"""
    list_files_handler(req::HTTP.Request)

List files in the current storage provider.
"""
function list_files_handler(req::HTTP.Request)
    try
        # Parse query parameters
        query_params = HTTP.queryparams(HTTP.URI(req.target))
        prefix = get(query_params, "prefix", "")
        limit = parse(Int, get(query_params, "limit", "100"))
        
        keys = Storage.list_keys_default(prefix)
        
        # Apply limit
        if length(keys) > limit
            keys = keys[1:limit]
        end
        
        response_data = Dict(
            "keys" => keys,
            "count" => length(keys),
            "prefix" => prefix,
            "provider" => Storage.get_current_provider_type()
        )
        
        return Utils.json_response(response_data)
    catch e
        @error "Error listing files" exception=(e, catch_backtrace())
        return Utils.error_response("Failed to list files: $(sprint(showerror, e))", 500,
                                   error_code=Utils.ERROR_CODE_SERVER_ERROR)
    end
end

"""
    file_exists_handler(req::HTTP.Request, key::String)

Check if a file exists in the current storage provider.
"""
function file_exists_handler(req::HTTP.Request, key::String)
    try
        exists = Storage.exists_default(key)
        
        response_data = Dict(
            "key" => key,
            "exists" => exists,
            "provider" => Storage.get_current_provider_type()
        )
        
        return Utils.json_response(response_data)
    catch e
        @error "Error checking file existence" exception=(e, catch_backtrace())
        return Utils.error_response("Failed to check file existence: $(sprint(showerror, e))", 500,
                                   error_code=Utils.ERROR_CODE_SERVER_ERROR)
    end
end

"""
    get_storage_stats_handler(req::HTTP.Request)

Get storage statistics and provider information.
"""
function get_storage_stats_handler(req::HTTP.Request)
    try
        provider_info = Storage.get_provider_info()
        keys = Storage.list_keys_default()
        
        stats = Dict(
            "provider_info" => provider_info,
            "total_files" => length(keys),
            "max_file_size" => MAX_FILE_SIZE[],
            "available_providers" => Storage.get_available_providers()
        )
        
        return Utils.json_response(stats)
    catch e
        @error "Error getting storage stats" exception=(e, catch_backtrace())
        return Utils.error_response("Failed to get storage stats: $(sprint(showerror, e))", 500,
                                   error_code=Utils.ERROR_CODE_SERVER_ERROR)
    end
end

end # module StorageHandlers
