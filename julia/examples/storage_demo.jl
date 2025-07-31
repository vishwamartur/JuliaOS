#!/usr/bin/env julia

"""
JuliaOS Storage Demo

This script demonstrates the decentralized storage capabilities of JuliaOS,
including local storage, IPFS, and Arweave backends.
"""

using Pkg
Pkg.activate(".")

using JuliaOS.JuliaOSFramework.Storage
using JSON3
using Dates

function main()
    println("🚀 JuliaOS Decentralized Storage Demo")
    println("=" ^ 50)
    
    # Initialize with local storage first
    println("\n📁 Initializing Local Storage...")
    local_config = Dict("db_path" => joinpath(tempdir(), "juliaos_demo.sqlite"))
    provider = Storage.initialize_storage_system(provider_type=:local, config=local_config)
    
    if isnothing(provider)
        println("❌ Failed to initialize local storage")
        return
    end
    
    println("✅ Local storage initialized successfully")
    
    # Demonstrate basic operations
    demo_basic_operations()
    
    # Show provider information
    demo_provider_info()
    
    # Demonstrate file operations with metadata
    demo_metadata_operations()
    
    # Demonstrate agent-like file operations
    demo_agent_file_operations()
    
    println("\n🎉 Demo completed successfully!")
    println("\nTo try IPFS or Arweave storage:")
    println("1. For IPFS: Start an IPFS node and run: Storage.switch_provider(:ipfs)")
    println("2. For Arweave: Configure wallet and run: Storage.switch_provider(:arweave)")
end

function demo_basic_operations()
    println("\n📝 Basic Storage Operations")
    println("-" ^ 30)
    
    # Save some data
    test_data = Dict(
        "message" => "Hello from JuliaOS!",
        "timestamp" => string(now()),
        "version" => "1.0.0",
        "features" => ["decentralized", "modular", "scalable"]
    )
    
    key = "demo_file_$(rand(UInt32))"
    
    println("💾 Saving data with key: $key")
    success = Storage.save_default(key, test_data)
    println(success ? "✅ Data saved successfully" : "❌ Failed to save data")
    
    # Check if file exists
    println("🔍 Checking if file exists...")
    exists = Storage.exists_default(key)
    println(exists ? "✅ File exists" : "❌ File not found")
    
    # Load the data
    println("📖 Loading data...")
    result = Storage.load_default(key)
    if !isnothing(result)
        data, metadata = result
        println("✅ Data loaded successfully:")
        println("   Message: $(data["message"])")
        println("   Features: $(join(data["features"], ", "))")
    else
        println("❌ Failed to load data")
    end
    
    # List files
    println("📋 Listing all files...")
    keys = Storage.list_keys_default()
    println("   Found $(length(keys)) files")
    for k in keys[1:min(5, length(keys))]  # Show first 5
        println("   - $k")
    end
    if length(keys) > 5
        println("   ... and $(length(keys) - 5) more")
    end
    
    # Clean up
    println("🗑️  Cleaning up...")
    deleted = Storage.delete_key_default(key)
    println(deleted ? "✅ File deleted successfully" : "❌ Failed to delete file")
end

function demo_provider_info()
    println("\n🔧 Storage Provider Information")
    println("-" ^ 35)
    
    # Show available providers
    providers = Storage.get_available_providers()
    println("📦 Available providers: $(join(string.(providers), ", "))")
    
    # Show current provider
    current = Storage.get_current_provider_type()
    println("🎯 Current provider: $current")
    
    # Show detailed info
    info = Storage.get_provider_info()
    println("📊 Provider details:")
    for (k, v) in info
        println("   $k: $v")
    end
end

function demo_metadata_operations()
    println("\n🏷️  Metadata Operations")
    println("-" ^ 25)
    
    # Create data with rich metadata
    document = Dict(
        "title" => "JuliaOS Research Paper",
        "content" => "This paper explores the architecture of JuliaOS...",
        "authors" => ["Alice", "Bob", "Charlie"],
        "references" => 42
    )
    
    metadata = Dict(
        "document_type" => "research_paper",
        "category" => "computer_science",
        "tags" => ["ai", "agents", "decentralized"],
        "created_at" => string(now()),
        "version" => "1.0",
        "size_estimate" => length(JSON3.write(document)),
        "access_level" => "public"
    )
    
    key = "research_paper_$(rand(UInt32))"
    
    println("💾 Saving document with metadata...")
    success = Storage.save_default(key, document; metadata=metadata)
    
    if success
        println("✅ Document saved successfully")
        
        # Load and show metadata
        result = Storage.load_default(key)
        if !isnothing(result)
            data, meta = result
            println("📄 Document: $(data["title"])")
            println("👥 Authors: $(join(data["authors"], ", "))")
            println("🏷️  Tags: $(join(meta["tags"], ", "))")
            println("📅 Created: $(meta["created_at"])")
            println("📊 Category: $(meta["category"])")
        end
        
        # Clean up
        Storage.delete_key_default(key)
    else
        println("❌ Failed to save document")
    end
end

function demo_agent_file_operations()
    println("\n🤖 Agent-Style File Operations")
    println("-" ^ 35)
    
    # Simulate agent uploading LLM outputs
    llm_output = Dict(
        "prompt" => "Analyze the market trends for cryptocurrency",
        "response" => "Based on recent data, cryptocurrency markets show...",
        "model" => "gpt-4",
        "tokens_used" => 1250,
        "confidence" => 0.87,
        "timestamp" => string(now())
    )
    
    # Simulate agent uploading dataset
    dataset = Dict(
        "name" => "crypto_prices_2024",
        "records" => [
            Dict("symbol" => "BTC", "price" => 45000, "volume" => 1000000),
            Dict("symbol" => "ETH", "price" => 3200, "volume" => 800000),
            Dict("symbol" => "ADA", "price" => 0.45, "volume" => 500000)
        ],
        "source" => "coinbase_api",
        "collected_at" => string(now())
    )
    
    # Simulate swarm state snapshot
    swarm_state = Dict(
        "swarm_id" => "trading_swarm_001",
        "agents" => [
            Dict("id" => "agent_1", "status" => "active", "task" => "price_monitoring"),
            Dict("id" => "agent_2", "status" => "active", "task" => "trend_analysis"),
            Dict("id" => "agent_3", "status" => "idle", "task" => "none")
        ],
        "coordination_state" => "synchronized",
        "last_update" => string(now())
    )
    
    files = [
        ("llm_output", llm_output, "LLM Analysis Output"),
        ("dataset", dataset, "Market Dataset"),
        ("swarm_state", swarm_state, "Swarm State Snapshot")
    ]
    
    saved_keys = String[]
    
    for (prefix, data, description) in files
        key = "$(prefix)_$(rand(UInt32))"
        metadata = Dict(
            "type" => prefix,
            "description" => description,
            "agent_id" => "demo_agent",
            "uploaded_at" => string(now())
        )
        
        println("📤 Uploading: $description")
        success = Storage.save_default(key, data; metadata=metadata)
        
        if success
            println("   ✅ Saved with key: $key")
            push!(saved_keys, key)
        else
            println("   ❌ Failed to save")
        end
    end
    
    # Demonstrate agent downloading files
    println("\n📥 Agent retrieving files...")
    for key in saved_keys
        result = Storage.load_default(key)
        if !isnothing(result)
            data, metadata = result
            println("   📄 $(metadata["description"]) - $(metadata["type"])")
        end
    end
    
    # Clean up
    println("\n🗑️  Cleaning up agent files...")
    for key in saved_keys
        Storage.delete_key_default(key)
    end
    println("   ✅ All files cleaned up")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
