"""
SwarmEnhancements.jl - Main integration module for JuliaOS swarm optimization enhancements

This module provides the main interface for all swarm optimization enhancements,
integrating advanced scoring functions, enhanced optimization, communication systems,
memory management, task recovery, and LLM-based coordination.
"""
module SwarmEnhancements

using Dates, Logging, Statistics

# Import all enhancement modules
include("scoring/AdvancedScoringFunctions.jl")
include("optimization/EnhancedOptimization.jl")
include("communication/SwarmCommunication.jl")
include("memory/SharedMemory.jl")
include("recovery/TaskRecovery.jl")
include("intelligence/InferenceCoordination.jl")
include("applications/RealWorldExamples.jl")

using .AdvancedScoringFunctions
using .EnhancedOptimization
using .SwarmCommunication
using .SharedMemory
using .TaskRecovery
using .InferenceCoordination
using .RealWorldExamples

# Re-export key functionality
export 
    # Advanced Scoring Functions
    MultiObjectiveFunction, ConstrainedObjectiveFunction, PricePredictionObjective,
    RoutingObjective, NFTValuationObjective, PortfolioOptimizationObjective,
    
    # Enhanced Optimization
    AdaptiveSwarmOptimizer, ConvergenceDetector, EarlyStoppingCriteria,
    DynamicSwarmManager, AdaptiveParameterTuner, optimize_with_enhancements!,
    
    # Communication
    SwarmCommunicationManager, SwarmMessage, MessageType, MessagePriority,
    send_message!, receive_messages!, broadcast_message!, subscribe_to_topic!,
    setup_swarm_communication,
    
    # Shared Memory
    SwarmMemoryManager, store_shared_data!, retrieve_shared_data, cache_computation!,
    share_knowledge!, get_shared_knowledge, create_shared_context, update_context!,
    setup_swarm_memory,
    
    # Task Recovery
    TaskRecoveryManager, SwarmTask, RecoveryStrategy, create_recoverable_task,
    execute_with_recovery!, checkpoint_task!, setup_task_recovery,
    
    # LLM Coordination
    InferenceCoordinator, SwarmIntelligence, CoordinationStrategy,
    create_inference_coordinator, setup_swarm_intelligence, make_coordination_decision!,
    evaluate_optimization_results!,
    
    # Real-World Applications
    PricePredictionExample, RoutingOptimizationExample, PortfolioOptimizationExample,
    run_price_prediction_optimization!, run_routing_optimization!,
    run_portfolio_optimization!,
    
    # Main Integration Functions
    create_enhanced_swarm_system, run_enhanced_swarm_optimization!,
    get_swarm_system_stats, cleanup_swarm_system!

"""
Enhanced swarm system configuration
"""
struct EnhancedSwarmConfig
    # Optimization settings
    swarm_size::Int
    max_iterations::Int
    convergence_tolerance::Float64
    
    # Communication settings
    enable_communication::Bool
    communication_topics::Vector{String}
    
    # Memory settings
    enable_shared_memory::Bool
    max_cache_size_mb::Int
    
    # Recovery settings
    enable_task_recovery::Bool
    max_retries::Int
    
    # LLM coordination settings
    enable_llm_coordination::Bool
    llm_provider::String
    llm_model::String
    analysis_frequency::Int
    
    function EnhancedSwarmConfig(;
        swarm_size::Int=30,
        max_iterations::Int=200,
        convergence_tolerance::Float64=1e-6,
        enable_communication::Bool=true,
        communication_topics::Vector{String}=["coordination", "data_sharing"],
        enable_shared_memory::Bool=true,
        max_cache_size_mb::Int=100,
        enable_task_recovery::Bool=true,
        max_retries::Int=3,
        enable_llm_coordination::Bool=false,
        llm_provider::String="openai",
        llm_model::String="gpt-4o-mini",
        analysis_frequency::Int=10
    )
        new(swarm_size, max_iterations, convergence_tolerance,
            enable_communication, communication_topics,
            enable_shared_memory, max_cache_size_mb,
            enable_task_recovery, max_retries,
            enable_llm_coordination, llm_provider, llm_model, analysis_frequency)
    end
end

"""
Enhanced swarm system that integrates all components
"""
mutable struct EnhancedSwarmSystem
    config::EnhancedSwarmConfig
    swarm_id::String
    agent_ids::Vector{String}
    
    # Core components
    optimizer::Union{AdaptiveSwarmOptimizer, Nothing}
    communication_manager::Union{SwarmCommunicationManager, Nothing}
    memory_manager::Union{SwarmMemoryManager, Nothing}
    recovery_manager::Union{TaskRecoveryManager, Nothing}
    inference_coordinator::Union{InferenceCoordinator, Nothing}
    
    # State
    is_initialized::Bool
    is_running::Bool
    
    function EnhancedSwarmSystem(config::EnhancedSwarmConfig, swarm_id::String, agent_ids::Vector{String})
        new(config, swarm_id, agent_ids, nothing, nothing, nothing, nothing, nothing, false, false)
    end
end

"""
Create and initialize enhanced swarm system
"""
function create_enhanced_swarm_system(config::EnhancedSwarmConfig, 
                                    swarm_id::String, 
                                    agent_ids::Vector{String})::EnhancedSwarmSystem
    system = EnhancedSwarmSystem(config, swarm_id, agent_ids)
    
    @info "Creating enhanced swarm system" swarm_id=swarm_id agents=length(agent_ids)
    
    try
        # Initialize optimizer
        initial_params = Dict{String, Float64}(
            "inertia_weight" => 0.7,
            "cognitive_coeff" => 1.5,
            "social_coeff" => 1.5
        )
        
        param_ranges = Dict{String, Tuple{Float64, Float64}}(
            "inertia_weight" => (0.1, 0.9),
            "cognitive_coeff" => (0.5, 2.5),
            "social_coeff" => (0.5, 2.5)
        )
        
        system.optimizer = AdaptiveSwarmOptimizer(
            config.swarm_size, initial_params,
            parameter_ranges=param_ranges,
            max_iterations=config.max_iterations,
            convergence_tolerance=config.convergence_tolerance,
            verbose=true
        )
        
        # Initialize communication system
        if config.enable_communication
            system.communication_manager = setup_swarm_communication(agent_ids, config.communication_topics)
            @info "Communication system initialized" topics=length(config.communication_topics)
        end
        
        # Initialize shared memory
        if config.enable_shared_memory
            system.memory_manager = setup_swarm_memory(agent_ids, max_cache_size_mb=config.max_cache_size_mb)
            @info "Shared memory system initialized" cache_size_mb=config.max_cache_size_mb
        end
        
        # Initialize task recovery
        if config.enable_task_recovery
            recovery_policy = RecoveryPolicy(max_concurrent_recoveries=5, auto_recovery_enabled=true)
            system.recovery_manager = setup_task_recovery(agent_ids, policy=recovery_policy)
            @info "Task recovery system initialized"
        end
        
        # Initialize LLM coordination
        if config.enable_llm_coordination
            try
                system.inference_coordinator = create_inference_coordinator(
                    llm_provider=config.llm_provider,
                    llm_model=config.llm_model
                )
                setup_swarm_intelligence(system.inference_coordinator, swarm_id,
                                       analysis_frequency=config.analysis_frequency)
                @info "LLM coordination initialized" provider=config.llm_provider model=config.llm_model
            catch e
                @warn "Failed to initialize LLM coordination" error=e
                system.inference_coordinator = nothing
            end
        end
        
        system.is_initialized = true
        @info "Enhanced swarm system created successfully" swarm_id=swarm_id
        
        return system
        
    catch e
        @error "Failed to create enhanced swarm system" swarm_id=swarm_id error=e
        rethrow(e)
    end
end

"""
Run enhanced swarm optimization with all features
"""
function run_enhanced_swarm_optimization!(system::EnhancedSwarmSystem,
                                        objective_function::Function,
                                        initial_population::Vector{Vector{Float64}},
                                        bounds::Vector{Tuple{Float64, Float64}}=Tuple{Float64, Float64}[];
                                        problem_characteristics::Dict{String, Any}=Dict{String, Any}())::Dict{String, Any}
    
    if !system.is_initialized
        throw(ArgumentError("Swarm system not initialized"))
    end
    
    @info "Starting enhanced swarm optimization" swarm_id=system.swarm_id
    system.is_running = true
    
    try
        # Setup optimization callback for LLM coordination
        callback = function(iteration, best_individual, best_fitness, population, parameters)
            # LLM coordination
            if system.inference_coordinator !== nothing && iteration % system.config.analysis_frequency == 0
                try
                    fitness_history = system.optimizer.history.fitness_history
                    diversity = calculate_diversity(population)
                    convergence_rate = length(fitness_history) > 1 ? 
                                     abs(fitness_history[end] - fitness_history[end-1]) : 0.0
                    
                    context = DecisionContext(system.swarm_id, iteration, fitness_history,
                                            diversity, convergence_rate, time(),
                                            problem_chars=problem_characteristics)
                    
                    recommendation = make_coordination_decision!(system.inference_coordinator, system.swarm_id, context)
                    
                    @info "LLM coordination" iteration=iteration strategy=recommendation.recommended_strategy confidence=recommendation.confidence
                    
                    # Apply parameter adjustments if recommended
                    if !isempty(recommendation.parameter_adjustments)
                        for (param, adjustment) in recommendation.parameter_adjustments
                            if haskey(parameters, param)
                                old_value = parameters[param]
                                new_value = clamp(old_value + adjustment, 0.1, 2.0)  # Safe bounds
                                parameters[param] = new_value
                                @debug "Parameter adjusted" param=param old_value=old_value new_value=new_value
                            end
                        end
                    end
                    
                catch e
                    @warn "LLM coordination failed" iteration=iteration error=e
                end
            end
            
            # Communication updates
            if system.communication_manager !== nothing && iteration % 5 == 0
                try
                    status_update = Dict{String, Any}(
                        "iteration" => iteration,
                        "best_fitness" => best_fitness,
                        "diversity" => calculate_diversity(population),
                        "timestamp" => now(UTC)
                    )
                    
                    broadcast_message!(system.communication_manager, "system", "status_updates", status_update)
                catch e
                    @warn "Communication update failed" iteration=iteration error=e
                end
            end
            
            # Memory caching
            if system.memory_manager !== nothing && iteration % 10 == 0
                try
                    cache_key = "optimization_state_$(iteration)"
                    state_data = Dict{String, Any}(
                        "best_individual" => best_individual,
                        "best_fitness" => best_fitness,
                        "parameters" => parameters,
                        "iteration" => iteration
                    )
                    
                    store_shared_data!(system.memory_manager, cache_key, state_data, ttl_seconds=3600)
                catch e
                    @warn "Memory caching failed" iteration=iteration error=e
                end
            end
        end
        
        # Run optimization with enhancements
        start_time = time()
        best_solution, best_fitness = optimize_with_enhancements!(
            system.optimizer, objective_function, initial_population, bounds, callback=callback
        )
        optimization_time = time() - start_time
        
        system.is_running = false
        
        # Collect results
        results = Dict{String, Any}(
            "best_solution" => best_solution,
            "best_fitness" => best_fitness,
            "optimization_time" => optimization_time,
            "iterations" => length(system.optimizer.history.fitness_history),
            "convergence_achieved" => detect_convergence(system.optimizer.convergence_detector),
            "optimization_stats" => get_statistics(system.optimizer.history)
        )
        
        # Add component-specific results
        if system.communication_manager !== nothing
            results["communication_stats"] = get_communication_stats(system.communication_manager)
        end
        
        if system.memory_manager !== nothing
            results["memory_stats"] = get_memory_stats(system.memory_manager)
        end
        
        if system.recovery_manager !== nothing
            results["recovery_stats"] = get_recovery_stats(system.recovery_manager)
        end
        
        if system.inference_coordinator !== nothing
            results["coordination_stats"] = get_coordination_stats(system.inference_coordinator)
            results["intelligent_insights"] = get_intelligent_insights(system.inference_coordinator, system.swarm_id)
        end
        
        @info "Enhanced swarm optimization completed" swarm_id=system.swarm_id best_fitness=best_fitness time=optimization_time
        
        return results
        
    catch e
        system.is_running = false
        @error "Enhanced swarm optimization failed" swarm_id=system.swarm_id error=e
        rethrow(e)
    end
end

"""
Get comprehensive system statistics
"""
function get_swarm_system_stats(system::EnhancedSwarmSystem)::Dict{String, Any}
    stats = Dict{String, Any}(
        "swarm_id" => system.swarm_id,
        "agent_count" => length(system.agent_ids),
        "is_initialized" => system.is_initialized,
        "is_running" => system.is_running,
        "config" => Dict(
            "swarm_size" => system.config.swarm_size,
            "max_iterations" => system.config.max_iterations,
            "features_enabled" => Dict(
                "communication" => system.config.enable_communication,
                "shared_memory" => system.config.enable_shared_memory,
                "task_recovery" => system.config.enable_task_recovery,
                "llm_coordination" => system.config.enable_llm_coordination
            )
        )
    )
    
    # Add component stats if available
    if system.communication_manager !== nothing
        stats["communication"] = get_communication_stats(system.communication_manager)
    end
    
    if system.memory_manager !== nothing
        stats["memory"] = get_memory_stats(system.memory_manager)
    end
    
    if system.recovery_manager !== nothing
        stats["recovery"] = get_recovery_stats(system.recovery_manager)
    end
    
    if system.inference_coordinator !== nothing
        stats["coordination"] = get_coordination_stats(system.inference_coordinator)
    end
    
    return stats
end

"""
Cleanup swarm system resources
"""
function cleanup_swarm_system!(system::EnhancedSwarmSystem)
    @info "Cleaning up swarm system" swarm_id=system.swarm_id
    
    try
        if system.communication_manager !== nothing
            cleanup_communication!(system.communication_manager)
        end
        
        if system.memory_manager !== nothing
            cleanup_memory!(system.memory_manager)
        end
        
        if system.recovery_manager !== nothing
            cleanup_recovery_data!(system.recovery_manager)
        end
        
        system.is_initialized = false
        system.is_running = false
        
        @info "Swarm system cleanup completed" swarm_id=system.swarm_id
        
    catch e
        @error "Error during swarm system cleanup" swarm_id=system.swarm_id error=e
    end
end

end # module SwarmEnhancements
