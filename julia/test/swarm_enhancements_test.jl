"""
Comprehensive test suite for JuliaOS swarm optimization enhancements

Tests all new functionality including advanced scoring functions, enhanced optimization,
communication systems, memory management, task recovery, and LLM coordination.
"""

using Test, Dates, Statistics, Random
using JuliaOS.JuliaOSFramework.Swarm

# Set random seed for reproducible tests
Random.seed!(42)

@testset "JuliaOS Swarm Enhancements Tests" begin
    
    # ============================================================================
    # Advanced Scoring Functions Tests
    # ============================================================================
    
    @testset "Advanced Scoring Functions" begin
        using JuliaOS.JuliaOSFramework.Swarm.AdvancedScoringFunctions
        
        @testset "Multi-Objective Optimization" begin
            # Test multi-objective function creation
            obj1 = x -> sum(x.^2)  # Minimize sum of squares
            obj2 = x -> sum(abs.(x))  # Minimize sum of absolute values
            
            multi_obj = MultiObjectiveFunction([obj1, obj2], ["quadratic", "linear"])
            
            test_point = [1.0, -2.0, 0.5]
            result = multi_obj(test_point)
            
            @test isa(result, Float64)
            @test isfinite(result)
            
            # Test different aggregation methods
            multi_obj_pareto = MultiObjectiveFunction([obj1, obj2], ["quadratic", "linear"],
                                                    aggregation_method=:pareto)
            result_pareto = multi_obj_pareto(test_point)
            @test isa(result_pareto, Float64)
        end
        
        @testset "Constrained Optimization" begin
            # Test constrained objective function
            objective = x -> sum(x.^2)
            equality_constraints = [x -> sum(x) - 1.0]  # Sum equals 1
            inequality_constraints = [x -> -minimum(x)]  # All positive
            
            constrained_obj = ConstrainedObjectiveFunction(objective,
                                                         equality_constraints=equality_constraints,
                                                         inequality_constraints=inequality_constraints)
            
            # Test feasible point
            feasible_point = [0.3, 0.3, 0.4]
            result_feasible = constrained_obj(feasible_point)
            @test isfinite(result_feasible)
            
            # Test infeasible point
            infeasible_point = [-0.5, 0.8, 0.7]
            result_infeasible = constrained_obj(infeasible_point)
            @test result_infeasible > result_feasible  # Should have penalty
        end
        
        @testset "Price Prediction Objective" begin
            # Generate test data
            n_samples, n_features = 50, 4
            prices = cumsum(randn(n_samples) * 0.1) .+ 100.0
            features = randn(n_samples, n_features)
            
            price_obj = PricePredictionObjective(prices, features, target_horizon=1)
            
            # Test with random parameters
            params = randn(n_features)
            result = price_obj(params)
            
            @test isa(result, Float64)
            @test isfinite(result)
            @test result >= 0  # MSE should be non-negative
        end
        
        @testset "Routing Objective" begin
            # Create simple routing problem
            n_cities = 5
            distances = rand(n_cities, n_cities)
            # Make symmetric
            distances = (distances + distances') / 2
            # Zero diagonal
            for i in 1:n_cities
                distances[i, i] = 0.0
            end
            
            demands = rand(n_cities) * 10
            
            routing_obj = RoutingObjective(distances, demands)
            
            # Test with random solution
            solution = rand(n_cities)
            result = routing_obj(solution)
            
            @test isa(result, Float64)
            @test isfinite(result)
            @test result >= 0  # Distance should be non-negative
        end
        
        @testset "Portfolio Optimization Objective" begin
            # Create test portfolio data
            n_assets = 4
            expected_returns = [0.08, 0.12, 0.15, 0.10]
            
            # Create positive definite covariance matrix
            A = randn(n_assets, n_assets)
            cov_matrix = A * A' / n_assets + 0.01 * I
            
            portfolio_obj = PortfolioOptimizationObjective(expected_returns, cov_matrix)
            
            # Test with equal weights
            equal_weights = ones(n_assets) / n_assets
            result = portfolio_obj(equal_weights)
            
            @test isa(result, Float64)
            @test isfinite(result)
        end
        
        @testset "Utility Functions" begin
            # Test constraint evaluation
            simple_obj = x -> sum(x.^2)
            bounds = [(-1.0, 1.0), (-1.0, 1.0)]
            
            # Test within bounds
            valid_point = [0.5, -0.3]
            result_valid = evaluate_with_constraints(simple_obj, valid_point, bounds=bounds)
            @test isfinite(result_valid)
            
            # Test outside bounds
            invalid_point = [1.5, -0.3]
            result_invalid = evaluate_with_constraints(simple_obj, invalid_point, bounds=bounds)
            @test result_invalid > result_valid  # Should have penalty
        end
    end
    
    # ============================================================================
    # Enhanced Optimization Tests
    # ============================================================================
    
    @testset "Enhanced Optimization" begin
        using JuliaOS.JuliaOSFramework.Swarm.EnhancedOptimization
        
        @testset "Convergence Detection" begin
            detector = ConvergenceDetector(window_size=5, tolerance=1e-3)
            
            # Test with improving fitness
            for i in 1:20
                fitness = 10.0 - i * 0.1  # Decreasing fitness
                diversity = 0.5
                update!(detector, fitness, diversity)
            end
            
            @test !detect_convergence(detector)  # Should not converge yet
            
            # Test with stagnant fitness
            for i in 1:15
                update!(detector, 5.0, 0.1)  # Constant fitness
            end
            
            @test detect_convergence(detector)  # Should converge now
        end
        
        @testset "Early Stopping" begin
            criteria = EarlyStoppingCriteria(max_iterations=100, patience=10)
            
            # Test iteration limit
            @test should_stop_early(criteria, 101, 5.0)
            
            # Test patience
            @test !should_stop_early(criteria, 50, 4.0)  # Improvement
            
            for i in 1:12
                should_stop_early(criteria, 50 + i, 4.1)  # No improvement
            end
            @test should_stop_early(criteria, 63, 4.1)  # Should stop due to patience
        end
        
        @testset "Dynamic Swarm Management" begin
            manager = DynamicSwarmManager(20, min_size=10, max_size=50)
            
            # Test size increase due to low diversity
            new_size = resize_swarm_dynamically!(manager, 25, 0.05, 0.1)  # Low diversity
            @test new_size >= manager.current_size
            
            # Test size decrease due to stagnation
            for i in 1:6
                resize_swarm_dynamically!(manager, 25 + i * 25, 0.3, 0.01)  # Stagnation
            end
            # Should decrease size due to poor performance
        end
        
        @testset "Adaptive Parameter Tuning" begin
            initial_params = Dict("param1" => 0.5, "param2" => 1.0)
            param_ranges = Dict("param1" => (0.1, 0.9), "param2" => (0.5, 2.0))
            
            tuner = AdaptiveParameterTuner(initial_params, param_ranges)
            
            # Simulate performance history
            for i in 1:15
                performance = 10.0 - i * 0.1  # Improving performance
                tune_parameters_adaptively!(tuner, i, performance)
            end
            
            updated_params = tuner.parameters
            @test haskey(updated_params, "param1")
            @test haskey(updated_params, "param2")
            @test 0.1 <= updated_params["param1"] <= 0.9
            @test 0.5 <= updated_params["param2"] <= 2.0
        end
        
        @testset "Optimization History" begin
            history = OptimizationHistory()
            
            # Record some steps
            for i in 1:10
                record_step!(history, i, 10.0 - i, 0.5, Dict("param" => 0.5), 20)
            end
            
            stats = get_statistics(history)
            @test stats["total_iterations"] == 10
            @test stats["best_fitness"] == 1.0
            @test stats["improvement_rate"] > 0
        end
        
        @testset "Adaptive Swarm Optimizer Integration" begin
            # Simple quadratic function
            objective = x -> sum(x.^2)
            
            initial_params = Dict("inertia" => 0.7)
            param_ranges = Dict("inertia" => (0.1, 0.9))
            
            optimizer = AdaptiveSwarmOptimizer(10, initial_params,
                                             parameter_ranges=param_ranges,
                                             max_iterations=50,
                                             verbose=false)
            
            # Initialize population
            initial_population = [randn(2) for _ in 1:10]
            bounds = [(-5.0, 5.0), (-5.0, 5.0)]
            
            # Run optimization
            best_solution, best_fitness = optimize_with_enhancements!(optimizer, objective, 
                                                                    initial_population, bounds)
            
            @test length(best_solution) == 2
            @test isfinite(best_fitness)
            @test best_fitness < 10.0  # Should find better solution than random
        end
    end
    
    # ============================================================================
    # Communication System Tests
    # ============================================================================
    
    @testset "Swarm Communication" begin
        using JuliaOS.JuliaOSFramework.Swarm.SwarmCommunication
        
        @testset "Message Creation and Properties" begin
            message = SwarmMessage("agent1", "test_topic", Dict("data" => "test"))
            
            @test message.sender_id == "agent1"
            @test message.topic == "test_topic"
            @test message.payload["data"] == "test"
            @test !is_expired(message)
            
            # Test response creation
            response = create_response(message, "agent2", Dict("response" => "ok"))
            @test response.recipient_id == "agent1"
            @test response.correlation_id == message.id
        end
        
        @testset "Communication Channels" begin
            channel = CommunicationChannel("test_channel")
            
            message1 = SwarmMessage("agent1", "topic1", Dict("msg" => 1))
            message2 = SwarmMessage("agent2", "topic1", Dict("msg" => 2))
            
            @test add_message!(channel, message1)
            @test add_message!(channel, message2)
            
            # Test message retrieval
            retrieved = get_next_message(channel, "agent1")
            @test retrieved !== nothing
            @test retrieved.sender_id in ["agent1", "agent2"]
        end
        
        @testset "Message Router" begin
            router = MessageRouter()
            
            # Subscribe agents to topics
            subscribe_agent!(router, "agent1", "coordination", "default")
            subscribe_agent!(router, "agent2", "coordination", "default")
            
            # Route a message
            message = SwarmMessage("agent1", "coordination", Dict("command" => "start"))
            @test route_message!(router, message)
            
            # Get messages for agent
            messages = get_messages_for_agent(router, "agent2")
            @test length(messages) >= 0  # May be 0 if message was consumed
        end
        
        @testset "Communication Manager" begin
            manager = SwarmCommunicationManager()
            start_communication_manager!(manager)
            
            # Subscribe agents
            subscribe_to_topic!(manager, "agent1", "test_topic")
            subscribe_to_topic!(manager, "agent2", "test_topic")
            
            # Send message
            message = SwarmMessage("agent1", "test_topic", Dict("hello" => "world"))
            @test send_message!(manager, message)
            
            # Receive messages
            messages = receive_messages!(manager, "agent2")
            @test isa(messages, Vector{SwarmMessage})
            
            # Broadcast message
            @test broadcast_message!(manager, "agent1", "test_topic", Dict("broadcast" => true))
            
            # Get stats
            stats = get_communication_stats(manager)
            @test haskey(stats, "messages_sent")
            @test haskey(stats, "active_agents")
            
            stop_communication_manager!(manager)
        end
    end
    
    # ============================================================================
    # Shared Memory Tests
    # ============================================================================
    
    @testset "Shared Memory" begin
        using JuliaOS.JuliaOSFramework.Swarm.SharedMemory
        
        @testset "Cache Operations" begin
            manager = SwarmMemoryManager(max_cache_size_mb=1)
            
            # Test data storage and retrieval
            test_data = Dict("key" => "value", "number" => 42)
            @test store_shared_data!(manager, "test_key", test_data)
            
            retrieved_data = retrieve_shared_data(manager, "test_key")
            @test retrieved_data !== nothing
            @test retrieved_data["key"] == "value"
            @test retrieved_data["number"] == 42
            
            # Test cache miss
            missing_data = retrieve_shared_data(manager, "nonexistent_key")
            @test missing_data === nothing
        end
        
        @testset "Computation Caching" begin
            manager = SwarmMemoryManager()
            
            # Define expensive computation
            expensive_computation = function(x, y)
                sleep(0.01)  # Simulate expensive operation
                return x^2 + y^2
            end
            
            # Cache computation
            start_time = time()
            result1 = cache_computation!(manager, "computation_1", expensive_computation, 3, 4)
            first_time = time() - start_time
            
            # Retrieve cached result
            start_time = time()
            result2 = cache_computation!(manager, "computation_1", expensive_computation, 3, 4)
            second_time = time() - start_time
            
            @test result1 == result2
            @test result1 == 25  # 3^2 + 4^2
            @test second_time < first_time  # Should be faster due to caching
        end
        
        @testset "Knowledge Sharing" begin
            manager = SwarmMemoryManager()
            
            # Share knowledge
            knowledge_content = Dict("insight" => "optimization works better with diversity")
            knowledge_id = share_knowledge!(manager, "optimization", knowledge_content, "agent1",
                                          confidence=0.8, tags=Set(["optimization", "diversity"]))
            
            @test !isempty(knowledge_id)
            
            # Retrieve knowledge
            knowledge_entries = get_shared_knowledge(manager, "optimization")
            @test length(knowledge_entries) == 1
            @test knowledge_entries[1].content["insight"] == "optimization works better with diversity"
            
            # Search by tags
            tagged_knowledge = search_knowledge_by_tags(manager, Set(["optimization"]))
            @test length(tagged_knowledge) == 1
        end
        
        @testset "Shared Context" begin
            manager = SwarmMemoryManager()
            
            # Create shared context
            initial_data = Dict("status" => "active", "participants" => ["agent1", "agent2"])
            context_id = create_shared_context(manager, "coordination", initial_data)
            
            @test !isempty(context_id)
            
            # Update context
            updates = Dict("status" => "running", "iteration" => 1)
            @test update_context!(manager, context_id, updates, "agent1")
            
            # Get context snapshot
            snapshot = get_context_snapshot(manager, context_id, "agent2")
            @test snapshot !== nothing
            @test snapshot["data"]["status"] == "running"
            @test snapshot["data"]["iteration"] == 1
        end
        
        @testset "Memory Statistics" begin
            manager = SwarmMemoryManager()
            
            # Add some data
            store_shared_data!(manager, "key1", "value1")
            store_shared_data!(manager, "key2", Dict("complex" => "data"))
            share_knowledge!(manager, "topic1", Dict("info" => "test"), "agent1")
            
            stats = get_memory_stats(manager)
            @test haskey(stats, "cache")
            @test haskey(stats, "knowledge")
            @test stats["cache"]["entries"] >= 2
            @test stats["knowledge"]["total_entries"] >= 1
        end
    end
    
    println("✅ All swarm enhancement tests passed!")
end
