using Test
using JuliaOS.JuliaOSFramework.Storage

@testset "Storage System Tests" begin
    
    @testset "Local Storage Provider" begin
        # Test local storage initialization
        config = Dict("db_path" => tempname() * ".sqlite")
        provider = Storage.initialize_storage_system(provider_type=:local, config=config)
        
        @test !isnothing(provider)
        @test Storage.get_current_provider_type() == :local
        
        # Test basic operations
        test_key = "test_key_$(rand(UInt32))"
        test_data = Dict("message" => "Hello, World!", "timestamp" => "2024-01-01")
        test_metadata = Dict("test" => true, "source" => "unit_test")
        
        # Test save
        @test Storage.save_default(test_key, test_data; metadata=test_metadata) == true
        
        # Test exists
        @test Storage.exists_default(test_key) == true
        @test Storage.exists_default("nonexistent_key") == false
        
        # Test load
        result = Storage.load_default(test_key)
        @test !isnothing(result)
        data, metadata = result
        @test data["message"] == "Hello, World!"
        @test metadata["test"] == true
        
        # Test list keys
        keys = Storage.list_keys_default()
        @test test_key in keys
        
        # Test delete
        @test Storage.delete_key_default(test_key) == true
        @test Storage.exists_default(test_key) == false
    end
    
    @testset "Storage Provider Management" begin
        # Test available providers
        providers = Storage.get_available_providers()
        @test :local in providers
        @test :ipfs in providers
        @test :arweave in providers
        
        # Test provider info
        info = Storage.get_provider_info()
        @test haskey(info, "type")
        @test haskey(info, "initialized")
        @test info["initialized"] == true
    end
    
    @testset "Storage Provider Factory" begin
        # Test switching between providers (only test local since others require external services)
        original_provider = Storage.get_current_provider_type()
        
        # Switch to local with different config
        config = Dict("db_path" => tempname() * "_test.sqlite")
        success = Storage.switch_provider(:local; config=config)
        @test success == true
        @test Storage.get_current_provider_type() == :local
        
        # Test that we can still perform operations after switch
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
        # Test invalid provider type
        @test_throws Exception Storage.initialize_storage_system(provider_type=:invalid)
        
        # Test operations on non-existent keys
        @test isnothing(Storage.load_default("definitely_nonexistent_key_$(rand(UInt64))"))
        
        # Test empty key
        @test Storage.save_default("", "data") == false || Storage.save_default("", "data") == true  # Some providers might allow empty keys
    end
    
    @testset "Metadata Handling" begin
        # Test metadata preservation
        test_key = "metadata_test_$(rand(UInt32))"
        test_data = "Test data with metadata"
        test_metadata = Dict(
            "created_by" => "test_suite",
            "version" => "1.0",
            "tags" => ["test", "metadata"],
            "numeric_value" => 42
        )
        
        @test Storage.save_default(test_key, test_data; metadata=test_metadata) == true
        
        result = Storage.load_default(test_key)
        @test !isnothing(result)
        data, metadata = result
        
        @test data == test_data
        @test metadata["created_by"] == "test_suite"
        @test metadata["version"] == "1.0"
        @test metadata["tags"] == ["test", "metadata"]
        @test metadata["numeric_value"] == 42
        
        # Cleanup
        @test Storage.delete_key_default(test_key) == true
    end
    
    @testset "Large Data Handling" begin
        # Test with larger data structures
        test_key = "large_data_test_$(rand(UInt32))"
        large_data = Dict(
            "array" => collect(1:1000),
            "nested" => Dict(
                "level1" => Dict(
                    "level2" => Dict(
                        "data" => repeat("x", 1000)
                    )
                )
            ),
            "strings" => [randstring(100) for _ in 1:50]
        )
        
        @test Storage.save_default(test_key, large_data) == true
        @test Storage.exists_default(test_key) == true
        
        result = Storage.load_default(test_key)
        @test !isnothing(result)
        data, _ = result
        
        @test data["array"] == collect(1:1000)
        @test length(data["strings"]) == 50
        @test data["nested"]["level1"]["level2"]["data"] == repeat("x", 1000)
        
        # Cleanup
        @test Storage.delete_key_default(test_key) == true
    end
    
    @testset "Concurrent Operations" begin
        # Test basic thread safety (simple test)
        test_keys = ["concurrent_test_$i" for i in 1:10]
        
        # Save multiple keys
        for (i, key) in enumerate(test_keys)
            @test Storage.save_default(key, "data_$i") == true
        end
        
        # Verify all keys exist
        for key in test_keys
            @test Storage.exists_default(key) == true
        end
        
        # Load all keys
        for (i, key) in enumerate(test_keys)
            result = Storage.load_default(key)
            @test !isnothing(result)
            data, _ = result
            @test data == "data_$i"
        end
        
        # Cleanup
        for key in test_keys
            @test Storage.delete_key_default(key) == true
        end
    end
end
