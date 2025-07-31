"""
RealWorldExamples.jl - Real-world applications for JuliaOS swarm optimization

This module implements practical examples including price prediction optimization,
routing problems, NFT valuation models, and portfolio optimization with real market data.
"""
module RealWorldExamples

using Dates, Statistics, LinearAlgebra, Random, HTTP, JSON3, Logging
using ..SwarmBase
using ..AdvancedScoringFunctions
using ..EnhancedOptimization
using ..SwarmCommunication
using ..InferenceCoordination

export PricePredictionExample, RoutingOptimizationExample, NFTValuationExample,
       PortfolioOptimizationExample, CryptocurrencyTradingExample,
       run_price_prediction_optimization!, run_routing_optimization!,
       run_nft_valuation_optimization!, run_portfolio_optimization!,
       run_cryptocurrency_trading_optimization!, create_market_data_simulator,
       setup_real_world_swarm_optimization

# ============================================================================
# Market Data Simulation and Fetching
# ============================================================================

"""
Market data simulator for testing purposes
"""
struct MarketDataSimulator
    base_price::Float64
    volatility::Float64
    trend::Float64
    noise_level::Float64
    
    function MarketDataSimulator(; base_price::Float64=100.0, volatility::Float64=0.02,
                                trend::Float64=0.001, noise_level::Float64=0.01)
        new(base_price, volatility, trend, noise_level)
    end
end

"""
Generate simulated price data
"""
function generate_price_data(simulator::MarketDataSimulator, n_points::Int)::Vector{Float64}
    prices = Vector{Float64}(undef, n_points)
    prices[1] = simulator.base_price
    
    for i in 2:n_points
        # Geometric Brownian Motion with trend
        dt = 1.0  # Time step
        drift = simulator.trend * dt
        diffusion = simulator.volatility * sqrt(dt) * randn()
        noise = simulator.noise_level * randn()
        
        prices[i] = prices[i-1] * exp(drift + diffusion) + noise
    end
    
    return prices
end

"""
Generate technical indicators from price data
"""
function generate_technical_indicators(prices::Vector{Float64})::Matrix{Float64}
    n = length(prices)
    features = zeros(n, 8)  # 8 technical indicators
    
    for i in 1:n
        # Simple Moving Averages
        sma_5 = i >= 5 ? mean(prices[max(1, i-4):i]) : prices[i]
        sma_20 = i >= 20 ? mean(prices[max(1, i-19):i]) : prices[i]
        
        # Price ratios
        price_ratio_5 = prices[i] / sma_5
        price_ratio_20 = prices[i] / sma_20
        
        # Volatility (rolling standard deviation)
        volatility = i >= 10 ? std(prices[max(1, i-9):i]) : 0.0
        
        # Momentum
        momentum = i >= 5 ? prices[i] - prices[max(1, i-4)] : 0.0
        
        # RSI approximation
        gains = i >= 10 ? sum(max.(diff(prices[max(1, i-9):i]), 0)) : 0.0
        losses = i >= 10 ? sum(abs.(min.(diff(prices[max(1, i-9):i]), 0))) : 1.0
        rsi = 100 - (100 / (1 + gains / max(losses, 1e-8)))
        
        # Volume proxy (random but correlated with price changes)
        volume_proxy = abs(i > 1 ? prices[i] - prices[i-1] : 0.0) * (1 + 0.5 * randn())
        
        features[i, :] = [sma_5, sma_20, price_ratio_5, price_ratio_20, volatility, momentum, rsi, volume_proxy]
    end
    
    return features
end

# ============================================================================
# Price Prediction Optimization Example
# ============================================================================

"""
Price prediction optimization example
"""
struct PricePredictionExample
    historical_prices::Vector{Float64}
    technical_features::Matrix{Float64}
    prediction_horizon::Int
    train_test_split::Float64
    
    function PricePredictionExample(prices::Vector{Float64}; 
                                  prediction_horizon::Int=5,
                                  train_test_split::Float64=0.8)
        features = generate_technical_indicators(prices)
        new(prices, features, prediction_horizon, train_test_split)
    end
end

"""
Run price prediction optimization
"""
function run_price_prediction_optimization!(example::PricePredictionExample;
                                          swarm_size::Int=30,
                                          max_iterations::Int=100,
                                          use_llm_coordination::Bool=true)::Dict{String, Any}
    @info "Starting price prediction optimization" swarm_size=swarm_size max_iterations=max_iterations
    
    # Split data
    n_train = Int(floor(length(example.historical_prices) * example.train_test_split))
    train_prices = example.historical_prices[1:n_train]
    train_features = example.technical_features[1:n_train, :]
    
    # Create objective function
    objective = PricePredictionObjective(train_prices, train_features,
                                       target_horizon=example.prediction_horizon,
                                       loss_function=:mse)
    
    # Set up optimization problem
    n_features = size(train_features, 2)
    bounds = [(-2.0, 2.0) for _ in 1:n_features]  # Parameter bounds
    
    problem = OptimizationProblem(
        dimensions=n_features,
        bounds=bounds,
        is_minimization=true,
        objective_function=objective
    )
    
    # Create enhanced optimizer
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
    
    optimizer = AdaptiveSwarmOptimizer(swarm_size, initial_params,
                                     parameter_ranges=param_ranges,
                                     max_iterations=max_iterations,
                                     convergence_tolerance=1e-6)
    
    # Initialize population
    initial_population = [randn(n_features) for _ in 1:swarm_size]
    
    # Set up LLM coordination if requested
    coordinator = nothing
    if use_llm_coordination
        try
            coordinator = create_inference_coordinator()
            setup_swarm_intelligence(coordinator, "price_prediction_swarm")
        catch e
            @warn "Failed to setup LLM coordination" error=e
            coordinator = nothing
        end
    end
    
    # Optimization callback for LLM coordination
    callback = function(iteration, best_individual, best_fitness, population, parameters)
        if coordinator !== nothing && iteration % 10 == 0
            try
                # Create decision context
                fitness_history = optimizer.history.fitness_history
                diversity = calculate_diversity(population)
                convergence_rate = length(fitness_history) > 1 ? 
                                 abs(fitness_history[end] - fitness_history[end-1]) : 0.0
                
                context = DecisionContext("price_prediction_swarm", iteration, fitness_history,
                                        diversity, convergence_rate, time())
                
                # Get LLM recommendation
                recommendation = make_coordination_decision!(coordinator, "price_prediction_swarm", context)
                
                @info "LLM coordination recommendation" iteration=iteration strategy=recommendation.recommended_strategy confidence=recommendation.confidence
            catch e
                @warn "LLM coordination failed" iteration=iteration error=e
            end
        end
    end
    
    # Run optimization
    start_time = time()
    best_solution, best_fitness = optimize_with_enhancements!(optimizer, objective, initial_population, bounds, callback=callback)
    optimization_time = time() - start_time
    
    # Evaluate on test data
    test_prices = example.historical_prices[n_train+1:end]
    test_features = example.technical_features[n_train+1:end, :]
    
    test_objective = PricePredictionObjective(test_prices, test_features,
                                            target_horizon=example.prediction_horizon,
                                            loss_function=:mse)
    
    test_fitness = test_objective(best_solution)
    
    # Calculate additional metrics
    train_predictions = predict_prices(best_solution, train_features, train_prices, example.prediction_horizon)
    test_predictions = predict_prices(best_solution, test_features, test_prices, example.prediction_horizon)
    
    train_mae = mean(abs.(train_predictions - train_prices[example.prediction_horizon+1:end]))
    test_mae = mean(abs.(test_predictions - test_prices[example.prediction_horizon+1:end]))
    
    results = Dict{String, Any}(
        "best_parameters" => best_solution,
        "train_mse" => best_fitness,
        "test_mse" => test_fitness,
        "train_mae" => train_mae,
        "test_mae" => test_mae,
        "optimization_time" => optimization_time,
        "iterations" => length(optimizer.history.fitness_history),
        "final_diversity" => optimizer.history.diversity_history[end],
        "convergence_achieved" => detect_convergence(optimizer.convergence_detector),
        "optimization_stats" => get_statistics(optimizer.history)
    )
    
    if coordinator !== nothing
        results["llm_coordination_stats"] = get_coordination_stats(coordinator)
        results["intelligent_insights"] = get_intelligent_insights(coordinator, "price_prediction_swarm")
    end
    
    @info "Price prediction optimization completed" train_mse=best_fitness test_mse=test_fitness time=optimization_time
    
    return results
end

"""
Predict prices using optimized parameters
"""
function predict_prices(params::Vector{Float64}, features::Matrix{Float64}, 
                       prices::Vector{Float64}, horizon::Int)::Vector{Float64}
    n_samples = size(features, 1) - horizon
    predictions = Vector{Float64}(undef, n_samples)
    
    for i in 1:n_samples
        predictions[i] = dot(params, features[i, :])
    end
    
    return predictions
end

# ============================================================================
# Routing Optimization Example
# ============================================================================

"""
Routing optimization example (Vehicle Routing Problem)
"""
struct RoutingOptimizationExample
    locations::Matrix{Float64}  # [x, y] coordinates
    demands::Vector{Float64}
    vehicle_capacity::Float64
    depot_location::Vector{Float64}

    function RoutingOptimizationExample(n_locations::Int;
                                      area_size::Float64=100.0,
                                      max_demand::Float64=10.0,
                                      vehicle_capacity::Float64=50.0)
        # Generate random locations
        locations = area_size * rand(n_locations, 2)
        demands = max_demand * rand(n_locations)
        depot = [area_size/2, area_size/2]  # Center depot

        new(locations, demands, vehicle_capacity, depot)
    end
end

"""
Calculate distance matrix for routing problem
"""
function calculate_distance_matrix(example::RoutingOptimizationExample)::Matrix{Float64}
    n = size(example.locations, 1)
    distances = zeros(n, n)

    for i in 1:n
        for j in 1:n
            if i != j
                distances[i, j] = norm(example.locations[i, :] - example.locations[j, :])
            end
        end
    end

    return distances
end

"""
Run routing optimization
"""
function run_routing_optimization!(example::RoutingOptimizationExample;
                                 swarm_size::Int=50,
                                 max_iterations::Int=200,
                                 use_enhanced_features::Bool=true)::Dict{String, Any}
    @info "Starting routing optimization" locations=size(example.locations, 1) swarm_size=swarm_size

    # Calculate distance matrix
    distance_matrix = calculate_distance_matrix(example)

    # Create routing objective
    objective = RoutingObjective(distance_matrix, example.demands,
                               capacities=fill(example.vehicle_capacity, size(example.locations, 1)))

    # Set up optimization problem
    n_locations = length(example.demands)
    bounds = [(0.0, 1.0) for _ in 1:n_locations]  # Continuous representation

    problem = OptimizationProblem(
        dimensions=n_locations,
        bounds=bounds,
        is_minimization=true,
        objective_function=objective
    )

    if use_enhanced_features
        # Use enhanced optimizer
        initial_params = Dict{String, Float64}(
            "crossover_rate" => 0.8,
            "mutation_rate" => 0.1,
            "population_size" => Float64(swarm_size)
        )

        param_ranges = Dict{String, Tuple{Float64, Float64}}(
            "crossover_rate" => (0.5, 0.95),
            "mutation_rate" => (0.05, 0.3)
        )

        optimizer = AdaptiveSwarmOptimizer(swarm_size, initial_params,
                                         parameter_ranges=param_ranges,
                                         max_iterations=max_iterations)

        # Initialize population with heuristic solutions
        initial_population = generate_routing_population(example, swarm_size)

        # Run optimization
        start_time = time()
        best_solution, best_fitness = optimize_with_enhancements!(optimizer, objective, initial_population, bounds)
        optimization_time = time() - start_time

        # Convert solution to route
        route = solution_to_route(best_solution)
        total_distance = best_fitness

        results = Dict{String, Any}(
            "best_route" => route,
            "total_distance" => total_distance,
            "optimization_time" => optimization_time,
            "iterations" => length(optimizer.history.fitness_history),
            "convergence_achieved" => detect_convergence(optimizer.convergence_detector),
            "optimization_stats" => get_statistics(optimizer.history)
        )
    else
        # Simple random search for comparison
        start_time = time()
        best_solution = rand(n_locations)
        best_fitness = objective(best_solution)

        for _ in 1:max_iterations
            candidate = rand(n_locations)
            fitness = objective(candidate)
            if fitness < best_fitness
                best_solution = candidate
                best_fitness = fitness
            end
        end

        optimization_time = time() - start_time
        route = solution_to_route(best_solution)

        results = Dict{String, Any}(
            "best_route" => route,
            "total_distance" => best_fitness,
            "optimization_time" => optimization_time,
            "iterations" => max_iterations,
            "method" => "random_search"
        )
    end

    @info "Routing optimization completed" distance=results["total_distance"] time=optimization_time
    return results
end

"""
Generate initial routing population using heuristics
"""
function generate_routing_population(example::RoutingOptimizationExample, pop_size::Int)::Vector{Vector{Float64}}
    n_locations = length(example.demands)
    population = Vector{Vector{Float64}}()

    for _ in 1:pop_size
        # Generate random permutation and convert to continuous representation
        perm = randperm(n_locations)
        continuous_solution = (perm .- 1) ./ (n_locations - 1)
        push!(population, continuous_solution)
    end

    return population
end

"""
Convert continuous solution to route
"""
function solution_to_route(solution::Vector{Float64})::Vector{Int}
    return sortperm(solution)
end

# ============================================================================
# Portfolio Optimization Example
# ============================================================================

"""
Portfolio optimization example with real market dynamics
"""
struct PortfolioOptimizationExample
    asset_returns::Matrix{Float64}  # Historical returns [time x assets]
    asset_names::Vector{String}
    risk_free_rate::Float64

    function PortfolioOptimizationExample(n_assets::Int, n_periods::Int;
                                        risk_free_rate::Float64=0.02)
        # Generate correlated asset returns
        asset_names = ["Asset_$i" for i in 1:n_assets]

        # Create correlation structure
        correlation_matrix = generate_correlation_matrix(n_assets)

        # Generate returns with realistic properties
        returns = generate_correlated_returns(n_periods, n_assets, correlation_matrix)

        new(returns, asset_names, risk_free_rate)
    end
end

"""
Generate realistic correlation matrix for assets
"""
function generate_correlation_matrix(n_assets::Int)::Matrix{Float64}
    # Start with identity matrix
    corr_matrix = Matrix{Float64}(I, n_assets, n_assets)

    # Add realistic correlations
    for i in 1:n_assets
        for j in (i+1):n_assets
            # Assets closer in index are more correlated
            distance = abs(i - j)
            correlation = 0.1 + 0.4 * exp(-distance / 3) + 0.1 * randn()
            correlation = clamp(correlation, -0.8, 0.8)

            corr_matrix[i, j] = correlation
            corr_matrix[j, i] = correlation
        end
    end

    # Ensure positive definite
    eigenvals, eigenvecs = eigen(corr_matrix)
    eigenvals = max.(eigenvals, 0.01)  # Ensure positive eigenvalues
    corr_matrix = eigenvecs * Diagonal(eigenvals) * eigenvecs'

    # Normalize diagonal to 1
    for i in 1:n_assets
        corr_matrix[i, i] = 1.0
    end

    return corr_matrix
end

"""
Generate correlated asset returns
"""
function generate_correlated_returns(n_periods::Int, n_assets::Int,
                                   correlation_matrix::Matrix{Float64})::Matrix{Float64}
    # Cholesky decomposition for correlation
    L = cholesky(correlation_matrix).L

    # Generate independent random returns
    independent_returns = randn(n_periods, n_assets)

    # Apply correlation structure
    correlated_returns = independent_returns * L'

    # Add realistic return characteristics
    mean_returns = 0.001 .+ 0.002 * randn(n_assets)  # Different expected returns
    volatilities = 0.01 .+ 0.02 * rand(n_assets)     # Different volatilities

    for i in 1:n_assets
        correlated_returns[:, i] = mean_returns[i] .+ volatilities[i] .* correlated_returns[:, i]
    end

    return correlated_returns
end
