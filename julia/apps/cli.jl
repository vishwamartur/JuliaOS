#!/usr/bin/env julia

"""
JuliaOS CLI - Command Line Interface for JuliaOS Framework

This CLI provides access to JuliaOS functionality including storage management,
agent operations, and system administration.
"""

using Pkg
Pkg.activate(dirname(dirname(@__FILE__)))

using ArgParse
using JSON3
using Dates
using Printf
using Crayons
using HTTP

# Import JuliaOS modules
using JuliaOS
using JuliaOS.JuliaOSFramework.Storage

# CLI Configuration
const CLI_VERSION = "0.1.0"
const DEFAULT_API_BASE = "http://localhost:8052/api/v1"

# Color scheme for output
const COLORS = Dict(
    :success => crayon"green",
    :error => crayon"red", 
    :warning => crayon"yellow",
    :info => crayon"blue",
    :header => crayon"bold cyan",
    :reset => crayon"reset"
)

"""
Print colored output to the terminal
"""
function print_colored(text::String, color::Symbol=:reset)
    print(COLORS[color], text, COLORS[:reset])
end

function println_colored(text::String, color::Symbol=:reset)
    println(COLORS[color], text, COLORS[:reset])
end

"""
Parse command line arguments and return settings
"""
function parse_commandline()
    s = ArgParseSettings(
        prog = "juliaos",
        description = "JuliaOS Framework CLI - Manage agents, storage, and more",
        version = CLI_VERSION,
        add_version = true
    )

    @add_arg_table! s begin
        "--api-base"
            help = "Base URL for JuliaOS API"
            default = DEFAULT_API_BASE
        "--config"
            help = "Path to configuration file"
            default = ""
        "--verbose", "-v"
            help = "Enable verbose output"
            action = :store_true
    end

    # Add storage subcommand
    @add_arg_table! s begin
        "storage"
            help = "Storage management commands"
            action = :command
    end

    # Storage subcommands
    s["storage"] = ArgParseSettings(description = "Manage JuliaOS storage backends")
    
    @add_arg_table! s["storage"] begin
        "list-providers"
            help = "List available storage providers"
            action = :command
        "current-provider"
            help = "Show current storage provider"
            action = :command
        "switch"
            help = "Switch to a different storage provider"
            action = :command
        "info"
            help = "Show detailed storage provider information"
            action = :command
        "upload"
            help = "Upload a file to storage"
            action = :command
        "download"
            help = "Download a file from storage"
            action = :command
        "list"
            help = "List stored files"
            action = :command
        "delete"
            help = "Delete a file from storage"
            action = :command
        "exists"
            help = "Check if a file exists in storage"
            action = :command
    end

    # Storage switch command arguments
    @add_arg_table! s["storage"]["switch"] begin
        "provider"
            help = "Provider to switch to (local, ipfs, arweave)"
            required = true
        "--config-json"
            help = "Provider configuration as JSON string"
            default = "{}"
    end

    # Storage upload command arguments
    @add_arg_table! s["storage"]["upload"] begin
        "file"
            help = "File path to upload"
            required = true
        "--key"
            help = "Storage key (auto-generated if not provided)"
            default = ""
        "--metadata"
            help = "Metadata as JSON string"
            default = "{}"
    end

    # Storage download command arguments
    @add_arg_table! s["storage"]["download"] begin
        "key"
            help = "Storage key to download"
            required = true
        "--output", "-o"
            help = "Output file path (prints to stdout if not provided)"
            default = ""
    end

    # Storage list command arguments
    @add_arg_table! s["storage"]["list"] begin
        "--prefix"
            help = "Filter files by prefix"
            default = ""
        "--limit"
            help = "Maximum number of files to list"
            arg_type = Int
            default = 100
    end

    # Storage delete command arguments
    @add_arg_table! s["storage"]["delete"] begin
        "key"
            help = "Storage key to delete"
            required = true
        "--confirm"
            help = "Skip confirmation prompt"
            action = :store_true
    end

    # Storage exists command arguments
    @add_arg_table! s["storage"]["exists"] begin
        "key"
            help = "Storage key to check"
            required = true
    end

    return parse_args(s)
end

"""
Initialize JuliaOS framework with configuration
"""
function initialize_juliaos(config_path::String="")
    try
        if !isempty(config_path) && isfile(config_path)
            # Load custom configuration
            println_colored("📁 Loading configuration from: $config_path", :info)
        end
        
        # Initialize JuliaOS framework
        success = JuliaOS.initialize()
        
        if success
            println_colored("✅ JuliaOS framework initialized successfully", :success)
        else
            println_colored("❌ Failed to initialize JuliaOS framework", :error)
            exit(1)
        end
    catch e
        println_colored("❌ Error initializing JuliaOS: $e", :error)
        exit(1)
    end
end

"""
Make HTTP request to JuliaOS API
"""
function api_request(method::String, endpoint::String, api_base::String; body=nothing, headers=Dict())
    url = "$api_base$endpoint"
    
    try
        if method == "GET"
            response = HTTP.get(url, headers)
        elseif method == "POST"
            response = HTTP.post(url, headers, body)
        elseif method == "DELETE"
            response = HTTP.delete(url, headers)
        else
            error("Unsupported HTTP method: $method")
        end
        
        if response.status >= 200 && response.status < 300
            return JSON3.read(String(response.body))
        else
            error("API request failed with status $(response.status): $(String(response.body))")
        end
    catch e
        if isa(e, HTTP.ConnectError)
            println_colored("❌ Cannot connect to JuliaOS API at $api_base", :error)
            println_colored("   Make sure the JuliaOS server is running", :info)
        else
            println_colored("❌ API request failed: $e", :error)
        end
        exit(1)
    end
end

# ============================================================================
# Storage Commands Implementation
# ============================================================================

"""
Handle storage list-providers command
"""
function cmd_storage_list_providers(args::Dict)
    println_colored("📦 Available Storage Providers", :header)
    println()

    try
        # Try API first, fallback to direct module access
        if haskey(args, "api-base")
            result = api_request("GET", "/storage/providers", args["api-base"])

            println_colored("Available providers:", :info)
            for provider in result["available_providers"]
                print("  • ")
                if provider == string(result["current_provider"])
                    print_colored("$provider (current)", :success)
                else
                    print("$provider")
                end
                println()
            end

            println()
            println_colored("Current provider details:", :info)
            for (key, value) in result["provider_info"]
                println("  $key: $value")
            end
        else
            # Direct module access
            providers = Storage.get_available_providers()
            current = Storage.get_current_provider_type()
            info = Storage.get_provider_info()

            println_colored("Available providers:", :info)
            for provider in providers
                print("  • ")
                if provider == current
                    print_colored("$provider (current)", :success)
                else
                    print("$provider")
                end
                println()
            end

            println()
            println_colored("Current provider details:", :info)
            for (key, value) in info
                println("  $key: $value")
            end
        end
    catch e
        println_colored("❌ Error listing providers: $e", :error)
        exit(1)
    end
end

"""
Handle storage current-provider command
"""
function cmd_storage_current_provider(args::Dict)
    try
        if haskey(args, "api-base")
            result = api_request("GET", "/storage/providers", args["api-base"])
            current = result["current_provider"]
        else
            current = Storage.get_current_provider_type()
        end

        println_colored("Current storage provider: ", :info)
        println_colored("$current", :success)
    catch e
        println_colored("❌ Error getting current provider: $e", :error)
        exit(1)
    end
end

"""
Handle storage switch command
"""
function cmd_storage_switch(args::Dict)
    provider = args["provider"]
    config_json = args["config-json"]

    # Validate provider
    valid_providers = ["local", "ipfs", "arweave"]
    if !(provider in valid_providers)
        println_colored("❌ Invalid provider: $provider", :error)
        println_colored("   Valid providers: $(join(valid_providers, ", "))", :info)
        exit(1)
    end

    # Parse configuration
    try
        config = JSON3.read(config_json)

        println_colored("🔄 Switching to $provider storage provider...", :info)

        if haskey(args, "api-base")
            # Use API
            body = JSON3.write(Dict(
                "provider_type" => provider,
                "config" => config
            ))

            result = api_request("POST", "/storage/providers/switch", args["api-base"];
                               body=body, headers=Dict("Content-Type" => "application/json"))

            println_colored("✅ $(result["message"])", :success)
        else
            # Direct module access
            success = Storage.switch_provider(Symbol(provider); config=Dict(config))

            if success
                println_colored("✅ Successfully switched to $provider", :success)
            else
                println_colored("❌ Failed to switch to $provider", :error)
                exit(1)
            end
        end
    catch e
        println_colored("❌ Error switching provider: $e", :error)
        exit(1)
    end
end

"""
Handle storage info command
"""
function cmd_storage_info(args::Dict)
    println_colored("🔧 Storage Provider Information", :header)
    println()

    try
        if haskey(args, "api-base")
            result = api_request("GET", "/storage/stats", args["api-base"])

            println_colored("Provider Information:", :info)
            for (key, value) in result["provider_info"]
                println("  $key: $value")
            end

            println()
            println_colored("Statistics:", :info)
            println("  Total files: $(result["total_files"])")
            println("  Max file size: $(result["max_file_size"]) bytes")
            println("  Available providers: $(join(result["available_providers"], ", "))")
        else
            info = Storage.get_provider_info()
            keys = Storage.list_keys_default()
            providers = Storage.get_available_providers()

            println_colored("Provider Information:", :info)
            for (key, value) in info
                println("  $key: $value")
            end

            println()
            println_colored("Statistics:", :info)
            println("  Total files: $(length(keys))")
            println("  Available providers: $(join(providers, ", "))")
        end
    catch e
        println_colored("❌ Error getting storage info: $e", :error)
        exit(1)
    end
end

"""
Handle storage upload command
"""
function cmd_storage_upload(args::Dict)
    file_path = args["file"]
    key = args["key"]
    metadata_json = args["metadata"]

    # Check if file exists
    if !isfile(file_path)
        println_colored("❌ File not found: $file_path", :error)
        exit(1)
    end

    try
        # Read file content
        content = read(file_path, String)

        # Try to parse as JSON, fallback to string
        data = try
            JSON3.read(content)
        catch
            content
        end

        # Parse metadata
        metadata = JSON3.read(metadata_json)

        # Generate key if not provided
        if isempty(key)
            filename = basename(file_path)
            timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
            key = "$(filename)_$(timestamp)"
        end

        # Add file metadata
        metadata["filename"] = basename(file_path)
        metadata["uploaded_at"] = string(now())
        metadata["file_size"] = filesize(file_path)
        metadata["upload_method"] = "cli"

        println_colored("📤 Uploading file: $file_path", :info)
        println_colored("   Key: $key", :info)

        if haskey(args, "api-base")
            # Use API
            body = JSON3.write(Dict(
                "key" => key,
                "data" => data,
                "metadata" => metadata
            ))

            result = api_request("POST", "/storage/files", args["api-base"];
                               body=body, headers=Dict("Content-Type" => "application/json"))

            println_colored("✅ $(result["message"])", :success)
            println_colored("   Provider: $(result["provider"])", :info)
            println_colored("   Size: $(result["size"]) bytes", :info)
        else
            # Direct module access
            success = Storage.save_default(key, data; metadata=metadata)

            if success
                provider = Storage.get_current_provider_type()
                println_colored("✅ File uploaded successfully", :success)
                println_colored("   Provider: $provider", :info)
                println_colored("   Size: $(filesize(file_path)) bytes", :info)
            else
                println_colored("❌ Failed to upload file", :error)
                exit(1)
            end
        end
    catch e
        println_colored("❌ Error uploading file: $e", :error)
        exit(1)
    end
end

"""
Handle storage download command
"""
function cmd_storage_download(args::Dict)
    key = args["key"]
    output_path = args["output"]

    try
        println_colored("📥 Downloading file: $key", :info)

        if haskey(args, "api-base")
            # Use API
            result = api_request("GET", "/storage/files/$key", args["api-base"])

            data = result["data"]
            metadata = result["metadata"]

            println_colored("✅ File downloaded successfully", :success)
            println_colored("   Provider: $(result["provider"])", :info)
            println_colored("   Size: $(result["size"]) bytes", :info)
        else
            # Direct module access
            result = Storage.load_default(key)

            if isnothing(result)
                println_colored("❌ File not found: $key", :error)
                exit(1)
            end

            data, metadata = result
            provider = Storage.get_current_provider_type()

            println_colored("✅ File downloaded successfully", :success)
            println_colored("   Provider: $provider", :info)
        end

        # Output data
        if isempty(output_path)
            # Print to stdout
            if isa(data, String)
                println(data)
            else
                println(JSON3.write(data, indent=2))
            end
        else
            # Write to file
            if isa(data, String)
                write(output_path, data)
            else
                write(output_path, JSON3.write(data, indent=2))
            end
            println_colored("   Saved to: $output_path", :info)
        end

        # Show metadata if available
        if !isempty(metadata) && args["verbose"]
            println()
            println_colored("Metadata:", :info)
            for (k, v) in metadata
                println("  $k: $v")
            end
        end

    catch e
        println_colored("❌ Error downloading file: $e", :error)
        exit(1)
    end
end

"""
Handle storage list command
"""
function cmd_storage_list(args::Dict)
    prefix = args["prefix"]
    limit = args["limit"]

    try
        println_colored("📋 Listing stored files", :header)
        if !isempty(prefix)
            println_colored("   Prefix filter: $prefix", :info)
        end
        println()

        if haskey(args, "api-base")
            # Use API
            query_params = "?limit=$limit"
            if !isempty(prefix)
                query_params *= "&prefix=$prefix"
            end

            result = api_request("GET", "/storage/files$query_params", args["api-base"])

            keys = result["keys"]
            count = result["count"]
            provider = result["provider"]
        else
            # Direct module access
            keys = Storage.list_keys_default(prefix)
            count = length(keys)
            provider = Storage.get_current_provider_type()

            # Apply limit
            if count > limit
                keys = keys[1:limit]
            end
        end

        if count == 0
            println_colored("No files found", :warning)
        else
            println_colored("Found $count files (showing $(length(keys))):", :info)
            println_colored("Provider: $provider", :info)
            println()

            for (i, key) in enumerate(keys)
                @printf "%3d. %s\n" i key
            end

            if count > limit
                println()
                println_colored("... and $(count - limit) more files", :info)
                println_colored("Use --limit to show more files", :info)
            end
        end

    catch e
        println_colored("❌ Error listing files: $e", :error)
        exit(1)
    end
end

"""
Handle storage delete command
"""
function cmd_storage_delete(args::Dict)
    key = args["key"]
    confirm = args["confirm"]

    # Confirmation prompt
    if !confirm
        print_colored("⚠️  Are you sure you want to delete '$key'? [y/N]: ", :warning)
        response = readline()
        if lowercase(strip(response)) != "y"
            println_colored("❌ Delete cancelled", :info)
            return
        end
    end

    try
        println_colored("🗑️  Deleting file: $key", :info)

        if haskey(args, "api-base")
            # Use API
            result = api_request("DELETE", "/storage/files/$key", args["api-base"])

            println_colored("✅ $(result["message"])", :success)
            println_colored("   Provider: $(result["provider"])", :info)
        else
            # Direct module access
            success = Storage.delete_key_default(key)

            if success
                provider = Storage.get_current_provider_type()
                println_colored("✅ File deleted successfully", :success)
                println_colored("   Provider: $provider", :info)
            else
                println_colored("❌ Failed to delete file", :error)
                exit(1)
            end
        end

    catch e
        println_colored("❌ Error deleting file: $e", :error)
        exit(1)
    end
end

"""
Handle storage exists command
"""
function cmd_storage_exists(args::Dict)
    key = args["key"]

    try
        if haskey(args, "api-base")
            # Use API
            result = api_request("GET", "/storage/files/$key/exists", args["api-base"])

            exists = result["exists"]
            provider = result["provider"]
        else
            # Direct module access
            exists = Storage.exists_default(key)
            provider = Storage.get_current_provider_type()
        end

        if exists
            println_colored("✅ File exists: $key", :success)
        else
            println_colored("❌ File not found: $key", :error)
        end
        println_colored("   Provider: $provider", :info)

        # Exit with appropriate code
        exit(exists ? 0 : 1)

    catch e
        println_colored("❌ Error checking file existence: $e", :error)
        exit(1)
    end
end

# ============================================================================
# Main CLI Logic
# ============================================================================

"""
Route storage commands to appropriate handlers
"""
function handle_storage_command(args::Dict)
    storage_cmd = args["%COMMAND%"]

    if storage_cmd == "list-providers"
        cmd_storage_list_providers(args)
    elseif storage_cmd == "current-provider"
        cmd_storage_current_provider(args)
    elseif storage_cmd == "switch"
        cmd_storage_switch(args)
    elseif storage_cmd == "info"
        cmd_storage_info(args)
    elseif storage_cmd == "upload"
        cmd_storage_upload(args)
    elseif storage_cmd == "download"
        cmd_storage_download(args)
    elseif storage_cmd == "list"
        cmd_storage_list(args)
    elseif storage_cmd == "delete"
        cmd_storage_delete(args)
    elseif storage_cmd == "exists"
        cmd_storage_exists(args)
    else
        println_colored("❌ Unknown storage command: $storage_cmd", :error)
        exit(1)
    end
end

"""
Main CLI entry point
"""
function main()
    # Parse command line arguments
    args = parse_commandline()

    # Show header
    println_colored("🚀 JuliaOS CLI v$CLI_VERSION", :header)
    println()

    # Initialize JuliaOS if not using API mode
    if !haskey(args, "api-base") || args["api-base"] == DEFAULT_API_BASE
        initialize_juliaos(args["config"])
    end

    # Route to appropriate command handler
    if args["%COMMAND%"] == "storage"
        handle_storage_command(args["storage"])
    else
        println_colored("❌ Unknown command: $(args["%COMMAND%"])", :error)
        println_colored("   Available commands: storage", :info)
        exit(1)
    end
end

# Run main function if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
