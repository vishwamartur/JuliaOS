using ....framework.JuliaOSFramework.Storage
using ..CommonTypes: ToolSpecification, ToolMetadata, ToolConfig
using JSON3, Dates, Logging

Base.@kwdef struct ToolFileUploadConfig <: ToolConfig
    max_file_size::Int = 10 * 1024 * 1024  # 10MB default
    allowed_extensions::Vector{String} = String[]  # Empty means all extensions allowed
    auto_generate_key::Bool = true  # Auto-generate key if not provided
end

"""
    tool_file_upload(cfg::ToolFileUploadConfig, task::Dict)

Upload a file to the configured storage backend.

Expected task parameters:
- data: The file data to upload (can be string, dict, or any JSON-serializable data)
- key: (optional) Storage key for the file. If not provided and auto_generate_key is true, will generate one
- filename: (optional) Original filename for metadata
- metadata: (optional) Additional metadata to store with the file

Returns:
- success: Boolean indicating if upload was successful
- key: The storage key where the file was saved
- message: Success or error message
- provider: The storage provider used
- size: Size of the uploaded data
"""
function tool_file_upload(cfg::ToolFileUploadConfig, task::Dict)
    try
        # Validate required parameters
        if !haskey(task, "data")
            return Dict(
                "success" => false,
                "message" => "Missing required parameter: data",
                "error_code" => "MISSING_DATA"
            )
        end
        
        data = task["data"]
        
        # Serialize data to JSON for size checking
        data_json = JSON3.write(data)
        data_size = length(data_json)
        
        # Check file size
        if data_size > cfg.max_file_size
            return Dict(
                "success" => false,
                "message" => "File too large. Size: $data_size bytes, Max: $(cfg.max_file_size) bytes",
                "error_code" => "FILE_TOO_LARGE",
                "size" => data_size,
                "max_size" => cfg.max_file_size
            )
        end
        
        # Generate or use provided key
        key = if haskey(task, "key") && !isempty(task["key"])
            task["key"]
        elseif cfg.auto_generate_key
            "upload_$(now())_$(rand(UInt32))"
        else
            return Dict(
                "success" => false,
                "message" => "No storage key provided and auto_generate_key is disabled",
                "error_code" => "MISSING_KEY"
            )
        end
        
        # Prepare metadata
        metadata = Dict{String, Any}(
            "uploaded_at" => string(now(Dates.UTC)),
            "upload_tool" => "file_upload",
            "size" => data_size,
            "data_type" => string(typeof(data))
        )
        
        # Add optional metadata from task
        if haskey(task, "metadata") && isa(task["metadata"], Dict)
            merge!(metadata, task["metadata"])
        end
        
        # Add filename if provided
        if haskey(task, "filename")
            metadata["filename"] = task["filename"]
            
            # Check file extension if restrictions are configured
            if !isempty(cfg.allowed_extensions)
                filename = task["filename"]
                ext = lowercase(splitext(filename)[2])
                if !isempty(ext) && !(ext in cfg.allowed_extensions)
                    return Dict(
                        "success" => false,
                        "message" => "File extension '$ext' not allowed. Allowed: $(cfg.allowed_extensions)",
                        "error_code" => "INVALID_EXTENSION",
                        "extension" => ext,
                        "allowed_extensions" => cfg.allowed_extensions
                    )
                end
            end
        end
        
        # Upload to storage
        success = Storage.save_default(key, data; metadata=metadata)
        
        if success
            provider_type = Storage.get_current_provider_type()
            @info "File uploaded successfully via tool. Key: $key, Size: $data_size bytes, Provider: $provider_type"
            
            return Dict(
                "success" => true,
                "message" => "File uploaded successfully",
                "key" => key,
                "size" => data_size,
                "provider" => string(provider_type),
                "metadata" => metadata
            )
        else
            @error "Failed to upload file via tool. Key: $key"
            return Dict(
                "success" => false,
                "message" => "Failed to save file to storage",
                "error_code" => "STORAGE_ERROR",
                "key" => key
            )
        end
        
    catch e
        @error "Error in file upload tool" exception=(e, catch_backtrace())
        return Dict(
            "success" => false,
            "message" => "Upload failed: $(sprint(showerror, e))",
            "error_code" => "TOOL_ERROR"
        )
    end
end

const TOOL_FILE_UPLOAD_METADATA = ToolMetadata(
    "file_upload",
    "Upload files to the configured storage backend (local, IPFS, Arweave, etc.)"
)

const TOOL_FILE_UPLOAD_SPECIFICATION = ToolSpecification(
    tool_file_upload,
    ToolFileUploadConfig,
    TOOL_FILE_UPLOAD_METADATA
)
