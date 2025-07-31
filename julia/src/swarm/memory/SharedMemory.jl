"""
SharedMemory.jl - Context sharing and caching system for JuliaOS swarms

This module provides shared memory systems for swarm coordination, caching mechanisms
for expensive computations, and knowledge sharing between agents.
"""
module SharedMemory

using Dates, UUIDs, JSON3, Logging, Serialization
using Base.Threads
using DataStructures: LRU

export SwarmMemoryManager, CacheEntry, SharedContext, KnowledgeBase,
       MemoryScope, CachePolicy, EvictionStrategy,
       store_shared_data!, retrieve_shared_data, cache_computation!,
       get_cached_result, share_knowledge!, get_shared_knowledge,
       create_shared_context, update_context!, get_context_snapshot,
       cleanup_memory!, get_memory_stats, setup_swarm_memory

# ============================================================================
# Memory Scopes and Policies
# ============================================================================

@enum MemoryScope begin
    AGENT_LOCAL = 1      # Private to single agent
    SWARM_SHARED = 2     # Shared within swarm
    GLOBAL_SHARED = 3    # Shared across all swarms
    PERSISTENT = 4       # Persisted to disk
end

@enum CachePolicy begin
    LRU_POLICY = 1       # Least Recently Used
    LFU_POLICY = 2       # Least Frequently Used
    TTL_POLICY = 3       # Time To Live
    SIZE_POLICY = 4      # Size-based eviction
end

@enum EvictionStrategy begin
    IMMEDIATE = 1        # Evict immediately when limit reached
    LAZY = 2            # Evict during cleanup cycles
    ADAPTIVE = 3        # Adapt based on usage patterns
end

# ============================================================================
# Data Structures
# ============================================================================

"""
Cache entry with metadata
"""
mutable struct CacheEntry{T}
    key::String
    value::T
    created_at::DateTime
    last_accessed::DateTime
    access_count::Int
    size_bytes::Int
    ttl_seconds::Int
    scope::MemoryScope
    tags::Set{String}
    
    function CacheEntry{T}(key::String, value::T; 
                          ttl_seconds::Int=3600,
                          scope::MemoryScope=SWARM_SHARED,
                          tags::Set{String}=Set{String}()) where T
        size_bytes = estimate_size(value)
        now_time = now(UTC)
        new{T}(key, value, now_time, now_time, 1, size_bytes, ttl_seconds, scope, tags)
    end
end

"""
Check if cache entry has expired
"""
function is_expired(entry::CacheEntry)::Bool
    return (now(UTC) - entry.created_at).value / 1000 > entry.ttl_seconds
end

"""
Update access statistics
"""
function access!(entry::CacheEntry)
    entry.last_accessed = now(UTC)
    entry.access_count += 1
end

"""
Estimate memory size of an object
"""
function estimate_size(obj)::Int
    try
        io = IOBuffer()
        serialize(io, obj)
        return length(take!(io))
    catch
        return sizeof(string(obj))  # Fallback estimation
    end
end

"""
Shared context for swarm coordination
"""
mutable struct SharedContext
    id::String
    name::String
    data::Dict{String, Any}
    metadata::Dict{String, Any}
    version::Int
    created_at::DateTime
    updated_at::DateTime
    access_permissions::Set{String}  # Agent IDs with access
    
    function SharedContext(name::String, initial_data::Dict{String, Any}=Dict{String, Any}();
                          access_permissions::Set{String}=Set{String}())
        id = string(uuid4())
        now_time = now(UTC)
        metadata = Dict{String, Any}(
            "created_by" => "system",
            "size_bytes" => estimate_size(initial_data),
            "access_count" => 0
        )
        new(id, name, initial_data, metadata, 1, now_time, now_time, access_permissions)
    end
end

"""
Update shared context with new data
"""
function update_context!(context::SharedContext, updates::Dict{String, Any}, updater_id::String="system")
    if !isempty(context.access_permissions) && !(updater_id in context.access_permissions)
        throw(ArgumentError("Agent $updater_id does not have permission to update context $(context.name)"))
    end
    
    merge!(context.data, updates)
    context.version += 1
    context.updated_at = now(UTC)
    context.metadata["updated_by"] = updater_id
    context.metadata["size_bytes"] = estimate_size(context.data)
    context.metadata["access_count"] = get(context.metadata, "access_count", 0) + 1
end

"""
Knowledge base entry for sharing insights and learnings
"""
struct KnowledgeEntry
    id::String
    topic::String
    content::Dict{String, Any}
    confidence::Float64
    source_agent::String
    created_at::DateTime
    tags::Set{String}
    validation_count::Int
    
    function KnowledgeEntry(topic::String, content::Dict{String, Any}, 
                          source_agent::String; confidence::Float64=1.0,
                          tags::Set{String}=Set{String}())
        new(string(uuid4()), topic, content, confidence, source_agent, 
            now(UTC), tags, 0)
    end
end

# ============================================================================
# Main Memory Manager
# ============================================================================

"""
Main swarm memory manager
"""
mutable struct SwarmMemoryManager
    # Cache storage
    cache_storage::Dict{String, CacheEntry}
    cache_policy::CachePolicy
    eviction_strategy::EvictionStrategy
    max_cache_size_mb::Int
    current_cache_size_bytes::Int
    
    # Shared contexts
    shared_contexts::Dict{String, SharedContext}
    context_access_log::Vector{Tuple{String, String, DateTime}}  # context_id, agent_id, timestamp
    
    # Knowledge base
    knowledge_base::Dict{String, Vector{KnowledgeEntry}}  # topic -> entries
    knowledge_index::Dict{String, Set{String}}           # tag -> knowledge_ids
    
    # Statistics
    cache_hits::Int
    cache_misses::Int
    context_updates::Int
    knowledge_shares::Int
    
    # Configuration
    cleanup_interval_seconds::Int
    max_context_history::Int
    
    function SwarmMemoryManager(; cache_policy::CachePolicy=LRU_POLICY,
                              eviction_strategy::EvictionStrategy=ADAPTIVE,
                              max_cache_size_mb::Int=100,
                              cleanup_interval_seconds::Int=300,
                              max_context_history::Int=1000)
        new(Dict{String, CacheEntry}(), cache_policy, eviction_strategy,
            max_cache_size_mb, 0,
            Dict{String, SharedContext}(), Tuple{String, String, DateTime}[],
            Dict{String, Vector{KnowledgeEntry}}(), Dict{String, Set{String}}(),
            0, 0, 0, 0,
            cleanup_interval_seconds, max_context_history)
    end
end

# ============================================================================
# Cache Operations
# ============================================================================

"""
Store data in shared cache
"""
function store_shared_data!(manager::SwarmMemoryManager, key::String, value::Any;
                          scope::MemoryScope=SWARM_SHARED, ttl_seconds::Int=3600,
                          tags::Set{String}=Set{String}())::Bool
    try
        entry = CacheEntry{typeof(value)}(key, value, ttl_seconds=ttl_seconds, 
                                        scope=scope, tags=tags)
        
        # Check if we need to evict entries
        if manager.current_cache_size_bytes + entry.size_bytes > manager.max_cache_size_mb * 1024 * 1024
            evict_cache_entries!(manager, entry.size_bytes)
        end
        
        # Store entry
        if haskey(manager.cache_storage, key)
            # Update existing entry
            old_entry = manager.cache_storage[key]
            manager.current_cache_size_bytes -= old_entry.size_bytes
        end
        
        manager.cache_storage[key] = entry
        manager.current_cache_size_bytes += entry.size_bytes
        
        @debug "Data stored in cache" key=key size_bytes=entry.size_bytes scope=scope
        return true
    catch e
        @error "Failed to store data in cache" key=key error=e
        return false
    end
end

"""
Retrieve data from shared cache
"""
function retrieve_shared_data(manager::SwarmMemoryManager, key::String)::Union{Any, Nothing}
    if haskey(manager.cache_storage, key)
        entry = manager.cache_storage[key]
        
        if is_expired(entry)
            delete!(manager.cache_storage, key)
            manager.current_cache_size_bytes -= entry.size_bytes
            manager.cache_misses += 1
            return nothing
        end
        
        access!(entry)
        manager.cache_hits += 1
        @debug "Cache hit" key=key access_count=entry.access_count
        return entry.value
    else
        manager.cache_misses += 1
        @debug "Cache miss" key=key
        return nothing
    end
end

"""
Cache expensive computation result
"""
function cache_computation!(manager::SwarmMemoryManager, computation_key::String,
                          computation_func::Function, args...; 
                          ttl_seconds::Int=3600, force_recompute::Bool=false)::Any
    # Check if result is already cached
    if !force_recompute
        cached_result = retrieve_shared_data(manager, computation_key)
        if cached_result !== nothing
            return cached_result
        end
    end
    
    # Compute and cache result
    @debug "Computing and caching result" key=computation_key
    start_time = time()
    result = computation_func(args...)
    computation_time = time() - start_time
    
    # Store with computation metadata
    tags = Set(["computation", "auto_cached"])
    store_shared_data!(manager, computation_key, result, ttl_seconds=ttl_seconds, tags=tags)
    
    @debug "Computation cached" key=computation_key time_seconds=computation_time
    return result
end

"""
Get cached computation result
"""
function get_cached_result(manager::SwarmMemoryManager, computation_key::String)::Union{Any, Nothing}
    return retrieve_shared_data(manager, computation_key)
end

# ============================================================================
# Knowledge Sharing Operations
# ============================================================================

"""
Share knowledge with the swarm
"""
function share_knowledge!(manager::SwarmMemoryManager, topic::String,
                        content::Dict{String, Any}, source_agent::String;
                        confidence::Float64=1.0, tags::Set{String}=Set{String}())::String
    entry = KnowledgeEntry(topic, content, source_agent,
                          confidence=confidence, tags=tags)

    # Add to knowledge base
    if !haskey(manager.knowledge_base, topic)
        manager.knowledge_base[topic] = KnowledgeEntry[]
    end
    push!(manager.knowledge_base[topic], entry)

    # Update index
    for tag in tags
        if !haskey(manager.knowledge_index, tag)
            manager.knowledge_index[tag] = Set{String}()
        end
        push!(manager.knowledge_index[tag], entry.id)
    end

    manager.knowledge_shares += 1
    @info "Knowledge shared" topic=topic source=source_agent confidence=confidence tags=length(tags)
    return entry.id
end

"""
Get shared knowledge by topic
"""
function get_shared_knowledge(manager::SwarmMemoryManager, topic::String;
                            min_confidence::Float64=0.0,
                            max_results::Int=10)::Vector{KnowledgeEntry}
    if !haskey(manager.knowledge_base, topic)
        return KnowledgeEntry[]
    end

    entries = manager.knowledge_base[topic]

    # Filter by confidence
    filtered_entries = filter(e -> e.confidence >= min_confidence, entries)

    # Sort by confidence and recency
    sort!(filtered_entries, by=e -> (e.confidence, e.created_at), rev=true)

    # Limit results
    return filtered_entries[1:min(max_results, length(filtered_entries))]
end

"""
Search knowledge by tags
"""
function search_knowledge_by_tags(manager::SwarmMemoryManager, tags::Set{String};
                                min_confidence::Float64=0.0)::Vector{KnowledgeEntry}
    matching_ids = Set{String}()

    # Find intersection of knowledge IDs for all tags
    for (i, tag) in enumerate(tags)
        if haskey(manager.knowledge_index, tag)
            if i == 1
                matching_ids = copy(manager.knowledge_index[tag])
            else
                intersect!(matching_ids, manager.knowledge_index[tag])
            end
        else
            return KnowledgeEntry[]  # No matches if any tag is missing
        end
    end

    # Collect matching entries
    matching_entries = KnowledgeEntry[]
    for (topic, entries) in manager.knowledge_base
        for entry in entries
            if entry.id in matching_ids && entry.confidence >= min_confidence
                push!(matching_entries, entry)
            end
        end
    end

    # Sort by confidence and recency
    sort!(matching_entries, by=e -> (e.confidence, e.created_at), rev=true)
    return matching_entries
end

# ============================================================================
# Context Management Operations
# ============================================================================

"""
Create shared context for swarm coordination
"""
function create_shared_context(manager::SwarmMemoryManager, name::String,
                             initial_data::Dict{String, Any}=Dict{String, Any}();
                             access_permissions::Set{String}=Set{String}())::String
    context = SharedContext(name, initial_data, access_permissions=access_permissions)
    manager.shared_contexts[context.id] = context

    @info "Shared context created" name=name id=context.id permissions=length(access_permissions)
    return context.id
end

"""
Update shared context
"""
function update_context!(manager::SwarmMemoryManager, context_id::String,
                       updates::Dict{String, Any}, updater_id::String)::Bool
    if !haskey(manager.shared_contexts, context_id)
        @warn "Context not found" context_id=context_id
        return false
    end

    try
        context = manager.shared_contexts[context_id]
        update_context!(context, updates, updater_id)

        # Log access
        push!(manager.context_access_log, (context_id, updater_id, now(UTC)))

        # Limit access log size
        if length(manager.context_access_log) > manager.max_context_history
            manager.context_access_log = manager.context_access_log[end-manager.max_context_history÷2:end]
        end

        manager.context_updates += 1
        @debug "Context updated" context_id=context_id updater=updater_id version=context.version
        return true
    catch e
        @error "Failed to update context" context_id=context_id error=e
        return false
    end
end

"""
Get context snapshot
"""
function get_context_snapshot(manager::SwarmMemoryManager, context_id::String,
                            accessor_id::String)::Union{Dict{String, Any}, Nothing}
    if !haskey(manager.shared_contexts, context_id)
        return nothing
    end

    context = manager.shared_contexts[context_id]

    # Check permissions
    if !isempty(context.access_permissions) && !(accessor_id in context.access_permissions)
        @warn "Access denied to context" context_id=context_id accessor=accessor_id
        return nothing
    end

    # Log access
    push!(manager.context_access_log, (context_id, accessor_id, now(UTC)))
    context.metadata["access_count"] = get(context.metadata, "access_count", 0) + 1

    return Dict{String, Any}(
        "id" => context.id,
        "name" => context.name,
        "data" => copy(context.data),
        "version" => context.version,
        "updated_at" => context.updated_at,
        "metadata" => copy(context.metadata)
    )
end

"""
Grant context access to agent
"""
function grant_context_access!(manager::SwarmMemoryManager, context_id::String, agent_id::String)::Bool
    if haskey(manager.shared_contexts, context_id)
        push!(manager.shared_contexts[context_id].access_permissions, agent_id)
        @info "Context access granted" context_id=context_id agent_id=agent_id
        return true
    end
    return false
end

"""
Revoke context access from agent
"""
function revoke_context_access!(manager::SwarmMemoryManager, context_id::String, agent_id::String)::Bool
    if haskey(manager.shared_contexts, context_id)
        delete!(manager.shared_contexts[context_id].access_permissions, agent_id)
        @info "Context access revoked" context_id=context_id agent_id=agent_id
        return true
    end
    return false
end

# ============================================================================
# Cache Eviction and Cleanup
# ============================================================================

"""
Evict cache entries to free up space
"""
function evict_cache_entries!(manager::SwarmMemoryManager, bytes_needed::Int)
    if manager.eviction_strategy == IMMEDIATE
        evict_immediate!(manager, bytes_needed)
    elseif manager.eviction_strategy == LAZY
        evict_lazy!(manager, bytes_needed)
    else  # ADAPTIVE
        evict_adaptive!(manager, bytes_needed)
    end
end

"""
Immediate eviction based on cache policy
"""
function evict_immediate!(manager::SwarmMemoryManager, bytes_needed::Int)
    entries_to_remove = String[]
    bytes_freed = 0

    if manager.cache_policy == LRU_POLICY
        # Sort by last accessed time
        sorted_entries = sort(collect(manager.cache_storage), by=p -> p.second.last_accessed)
    elseif manager.cache_policy == LFU_POLICY
        # Sort by access count
        sorted_entries = sort(collect(manager.cache_storage), by=p -> p.second.access_count)
    elseif manager.cache_policy == TTL_POLICY
        # Sort by creation time (oldest first)
        sorted_entries = sort(collect(manager.cache_storage), by=p -> p.second.created_at)
    else  # SIZE_POLICY
        # Sort by size (largest first)
        sorted_entries = sort(collect(manager.cache_storage), by=p -> p.second.size_bytes, rev=true)
    end

    for (key, entry) in sorted_entries
        if bytes_freed >= bytes_needed
            break
        end

        push!(entries_to_remove, key)
        bytes_freed += entry.size_bytes
    end

    # Remove selected entries
    for key in entries_to_remove
        entry = manager.cache_storage[key]
        delete!(manager.cache_storage, key)
        manager.current_cache_size_bytes -= entry.size_bytes
        @debug "Cache entry evicted" key=key size_bytes=entry.size_bytes policy=manager.cache_policy
    end

    @info "Cache eviction completed" entries_removed=length(entries_to_remove) bytes_freed=bytes_freed
end

"""
Lazy eviction - remove only expired entries
"""
function evict_lazy!(manager::SwarmMemoryManager, bytes_needed::Int)
    expired_keys = String[]
    bytes_freed = 0

    for (key, entry) in manager.cache_storage
        if is_expired(entry)
            push!(expired_keys, key)
            bytes_freed += entry.size_bytes
        end
    end

    # Remove expired entries
    for key in expired_keys
        entry = manager.cache_storage[key]
        delete!(manager.cache_storage, key)
        manager.current_cache_size_bytes -= entry.size_bytes
    end

    # If not enough space freed, fall back to immediate eviction
    if bytes_freed < bytes_needed
        evict_immediate!(manager, bytes_needed - bytes_freed)
    end

    @debug "Lazy eviction completed" expired_removed=length(expired_keys) bytes_freed=bytes_freed
end

"""
Adaptive eviction based on usage patterns
"""
function evict_adaptive!(manager::SwarmMemoryManager, bytes_needed::Int)
    # First remove expired entries
    evict_lazy!(manager, 0)

    # Calculate current cache utilization
    utilization = manager.current_cache_size_bytes / (manager.max_cache_size_mb * 1024 * 1024)

    if utilization > 0.9
        # High utilization - be aggressive
        evict_immediate!(manager, bytes_needed * 2)  # Free extra space
    elseif utilization > 0.7
        # Medium utilization - normal eviction
        evict_immediate!(manager, bytes_needed)
    else
        # Low utilization - minimal eviction
        evict_immediate!(manager, max(bytes_needed, manager.current_cache_size_bytes ÷ 10))
    end
end

"""
Cleanup expired entries and optimize memory usage
"""
function cleanup_memory!(manager::SwarmMemoryManager)
    @debug "Starting memory cleanup"

    # Clean up expired cache entries
    expired_cache_keys = String[]
    for (key, entry) in manager.cache_storage
        if is_expired(entry)
            push!(expired_cache_keys, key)
        end
    end

    for key in expired_cache_keys
        entry = manager.cache_storage[key]
        delete!(manager.cache_storage, key)
        manager.current_cache_size_bytes -= entry.size_bytes
    end

    # Clean up old context access logs
    if length(manager.context_access_log) > manager.max_context_history
        manager.context_access_log = manager.context_access_log[end-manager.max_context_history÷2:end]
    end

    # Clean up old knowledge entries (keep only recent high-confidence ones)
    for (topic, entries) in manager.knowledge_base
        if length(entries) > 100  # Arbitrary limit
            # Sort by confidence and recency, keep top entries
            sort!(entries, by=e -> (e.confidence, e.created_at), rev=true)
            manager.knowledge_base[topic] = entries[1:50]
        end
    end

    @info "Memory cleanup completed" expired_cache_entries=length(expired_cache_keys)
end

# ============================================================================
# Statistics and Utilities
# ============================================================================

"""
Get memory usage statistics
"""
function get_memory_stats(manager::SwarmMemoryManager)::Dict{String, Any}
    cache_hit_rate = manager.cache_hits + manager.cache_misses > 0 ?
                    manager.cache_hits / (manager.cache_hits + manager.cache_misses) : 0.0

    return Dict{String, Any}(
        "cache" => Dict(
            "entries" => length(manager.cache_storage),
            "size_mb" => manager.current_cache_size_bytes / (1024 * 1024),
            "max_size_mb" => manager.max_cache_size_mb,
            "utilization" => manager.current_cache_size_bytes / (manager.max_cache_size_mb * 1024 * 1024),
            "hits" => manager.cache_hits,
            "misses" => manager.cache_misses,
            "hit_rate" => cache_hit_rate,
            "policy" => string(manager.cache_policy),
            "eviction_strategy" => string(manager.eviction_strategy)
        ),
        "contexts" => Dict(
            "total" => length(manager.shared_contexts),
            "updates" => manager.context_updates,
            "access_log_size" => length(manager.context_access_log)
        ),
        "knowledge" => Dict(
            "topics" => length(manager.knowledge_base),
            "total_entries" => sum(length(entries) for entries in values(manager.knowledge_base)),
            "shares" => manager.knowledge_shares,
            "indexed_tags" => length(manager.knowledge_index)
        )
    )
end

"""
Setup swarm memory for a group of agents
"""
function setup_swarm_memory(agent_ids::Vector{String};
                           max_cache_size_mb::Int=100,
                           cache_policy::CachePolicy=LRU_POLICY)::SwarmMemoryManager
    manager = SwarmMemoryManager(max_cache_size_mb=max_cache_size_mb, cache_policy=cache_policy)

    # Create default shared contexts
    coordination_context_id = create_shared_context(manager, "coordination",
                                                   Dict{String, Any}("active_agents" => agent_ids))

    # Grant access to all agents
    for agent_id in agent_ids
        grant_context_access!(manager, coordination_context_id, agent_id)
    end

    @info "Swarm memory setup completed" agents=length(agent_ids) cache_size_mb=max_cache_size_mb
    return manager
end

"""
Export memory state for persistence
"""
function export_memory_state(manager::SwarmMemoryManager)::Dict{String, Any}
    return Dict{String, Any}(
        "shared_contexts" => Dict(id => Dict(
            "name" => ctx.name,
            "data" => ctx.data,
            "metadata" => ctx.metadata,
            "version" => ctx.version,
            "access_permissions" => collect(ctx.access_permissions)
        ) for (id, ctx) in manager.shared_contexts),
        "knowledge_base" => Dict(topic => [Dict(
            "id" => entry.id,
            "content" => entry.content,
            "confidence" => entry.confidence,
            "source_agent" => entry.source_agent,
            "created_at" => entry.created_at,
            "tags" => collect(entry.tags)
        ) for entry in entries] for (topic, entries) in manager.knowledge_base),
        "statistics" => get_memory_stats(manager)
    )
end

end # module SharedMemory
