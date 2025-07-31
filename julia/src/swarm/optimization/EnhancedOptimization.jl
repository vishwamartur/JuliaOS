"""
EnhancedOptimization.jl - Advanced optimization algorithms for JuliaOS swarm intelligence

This module provides enhanced optimization capabilities including early stopping,
dynamic swarm resizing, adaptive parameter tuning, and convergence detection.
"""
module EnhancedOptimization

using Statistics, LinearAlgebra, Random
using Dates, Logging
using ..SwarmBase

export AdaptiveSwarmOptimizer, ConvergenceDetector, EarlyStoppingCriteria,
       DynamicSwarmManager, AdaptiveParameterTuner, OptimizationHistory,
       optimize_with_enhancements!, detect_convergence, should_stop_early,
       resize_swarm_dynamically!, tune_parameters_adaptively!

# ============================================================================
# Convergence Detection
# ============================================================================

"""
Convergence detection for optimization algorithms
"""
mutable struct ConvergenceDetector
    fitness_history::Vector{Float64}
    diversity_history::Vector{Float64}
    window_size::Int
    tolerance::Float64
    min_iterations::Int
    stagnation_threshold::Int
    
    function ConvergenceDetector(;window_size::Int=10, tolerance::Float64=1e-6,
                               min_iterations::Int=50, stagnation_threshold::Int=20)
        new(Float64[], Float64[], window_size, tolerance, min_iterations, stagnation_threshold)
    end
end

"""
Update convergence detector with new fitness and diversity values
"""
function update!(detector::ConvergenceDetector, fitness::Float64, diversity::Float64)
    push!(detector.fitness_history, fitness)
    push!(detector.diversity_history, diversity)
    
    # Keep only recent history to prevent memory growth
    max_history = 1000
    if length(detector.fitness_history) > max_history
        detector.fitness_history = detector.fitness_history[end-max_history+1:end]
        detector.diversity_history = detector.diversity_history[end-max_history+1:end]
    end
end

"""
Check if optimization has converged
"""
function detect_convergence(detector::ConvergenceDetector)::Bool
    history_length = length(detector.fitness_history)
    
    # Need minimum iterations
    if history_length < detector.min_iterations
        return false
    end
    
    # Check fitness stagnation
    if history_length >= detector.window_size
        recent_fitness = detector.fitness_history[end-detector.window_size+1:end]
        fitness_range = maximum(recent_fitness) - minimum(recent_fitness)
        
        if fitness_range < detector.tolerance
            return true
        end
    end
    
    # Check for prolonged stagnation
    if history_length >= detector.stagnation_threshold
        recent_best = minimum(detector.fitness_history[end-detector.stagnation_threshold+1:end])
        older_best = minimum(detector.fitness_history[end-2*detector.stagnation_threshold+1:end-detector.stagnation_threshold])
        
        if abs(recent_best - older_best) < detector.tolerance
            return true
        end
    end
    
    return false
end

# ============================================================================
# Early Stopping Criteria
# ============================================================================

"""
Early stopping criteria for optimization
"""
mutable struct EarlyStoppingCriteria
    max_iterations::Int
    max_time_seconds::Float64
    target_fitness::Float64
    patience::Int
    improvement_threshold::Float64
    
    # Internal state
    start_time::Float64
    iterations_without_improvement::Int
    best_fitness::Float64
    
    function EarlyStoppingCriteria(;max_iterations::Int=1000, max_time_seconds::Float64=3600.0,
                                 target_fitness::Float64=-Inf, patience::Int=50,
                                 improvement_threshold::Float64=1e-4)
        new(max_iterations, max_time_seconds, target_fitness, patience, improvement_threshold,
            time(), 0, Inf)
    end
end

"""
Check if optimization should stop early
"""
function should_stop_early(criteria::EarlyStoppingCriteria, iteration::Int, current_fitness::Float64)::Bool
    # Check iteration limit
    if iteration >= criteria.max_iterations
        @info "Stopping: Maximum iterations reached" iterations=iteration
        return true
    end
    
    # Check time limit
    elapsed_time = time() - criteria.start_time
    if elapsed_time >= criteria.max_time_seconds
        @info "Stopping: Time limit reached" elapsed_time=elapsed_time
        return true
    end
    
    # Check target fitness
    if current_fitness <= criteria.target_fitness
        @info "Stopping: Target fitness reached" fitness=current_fitness target=criteria.target_fitness
        return true
    end
    
    # Check patience (no improvement)
    if current_fitness < criteria.best_fitness - criteria.improvement_threshold
        criteria.best_fitness = current_fitness
        criteria.iterations_without_improvement = 0
    else
        criteria.iterations_without_improvement += 1
    end
    
    if criteria.iterations_without_improvement >= criteria.patience
        @info "Stopping: No improvement for too long" patience=criteria.patience
        return true
    end
    
    return false
end

# ============================================================================
# Dynamic Swarm Management
# ============================================================================

"""
Dynamic swarm size management
"""
mutable struct DynamicSwarmManager
    min_size::Int
    max_size::Int
    resize_frequency::Int
    diversity_threshold::Float64
    performance_threshold::Float64
    
    # Internal state
    current_size::Int
    last_resize_iteration::Int
    performance_history::Vector{Float64}
    
    function DynamicSwarmManager(initial_size::Int; min_size::Int=10, max_size::Int=100,
                               resize_frequency::Int=25, diversity_threshold::Float64=0.1,
                               performance_threshold::Float64=0.05)
        new(min_size, max_size, resize_frequency, diversity_threshold, performance_threshold,
            initial_size, 0, Float64[])
    end
end

"""
Decide if swarm should be resized and return new size
"""
function resize_swarm_dynamically!(manager::DynamicSwarmManager, iteration::Int,
                                 current_diversity::Float64, current_performance::Float64)::Int
    # Only resize at specified intervals
    if iteration - manager.last_resize_iteration < manager.resize_frequency
        return manager.current_size
    end
    
    push!(manager.performance_history, current_performance)
    
    # Keep limited history
    if length(manager.performance_history) > 20
        manager.performance_history = manager.performance_history[end-19:end]
    end
    
    new_size = manager.current_size
    
    # Increase size if diversity is too low
    if current_diversity < manager.diversity_threshold && manager.current_size < manager.max_size
        new_size = min(manager.max_size, manager.current_size + 5)
        @info "Increasing swarm size due to low diversity" old_size=manager.current_size new_size=new_size diversity=current_diversity
    end
    
    # Decrease size if performance is stagnating
    if length(manager.performance_history) >= 5
        recent_improvement = manager.performance_history[end] - manager.performance_history[end-4]
        if abs(recent_improvement) < manager.performance_threshold && manager.current_size > manager.min_size
            new_size = max(manager.min_size, manager.current_size - 3)
            @info "Decreasing swarm size due to stagnation" old_size=manager.current_size new_size=new_size improvement=recent_improvement
        end
    end
    
    if new_size != manager.current_size
        manager.current_size = new_size
        manager.last_resize_iteration = iteration
    end
    
    return new_size
end

# ============================================================================
# Adaptive Parameter Tuning
# ============================================================================

"""
Adaptive parameter tuning for optimization algorithms
"""
mutable struct AdaptiveParameterTuner
    parameters::Dict{String, Float64}
    parameter_ranges::Dict{String, Tuple{Float64, Float64}}
    adaptation_rate::Float64
    performance_window::Int
    
    # Internal state
    performance_history::Vector{Float64}
    parameter_history::Dict{String, Vector{Float64}}
    last_update_iteration::Int
    
    function AdaptiveParameterTuner(initial_params::Dict{String, Float64},
                                  param_ranges::Dict{String, Tuple{Float64, Float64}};
                                  adaptation_rate::Float64=0.1, performance_window::Int=10)
        param_history = Dict(k => [v] for (k, v) in initial_params)
        new(initial_params, param_ranges, adaptation_rate, performance_window,
            Float64[], param_history, 0)
    end
end

"""
Adaptively tune parameters based on performance
"""
function tune_parameters_adaptively!(tuner::AdaptiveParameterTuner, iteration::Int,
                                    current_performance::Float64)::Dict{String, Float64}
    push!(tuner.performance_history, current_performance)
    
    # Only tune every few iterations
    if iteration - tuner.last_update_iteration < 5
        return tuner.parameters
    end
    
    # Need enough history for adaptation
    if length(tuner.performance_history) < tuner.performance_window
        return tuner.parameters
    end
    
    # Calculate performance trend
    recent_performance = tuner.performance_history[end-tuner.performance_window+1:end]
    performance_trend = (recent_performance[end] - recent_performance[1]) / tuner.performance_window
    
    # Adapt parameters based on performance
    for (param_name, current_value) in tuner.parameters
        if haskey(tuner.parameter_ranges, param_name)
            min_val, max_val = tuner.parameter_ranges[param_name]
            
            # If performance is improving, make smaller adjustments
            # If performance is stagnating, make larger adjustments
            adjustment_factor = performance_trend < -1e-6 ? 0.5 : 1.5
            adjustment = tuner.adaptation_rate * adjustment_factor * (rand() - 0.5)
            
            new_value = clamp(current_value + adjustment, min_val, max_val)
            tuner.parameters[param_name] = new_value
            
            # Record parameter history
            push!(tuner.parameter_history[param_name], new_value)
            
            # Keep limited history
            if length(tuner.parameter_history[param_name]) > 50
                tuner.parameter_history[param_name] = tuner.parameter_history[param_name][end-49:end]
            end
        end
    end
    
    tuner.last_update_iteration = iteration
    
    # Keep limited performance history
    if length(tuner.performance_history) > 100
        tuner.performance_history = tuner.performance_history[end-99:end]
    end
    
    return tuner.parameters
end

# ============================================================================
# Optimization History and Monitoring
# ============================================================================

"""
Track optimization history and statistics
"""
mutable struct OptimizationHistory
    fitness_history::Vector{Float64}
    diversity_history::Vector{Float64}
    parameter_history::Vector{Dict{String, Float64}}
    swarm_size_history::Vector{Int}
    timestamps::Vector{DateTime}
    convergence_events::Vector{Tuple{Int, String}}

    function OptimizationHistory()
        new(Float64[], Float64[], Dict{String, Float64}[], Int[], DateTime[],
            Tuple{Int, String}[])
    end
end

"""
Record optimization step in history
"""
function record_step!(history::OptimizationHistory, iteration::Int, fitness::Float64,
                     diversity::Float64, parameters::Dict{String, Float64},
                     swarm_size::Int, event::String="")
    push!(history.fitness_history, fitness)
    push!(history.diversity_history, diversity)
    push!(history.parameter_history, copy(parameters))
    push!(history.swarm_size_history, swarm_size)
    push!(history.timestamps, now())

    if !isempty(event)
        push!(history.convergence_events, (iteration, event))
    end
end

"""
Get optimization statistics
"""
function get_statistics(history::OptimizationHistory)::Dict{String, Any}
    if isempty(history.fitness_history)
        return Dict("status" => "no_data")
    end

    return Dict(
        "total_iterations" => length(history.fitness_history),
        "best_fitness" => minimum(history.fitness_history),
        "final_fitness" => history.fitness_history[end],
        "average_diversity" => mean(history.diversity_history),
        "final_diversity" => history.diversity_history[end],
        "convergence_events" => length(history.convergence_events),
        "total_time" => history.timestamps[end] - history.timestamps[1],
        "improvement_rate" => (history.fitness_history[1] - history.fitness_history[end]) / length(history.fitness_history)
    )
end

# ============================================================================
# Main Enhanced Optimizer
# ============================================================================

"""
Enhanced swarm optimizer with all advanced features
"""
mutable struct AdaptiveSwarmOptimizer
    convergence_detector::ConvergenceDetector
    early_stopping::EarlyStoppingCriteria
    swarm_manager::DynamicSwarmManager
    parameter_tuner::AdaptiveParameterTuner
    history::OptimizationHistory

    # Configuration
    verbose::Bool
    save_history::Bool

    function AdaptiveSwarmOptimizer(initial_swarm_size::Int, initial_parameters::Dict{String, Float64};
                                  parameter_ranges::Dict{String, Tuple{Float64, Float64}}=Dict{String, Tuple{Float64, Float64}}(),
                                  verbose::Bool=true, save_history::Bool=true,
                                  convergence_tolerance::Float64=1e-6,
                                  max_iterations::Int=1000,
                                  max_time_seconds::Float64=3600.0)

        convergence_detector = ConvergenceDetector(tolerance=convergence_tolerance)
        early_stopping = EarlyStoppingCriteria(max_iterations=max_iterations, max_time_seconds=max_time_seconds)
        swarm_manager = DynamicSwarmManager(initial_swarm_size)
        parameter_tuner = AdaptiveParameterTuner(initial_parameters, parameter_ranges)
        history = OptimizationHistory()

        new(convergence_detector, early_stopping, swarm_manager, parameter_tuner, history,
            verbose, save_history)
    end
end

"""
Main optimization loop with all enhancements
"""
function optimize_with_enhancements!(optimizer::AdaptiveSwarmOptimizer,
                                    objective_function::Function,
                                    initial_population::Vector{Vector{Float64}},
                                    bounds::Vector{Tuple{Float64, Float64}}=Tuple{Float64, Float64}[];
                                    callback::Function=(args...) -> nothing)::Tuple{Vector{Float64}, Float64}

    if optimizer.verbose
        @info "Starting enhanced swarm optimization" initial_size=length(initial_population)
    end

    # Initialize population
    population = copy(initial_population)
    fitness_values = [objective_function(individual) for individual in population]

    best_individual = population[argmin(fitness_values)]
    best_fitness = minimum(fitness_values)

    iteration = 0

    while true
        iteration += 1

        # Calculate current diversity
        current_diversity = calculate_diversity(population)

        # Update convergence detector
        update!(optimizer.convergence_detector, best_fitness, current_diversity)

        # Check for convergence
        if detect_convergence(optimizer.convergence_detector)
            if optimizer.verbose
                @info "Optimization converged" iteration=iteration fitness=best_fitness
            end
            if optimizer.save_history
                record_step!(optimizer.history, iteration, best_fitness, current_diversity,
                           optimizer.parameter_tuner.parameters, length(population), "converged")
            end
            break
        end

        # Check early stopping criteria
        if should_stop_early(optimizer.early_stopping, iteration, best_fitness)
            if optimizer.save_history
                record_step!(optimizer.history, iteration, best_fitness, current_diversity,
                           optimizer.parameter_tuner.parameters, length(population), "early_stop")
            end
            break
        end

        # Adaptive parameter tuning
        current_parameters = tune_parameters_adaptively!(optimizer.parameter_tuner, iteration, best_fitness)

        # Dynamic swarm resizing
        new_size = resize_swarm_dynamically!(optimizer.swarm_manager, iteration, current_diversity, best_fitness)

        if new_size != length(population)
            population = resize_population(population, fitness_values, new_size, bounds)
            fitness_values = [objective_function(individual) for individual in population]
        end

        # Record history
        if optimizer.save_history
            record_step!(optimizer.history, iteration, best_fitness, current_diversity,
                       current_parameters, length(population))
        end

        # Update best solution
        current_best_idx = argmin(fitness_values)
        if fitness_values[current_best_idx] < best_fitness
            best_individual = copy(population[current_best_idx])
            best_fitness = fitness_values[current_best_idx]
        end

        # Call user callback
        callback(iteration, best_individual, best_fitness, population, current_parameters)

        # Verbose logging
        if optimizer.verbose && iteration % 10 == 0
            @info "Optimization progress" iteration=iteration best_fitness=best_fitness diversity=current_diversity swarm_size=length(population)
        end
    end

    if optimizer.verbose
        stats = get_statistics(optimizer.history)
        @info "Optimization completed" stats
    end

    return best_individual, best_fitness
end

"""
Calculate population diversity (average pairwise distance)
"""
function calculate_diversity(population::Vector{Vector{Float64}})::Float64
    if length(population) < 2
        return 0.0
    end

    total_distance = 0.0
    count = 0

    for i in 1:length(population)
        for j in (i+1):length(population)
            distance = norm(population[i] - population[j])
            total_distance += distance
            count += 1
        end
    end

    return count > 0 ? total_distance / count : 0.0
end

"""
Resize population to new size
"""
function resize_population(population::Vector{Vector{Float64}}, fitness_values::Vector{Float64},
                         new_size::Int, bounds::Vector{Tuple{Float64, Float64}})::Vector{Vector{Float64}}
    current_size = length(population)

    if new_size == current_size
        return population
    elseif new_size < current_size
        # Remove worst individuals
        sorted_indices = sortperm(fitness_values)
        return population[sorted_indices[1:new_size]]
    else
        # Add new individuals
        new_population = copy(population)
        dimension = length(population[1])

        for _ in 1:(new_size - current_size)
            if isempty(bounds)
                # Random initialization
                new_individual = randn(dimension)
            else
                # Random within bounds
                new_individual = [rand() * (upper - lower) + lower for (lower, upper) in bounds]
            end
            push!(new_population, new_individual)
        end

        return new_population
    end
end

end # module EnhancedOptimization
