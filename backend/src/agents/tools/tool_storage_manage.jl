using ....framework.JuliaOSFramework.Storage
using ..CommonTypes: ToolSpecification, ToolMetadata, ToolConfig
using JSON3, Dates, Logging

Base.@kwdef struct ToolStorageManageConfig <: ToolConfig
    allow_provider_switch::Bool = true  # Allow switching storage providers
    allow_file_deletion::Bool = true    # Allow deleting files
end

"""
    tool_storage_manage(cfg::ToolStorageManageConfig, task::Dict)

Manage storage operations including provider switching, file listing, and file deletion.

Expected task parameters:
- action: The action to perform ("list_providers", "switch_provider", "list_files", "delete_file", "get_info", "file_exists")
- provider_type: (for switch_provider) The provider to switch to ("local", "ipfs", "arweave")
- provider_config: (for switch_provider) Configuration for the new provider
- key: (for delete_file, file_exists) The storage key of the file
- prefix: (for list_files) Optional prefix to filter files

Returns:
- success: Boolean indicating if operation was successful
- action: The action that was performed
- result: The result data (varies by action)
- message: Success or error message
"""
function tool_storage_manage(cfg::ToolStorageManageConfig, task::Dict)
    try
        # Validate required parameters
        if !haskey(task, "action")
            return Dict(
                "success" => false,
                "message" => "Missing required parameter: action",
                "error_code" => "MISSING_ACTION"
            )
        end
        
        action = task["action"]
        
        if action == "list_providers"
            return _handle_list_providers()
        elseif action == "switch_provider"
            return _handle_switch_provider(cfg, task)
        elseif action == "list_files"
            return _handle_list_files(task)
        elseif action == "delete_file"
            return _handle_delete_file(cfg, task)
        elseif action == "get_info"
            return _handle_get_info()
        elseif action == "file_exists"
            return _handle_file_exists(task)
        else
            return Dict(
                "success" => false,
                "message" => "Unknown action: $action. Supported: list_providers, switch_provider, list_files, delete_file, get_info, file_exists",
                "error_code" => "UNKNOWN_ACTION",
                "action" => action
            )
        end
        
    catch e
        @error "Error in storage management tool" exception=(e, catch_backtrace())
        return Dict(
            "success" => false,
            "message" => "Storage management failed: $(sprint(showerror, e))",
            "error_code" => "TOOL_ERROR",
            "action" => get(task, "action", "unknown")
        )
    end
end

function _handle_list_providers()
    available_providers = Storage.get_available_providers()
    current_provider = Storage.get_current_provider_type()
    provider_info = Storage.get_provider_info()
    
    return Dict(
        "success" => true,
        "action" => "list_providers",
        "result" => Dict(
            "available_providers" => available_providers,
            "current_provider" => current_provider,
            "provider_info" => provider_info
        ),
        "message" => "Listed storage providers successfully"
    )
end

function _handle_switch_provider(cfg::ToolStorageManageConfig, task::Dict)
    if !cfg.allow_provider_switch
        return Dict(
            "success" => false,
            "message" => "Provider switching is disabled in tool configuration",
            "error_code" => "SWITCH_DISABLED",
            "action" => "switch_provider"
        )
    end
    
    if !haskey(task, "provider_type")
        return Dict(
            "success" => false,
            "message" => "Missing required parameter for switch_provider: provider_type",
            "error_code" => "MISSING_PROVIDER_TYPE",
            "action" => "switch_provider"
        )
    end
    
    provider_type = Symbol(task["provider_type"])
    config = get(task, "provider_config", Dict())
    
    # Validate provider type
    available_providers = Storage.get_available_providers()
    if !(provider_type in available_providers)
        return Dict(
            "success" => false,
            "message" => "Unsupported provider type: $provider_type. Available: $available_providers",
            "error_code" => "INVALID_PROVIDER",
            "action" => "switch_provider",
            "provider_type" => provider_type
        )
    end
    
    old_provider = Storage.get_current_provider_type()
    success = Storage.switch_provider(provider_type; config=config)
    
    if success
        new_info = Storage.get_provider_info()
        return Dict(
            "success" => true,
            "action" => "switch_provider",
            "result" => Dict(
                "old_provider" => old_provider,
                "new_provider" => provider_type,
                "provider_info" => new_info
            ),
            "message" => "Successfully switched from $old_provider to $provider_type"
        )
    else
        return Dict(
            "success" => false,
            "message" => "Failed to switch to provider: $provider_type",
            "error_code" => "SWITCH_FAILED",
            "action" => "switch_provider",
            "provider_type" => provider_type
        )
    end
end

function _handle_list_files(task::Dict)
    prefix = get(task, "prefix", "")
    keys = Storage.list_keys_default(prefix)
    
    return Dict(
        "success" => true,
        "action" => "list_files",
        "result" => Dict(
            "keys" => keys,
            "count" => length(keys),
            "prefix" => prefix,
            "provider" => Storage.get_current_provider_type()
        ),
        "message" => "Listed $(length(keys)) files successfully"
    )
end

function _handle_delete_file(cfg::ToolStorageManageConfig, task::Dict)
    if !cfg.allow_file_deletion
        return Dict(
            "success" => false,
            "message" => "File deletion is disabled in tool configuration",
            "error_code" => "DELETE_DISABLED",
            "action" => "delete_file"
        )
    end
    
    if !haskey(task, "key")
        return Dict(
            "success" => false,
            "message" => "Missing required parameter for delete_file: key",
            "error_code" => "MISSING_KEY",
            "action" => "delete_file"
        )
    end
    
    key = task["key"]
    
    if !Storage.exists_default(key)
        return Dict(
            "success" => false,
            "message" => "File not found: $key",
            "error_code" => "FILE_NOT_FOUND",
            "action" => "delete_file",
            "key" => key
        )
    end
    
    success = Storage.delete_key_default(key)
    
    if success
        return Dict(
            "success" => true,
            "action" => "delete_file",
            "result" => Dict(
                "key" => key,
                "provider" => Storage.get_current_provider_type()
            ),
            "message" => "File deleted successfully: $key"
        )
    else
        return Dict(
            "success" => false,
            "message" => "Failed to delete file: $key",
            "error_code" => "DELETE_FAILED",
            "action" => "delete_file",
            "key" => key
        )
    end
end

function _handle_get_info()
    provider_info = Storage.get_provider_info()
    keys = Storage.list_keys_default()
    
    return Dict(
        "success" => true,
        "action" => "get_info",
        "result" => Dict(
            "provider_info" => provider_info,
            "total_files" => length(keys),
            "available_providers" => Storage.get_available_providers()
        ),
        "message" => "Retrieved storage information successfully"
    )
end

function _handle_file_exists(task::Dict)
    if !haskey(task, "key")
        return Dict(
            "success" => false,
            "message" => "Missing required parameter for file_exists: key",
            "error_code" => "MISSING_KEY",
            "action" => "file_exists"
        )
    end
    
    key = task["key"]
    exists = Storage.exists_default(key)
    
    return Dict(
        "success" => true,
        "action" => "file_exists",
        "result" => Dict(
            "key" => key,
            "exists" => exists,
            "provider" => Storage.get_current_provider_type()
        ),
        "message" => "File existence check completed: $exists"
    )
end

const TOOL_STORAGE_MANAGE_METADATA = ToolMetadata(
    "storage_manage",
    "Manage storage operations including provider switching, file listing, and deletion"
)

const TOOL_STORAGE_MANAGE_SPECIFICATION = ToolSpecification(
    tool_storage_manage,
    ToolStorageManageConfig,
    TOOL_STORAGE_MANAGE_METADATA
)
