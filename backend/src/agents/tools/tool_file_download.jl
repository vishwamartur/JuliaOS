using ....framework.JuliaOSFramework.Storage
using ..CommonTypes: ToolSpecification, ToolMetadata, ToolConfig
using JSON3, Dates, Logging

Base.@kwdef struct ToolFileDownloadConfig <: ToolConfig
    include_metadata::Bool = true  # Include metadata in response
    max_download_size::Int = 50 * 1024 * 1024  # 50MB default max download size
end

"""
    tool_file_download(cfg::ToolFileDownloadConfig, task::Dict)

Download a file from the configured storage backend.

Expected task parameters:
- key: The storage key of the file to download

Returns:
- success: Boolean indicating if download was successful
- key: The storage key that was requested
- data: The file data (if successful)
- metadata: File metadata (if include_metadata is true and successful)
- message: Success or error message
- provider: The storage provider used
- size: Size of the downloaded data
"""
function tool_file_download(cfg::ToolFileDownloadConfig, task::Dict)
    try
        # Validate required parameters
        if !haskey(task, "key")
            return Dict(
                "success" => false,
                "message" => "Missing required parameter: key",
                "error_code" => "MISSING_KEY"
            )
        end
        
        key = task["key"]
        
        if isempty(key)
            return Dict(
                "success" => false,
                "message" => "Storage key cannot be empty",
                "error_code" => "EMPTY_KEY"
            )
        end
        
        # Check if file exists
        if !Storage.exists_default(key)
            return Dict(
                "success" => false,
                "message" => "File not found: $key",
                "error_code" => "FILE_NOT_FOUND",
                "key" => key
            )
        end
        
        # Load file from storage
        result = Storage.load_default(key)
        
        if isnothing(result)
            return Dict(
                "success" => false,
                "message" => "Failed to load file: $key",
                "error_code" => "LOAD_FAILED",
                "key" => key
            )
        end
        
        data, metadata = result
        
        # Calculate data size for response
        data_json = JSON3.write(data)
        data_size = length(data_json)
        
        # Check download size limit
        if data_size > cfg.max_download_size
            return Dict(
                "success" => false,
                "message" => "File too large to download. Size: $data_size bytes, Max: $(cfg.max_download_size) bytes",
                "error_code" => "FILE_TOO_LARGE",
                "key" => key,
                "size" => data_size,
                "max_size" => cfg.max_download_size
            )
        end
        
        provider_type = Storage.get_current_provider_type()
        @info "File downloaded successfully via tool. Key: $key, Size: $data_size bytes, Provider: $provider_type"
        
        # Prepare response
        response = Dict(
            "success" => true,
            "message" => "File downloaded successfully",
            "key" => key,
            "data" => data,
            "size" => data_size,
            "provider" => string(provider_type)
        )
        
        # Include metadata if requested
        if cfg.include_metadata
            response["metadata"] = metadata
        end
        
        return response
        
    catch e
        @error "Error in file download tool" exception=(e, catch_backtrace())
        return Dict(
            "success" => false,
            "message" => "Download failed: $(sprint(showerror, e))",
            "error_code" => "TOOL_ERROR",
            "key" => get(task, "key", "unknown")
        )
    end
end

const TOOL_FILE_DOWNLOAD_METADATA = ToolMetadata(
    "file_download",
    "Download files from the configured storage backend (local, IPFS, Arweave, etc.)"
)

const TOOL_FILE_DOWNLOAD_SPECIFICATION = ToolSpecification(
    tool_file_download,
    ToolFileDownloadConfig,
    TOOL_FILE_DOWNLOAD_METADATA
)
