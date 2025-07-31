using Test
using JuliaOS
using JuliaOS.JuliaOSFramework.Storage
using JSON3
using Dates

@testset "CLI Storage Commands Tests" begin
    
    # Initialize storage system for testing
    test_db_path = tempname() * ".sqlite"
    config = Dict("db_path" => test_db_path)
    provider = Storage.initialize_storage_system(provider_type=:local, config=config)
    @test !isnothing(provider)
    
    @testset "Storage Provider Management" begin
        # Test list providers
        providers = Storage.get_available_providers()
        @test :local in providers
        @test :ipfs in providers
        @test :arweave in providers
        
        # Test current provider
        current = Storage.get_current_provider_type()
        @test current == :local
        
        # Test provider info
        info = Storage.get_provider_info()
        @test haskey(info, "type")
        @test info["type"] == "local"
        @test haskey(info, "initialized")
        @test info["initialized"] == true
    end
    
    @testset "File Operations" begin
        # Test data
        test_key = "cli_test_$(rand(UInt32))"
        test_data = Dict(
            "message" => "Hello from CLI test",
            "timestamp" => string(now()),
            "test_id" => rand(UInt32)
        )
        test_metadata = Dict(
            "test" => true,
            "source" => "cli_test",
            "created_at" => string(now())
        )
        
        # Test upload (save)
        success = Storage.save_default(test_key, test_data; metadata=test_metadata)
        @test success == true
        
        # Test exists
        @test Storage.exists_default(test_key) == true
        @test Storage.exists_default("nonexistent_key") == false
        
        # Test download (load)
        result = Storage.load_default(test_key)
        @test !isnothing(result)
        data, metadata = result
        @test data["message"] == "Hello from CLI test"
        @test metadata["test"] == true
        @test metadata["source"] == "cli_test"
        
        # Test list
        keys = Storage.list_keys_default()
        @test test_key in keys
        
        # Test list with prefix
        prefix_keys = Storage.list_keys_default("cli_test")
        @test test_key in prefix_keys
        
        # Test delete
        @test Storage.delete_key_default(test_key) == true
        @test Storage.exists_default(test_key) == false
    end
    
    @testset "Provider Switching" begin
        # Test switching to local with different config
        new_db_path = tempname() * "_switch.sqlite"
        new_config = Dict("db_path" => new_db_path)
        
        success = Storage.switch_provider(:local; config=new_config)
        @test success == true
        
        # Verify we can still perform operations
        test_key = "switch_test_$(rand(UInt32))"
        test_data = "Test data after provider switch"
        
        @test Storage.save_default(test_key, test_data) == true
        @test Storage.exists_default(test_key) == true
        
        result = Storage.load_default(test_key)
        @test !isnothing(result)
        data, _ = result
        @test data == test_data
        
        @test Storage.delete_key_default(test_key) == true
    end
    
    @testset "Error Handling" begin
        # Test loading non-existent key
        @test isnothing(Storage.load_default("definitely_nonexistent_key_$(rand(UInt64))"))
        
        # Test deleting non-existent key
        result = Storage.delete_key_default("definitely_nonexistent_key_$(rand(UInt64))")
        # Note: delete behavior may vary by provider, so we don't assert specific result
        
        # Test invalid provider switching
        @test_throws Exception Storage.initialize_storage_system(provider_type=:invalid)
    end
    
    @testset "CLI Integration Simulation" begin
        # Simulate CLI operations that would be performed
        
        # Simulate file upload
        temp_file = tempname() * ".json"
        test_content = Dict(
            "cli_upload_test" => true,
            "content" => "This is a test file for CLI upload",
            "timestamp" => string(now())
        )
        
        write(temp_file, JSON3.write(test_content, indent=2))
        
        try
            # Read and upload file content (simulating CLI upload)
            content = read(temp_file, String)
            data = JSON3.read(content)
            
            upload_key = "cli_upload_$(rand(UInt32))"
            metadata = Dict(
                "filename" => basename(temp_file),
                "uploaded_at" => string(now()),
                "file_size" => filesize(temp_file),
                "upload_method" => "cli_simulation"
            )
            
            success = Storage.save_default(upload_key, data; metadata=metadata)
            @test success == true
            
            # Simulate download
            result = Storage.load_default(upload_key)
            @test !isnothing(result)
            downloaded_data, downloaded_metadata = result
            
            @test downloaded_data["cli_upload_test"] == true
            @test downloaded_data["content"] == "This is a test file for CLI upload"
            @test downloaded_metadata["upload_method"] == "cli_simulation"
            
            # Simulate file listing
            keys = Storage.list_keys_default("cli_upload")
            @test upload_key in keys
            
            # Cleanup
            @test Storage.delete_key_default(upload_key) == true
            
        finally
            # Clean up temp file
            isfile(temp_file) && rm(temp_file)
        end
    end
    
    @testset "Metadata Handling" begin
        # Test rich metadata handling
        test_key = "metadata_test_$(rand(UInt32))"
        test_data = Dict("content" => "Test with rich metadata")
        
        rich_metadata = Dict(
            "type" => "test_document",
            "tags" => ["test", "cli", "metadata"],
            "version" => "1.0",
            "author" => "cli_test_suite",
            "created_at" => string(now()),
            "numeric_value" => 42,
            "boolean_flag" => true,
            "nested_data" => Dict(
                "level1" => Dict(
                    "level2" => "deep_value"
                )
            )
        )
        
        # Save with rich metadata
        success = Storage.save_default(test_key, test_data; metadata=rich_metadata)
        @test success == true
        
        # Load and verify metadata preservation
        result = Storage.load_default(test_key)
        @test !isnothing(result)
        data, metadata = result
        
        @test data["content"] == "Test with rich metadata"
        @test metadata["type"] == "test_document"
        @test metadata["tags"] == ["test", "cli", "metadata"]
        @test metadata["version"] == "1.0"
        @test metadata["author"] == "cli_test_suite"
        @test metadata["numeric_value"] == 42
        @test metadata["boolean_flag"] == true
        @test metadata["nested_data"]["level1"]["level2"] == "deep_value"
        
        # Cleanup
        @test Storage.delete_key_default(test_key) == true
    end
    
    @testset "Large Data Handling" begin
        # Test with larger data structures (simulating real-world usage)
        test_key = "large_data_test_$(rand(UInt32))"
        
        large_data = Dict(
            "dataset" => [Dict("id" => i, "value" => rand(), "name" => "item_$i") for i in 1:100],
            "metadata" => Dict(
                "description" => "Large test dataset",
                "size" => 100,
                "generated_at" => string(now())
            ),
            "config" => Dict(
                "parameters" => Dict("param_$i" => rand() for i in 1:20),
                "settings" => ["setting_$i" for i in 1:10]
            )
        )
        
        # Save large data
        success = Storage.save_default(test_key, large_data)
        @test success == true
        
        # Load and verify
        result = Storage.load_default(test_key)
        @test !isnothing(result)
        data, _ = result
        
        @test length(data["dataset"]) == 100
        @test data["metadata"]["size"] == 100
        @test length(data["config"]["parameters"]) == 20
        @test length(data["config"]["settings"]) == 10
        
        # Cleanup
        @test Storage.delete_key_default(test_key) == true
    end
    
    # Cleanup test database
    try
        rm(test_db_path, force=true)
    catch
        # Ignore cleanup errors
    end
end
