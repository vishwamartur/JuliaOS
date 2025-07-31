"""
InferenceCoordination.jl - LLM-based inference coordination for JuliaOS swarms

This module integrates LLM-based evaluation of optimization results, intelligent
decision making for swarm coordination, and adaptive strategy selection.
"""
module InferenceCoordination

using Dates, JSON3, Logging, Statistics
using ..SwarmBase
using ...Agents.LLMIntegration

export InferenceCoordinator, SwarmIntelligence, DecisionContext,
       StrategyRecommendation, InferenceResult, CoordinationStrategy,
       create_inference_coordinator, evaluate_optimization_results!,
       make_coordination_decision!, recommend_strategy_adaptation!,
       analyze_swarm_performance!, get_intelligent_insights,
       setup_swarm_intelligence

# ============================================================================
# Decision Context and Strategy Types
# ============================================================================

@enum CoordinationStrategy begin
    EXPLORATION_FOCUSED = 1    # Focus on exploring new areas
    EXPLOITATION_FOCUSED = 2   # Focus on refining current best solutions
    BALANCED_APPROACH = 3      # Balance exploration and exploitation
    DIVERSIFICATION = 4        # Increase population diversity
    INTENSIFICATION = 5        # Concentrate search around best solutions
    ADAPTIVE_HYBRID = 6        # Dynamically adapt strategy
end

"""
Decision context for LLM-based coordination
"""
struct DecisionContext
    swarm_id::String
    current_iteration::Int
    optimization_history::Vector{Float64}
    population_diversity::Float64
    convergence_rate::Float64
    time_elapsed::Float64
    resource_usage::Dict{String, Float64}
    agent_performance::Dict{String, Float64}
    problem_characteristics::Dict{String, Any}
    
    function DecisionContext(swarm_id::String, iteration::Int, history::Vector{Float64},
                           diversity::Float64, convergence::Float64, elapsed::Float64;
                           resources::Dict{String, Float64}=Dict{String, Float64}(),
                           agent_perf::Dict{String, Float64}=Dict{String, Float64}(),
                           problem_chars::Dict{String, Any}=Dict{String, Any}())
        new(swarm_id, iteration, history, diversity, convergence, elapsed,
            resources, agent_perf, problem_chars)
    end
end

"""
Strategy recommendation from LLM analysis
"""
struct StrategyRecommendation
    recommended_strategy::CoordinationStrategy
    confidence::Float64
    reasoning::String
    parameter_adjustments::Dict{String, Float64}
    expected_improvement::Float64
    risk_assessment::String
    
    function StrategyRecommendation(strategy::CoordinationStrategy, confidence::Float64,
                                  reasoning::String;
                                  params::Dict{String, Float64}=Dict{String, Float64}(),
                                  improvement::Float64=0.0,
                                  risk::String="medium")
        new(strategy, confidence, reasoning, params, improvement, risk)
    end
end

"""
Inference result from LLM evaluation
"""
struct InferenceResult
    analysis_type::String
    insights::Vector{String}
    recommendations::Vector{String}
    confidence_scores::Dict{String, Float64}
    metadata::Dict{String, Any}
    generated_at::DateTime
    
    function InferenceResult(analysis_type::String, insights::Vector{String},
                           recommendations::Vector{String};
                           confidence::Dict{String, Float64}=Dict{String, Float64}(),
                           metadata::Dict{String, Any}=Dict{String, Any}())
        new(analysis_type, insights, recommendations, confidence, metadata, now(UTC))
    end
end

# ============================================================================
# Swarm Intelligence System
# ============================================================================

"""
Swarm intelligence coordinator using LLM-based analysis
"""
mutable struct SwarmIntelligence
    swarm_id::String
    llm_config::Dict{String, Any}
    decision_history::Vector{Tuple{DateTime, DecisionContext, StrategyRecommendation}}
    performance_metrics::Dict{String, Vector{Float64}}
    learning_memory::Dict{String, Any}
    
    # Configuration
    analysis_frequency::Int  # Analyze every N iterations
    confidence_threshold::Float64
    max_history_size::Int
    
    function SwarmIntelligence(swarm_id::String, llm_config::Dict{String, Any};
                             analysis_frequency::Int=10,
                             confidence_threshold::Float64=0.7,
                             max_history_size::Int=1000)
        new(swarm_id, llm_config, 
            Tuple{DateTime, DecisionContext, StrategyRecommendation}[],
            Dict{String, Vector{Float64}}(),
            Dict{String, Any}(),
            analysis_frequency, confidence_threshold, max_history_size)
    end
end

"""
Main inference coordinator
"""
mutable struct InferenceCoordinator
    swarm_intelligences::Dict{String, SwarmIntelligence}
    global_insights::Dict{String, Any}
    coordination_patterns::Dict{String, Vector{String}}
    
    # LLM Integration
    llm_provider::String
    llm_model::String
    default_llm_config::Dict{String, Any}
    
    # Statistics
    total_analyses::Int
    successful_recommendations::Int
    
    function InferenceCoordinator(; llm_provider::String="openai",
                                llm_model::String="gpt-4o-mini",
                                llm_config::Dict{String, Any}=Dict{String, Any}())
        default_config = Dict{String, Any}(
            "provider" => llm_provider,
            "model" => llm_model,
            "temperature" => 0.3,
            "max_tokens" => 1000
        )
        merge!(default_config, llm_config)
        
        new(Dict{String, SwarmIntelligence}(), Dict{String, Any}(), 
            Dict{String, Vector{String}}(),
            llm_provider, llm_model, default_config, 0, 0)
    end
end

# ============================================================================
# LLM-Based Analysis Functions
# ============================================================================

"""
Evaluate optimization results using LLM analysis
"""
function evaluate_optimization_results!(coordinator::InferenceCoordinator,
                                      swarm_id::String, context::DecisionContext)::InferenceResult
    if !haskey(coordinator.swarm_intelligences, swarm_id)
        @warn "Swarm intelligence not found" swarm_id=swarm_id
        return InferenceResult("error", ["Swarm not found"], ["Initialize swarm intelligence"])
    end
    
    intelligence = coordinator.swarm_intelligences[swarm_id]
    
    # Prepare analysis prompt
    analysis_prompt = create_optimization_analysis_prompt(context)
    
    try
        # Get LLM analysis
        llm_response = query_llm_for_analysis(coordinator, analysis_prompt)
        
        # Parse LLM response
        insights, recommendations, confidence_scores = parse_llm_analysis(llm_response)
        
        result = InferenceResult("optimization_evaluation", insights, recommendations,
                               confidence=confidence_scores,
                               metadata=Dict("context" => context, "llm_response" => llm_response))
        
        coordinator.total_analyses += 1
        @info "Optimization results evaluated" swarm_id=swarm_id insights=length(insights)
        
        return result
        
    catch e
        @error "Failed to evaluate optimization results" swarm_id=swarm_id error=e
        return InferenceResult("error", ["Analysis failed: $(string(e))"], 
                             ["Check LLM configuration and try again"])
    end
end

"""
Make coordination decision using LLM intelligence
"""
function make_coordination_decision!(coordinator::InferenceCoordinator,
                                   swarm_id::String, context::DecisionContext)::StrategyRecommendation
    if !haskey(coordinator.swarm_intelligences, swarm_id)
        return StrategyRecommendation(BALANCED_APPROACH, 0.5, "Default strategy - swarm intelligence not initialized")
    end
    
    intelligence = coordinator.swarm_intelligences[swarm_id]
    
    # Check if analysis is needed based on frequency
    if context.current_iteration % intelligence.analysis_frequency != 0
        # Return last recommendation if available
        if !isempty(intelligence.decision_history)
            last_recommendation = intelligence.decision_history[end][3]
            return last_recommendation
        end
    end
    
    # Prepare decision prompt
    decision_prompt = create_coordination_decision_prompt(context, intelligence)
    
    try
        # Get LLM decision
        llm_response = query_llm_for_decision(coordinator, decision_prompt)
        
        # Parse decision
        recommendation = parse_llm_decision(llm_response)
        
        # Store decision in history
        decision_record = (now(UTC), context, recommendation)
        push!(intelligence.decision_history, decision_record)
        
        # Limit history size
        if length(intelligence.decision_history) > intelligence.max_history_size
            intelligence.decision_history = intelligence.decision_history[end-intelligence.max_history_size÷2:end]
        end
        
        # Update learning memory
        update_learning_memory!(intelligence, context, recommendation)
        
        if recommendation.confidence >= intelligence.confidence_threshold
            coordinator.successful_recommendations += 1
        end
        
        @info "Coordination decision made" swarm_id=swarm_id strategy=recommendation.recommended_strategy confidence=recommendation.confidence
        
        return recommendation
        
    catch e
        @error "Failed to make coordination decision" swarm_id=swarm_id error=e
        return StrategyRecommendation(BALANCED_APPROACH, 0.3, "Fallback strategy due to analysis error: $(string(e))")
    end
end

"""
Recommend strategy adaptation based on performance analysis
"""
function recommend_strategy_adaptation!(coordinator::InferenceCoordinator,
                                      swarm_id::String, performance_data::Dict{String, Any})::Vector{String}
    if !haskey(coordinator.swarm_intelligences, swarm_id)
        return ["Initialize swarm intelligence system"]
    end
    
    intelligence = coordinator.swarm_intelligences[swarm_id]
    
    # Analyze performance trends
    adaptation_prompt = create_adaptation_analysis_prompt(performance_data, intelligence)
    
    try
        llm_response = query_llm_for_adaptation(coordinator, adaptation_prompt)
        adaptations = parse_llm_adaptations(llm_response)
        
        @info "Strategy adaptations recommended" swarm_id=swarm_id adaptations=length(adaptations)
        return adaptations
        
    catch e
        @error "Failed to recommend adaptations" swarm_id=swarm_id error=e
        return ["Monitor performance and consider manual strategy adjustment"]
    end
end

# ============================================================================
# LLM Prompt Creation
# ============================================================================

"""
Create optimization analysis prompt for LLM
"""
function create_optimization_analysis_prompt(context::DecisionContext)::String
    history_summary = if length(context.optimization_history) > 10
        recent = context.optimization_history[end-9:end]
        "Recent fitness values: $(join(round.(recent, digits=4), ", "))"
    else
        "Fitness history: $(join(round.(context.optimization_history, digits=4), ", "))"
    end

    return """
    You are an expert in swarm optimization algorithms. Analyze the following optimization progress and provide insights.

    Swarm ID: $(context.swarm_id)
    Current Iteration: $(context.current_iteration)
    $(history_summary)
    Population Diversity: $(round(context.population_diversity, digits=4))
    Convergence Rate: $(round(context.convergence_rate, digits=4))
    Time Elapsed: $(round(context.time_elapsed, digits=2)) seconds

    Problem Characteristics:
    $(JSON3.write(context.problem_characteristics))

    Please provide:
    1. Key insights about the optimization progress (3-5 bullet points)
    2. Specific recommendations for improvement (3-5 bullet points)
    3. Confidence scores for each insight (0.0-1.0)

    Format your response as JSON:
    {
        "insights": ["insight1", "insight2", ...],
        "recommendations": ["rec1", "rec2", ...],
        "confidence_scores": {"insight1": 0.8, "rec1": 0.9, ...}
    }
    """
end

"""
Create coordination decision prompt for LLM
"""
function create_coordination_decision_prompt(context::DecisionContext, intelligence::SwarmIntelligence)::String
    # Summarize recent decision history
    recent_decisions = if length(intelligence.decision_history) > 5
        last_5 = intelligence.decision_history[end-4:end]
        decisions_summary = join([string(d[3].recommended_strategy) for d in last_5], ", ")
        "Recent strategies: $decisions_summary"
    else
        "Limited decision history available"
    end

    return """
    You are a swarm optimization coordinator. Based on the current state, recommend the best coordination strategy.

    Current State:
    - Iteration: $(context.current_iteration)
    - Best fitness trend: $(length(context.optimization_history) > 1 ?
        round(context.optimization_history[end] - context.optimization_history[max(1, end-5)], digits=4) : "N/A")
    - Population diversity: $(round(context.population_diversity, digits=4))
    - Convergence rate: $(round(context.convergence_rate, digits=4))
    - Time elapsed: $(round(context.time_elapsed, digits=2))s

    $(recent_decisions)

    Available strategies:
    1. EXPLORATION_FOCUSED - Explore new solution areas
    2. EXPLOITATION_FOCUSED - Refine current best solutions
    3. BALANCED_APPROACH - Balance exploration and exploitation
    4. DIVERSIFICATION - Increase population diversity
    5. INTENSIFICATION - Concentrate around best solutions
    6. ADAPTIVE_HYBRID - Dynamically adapt strategy

    Provide your recommendation as JSON:
    {
        "strategy": "STRATEGY_NAME",
        "confidence": 0.85,
        "reasoning": "Detailed explanation of why this strategy is recommended",
        "parameter_adjustments": {"param1": 0.1, "param2": -0.05},
        "expected_improvement": 0.15,
        "risk_assessment": "low|medium|high"
    }
    """
end

"""
Create adaptation analysis prompt for LLM
"""
function create_adaptation_analysis_prompt(performance_data::Dict{String, Any}, intelligence::SwarmIntelligence)::String
    return """
    You are analyzing swarm optimization performance to recommend strategic adaptations.

    Performance Data:
    $(JSON3.write(performance_data))

    Historical Context:
    - Total decisions made: $(length(intelligence.decision_history))
    - Learning memory size: $(length(intelligence.learning_memory))

    Based on this performance data, recommend specific adaptations to improve optimization effectiveness.
    Focus on:
    1. Algorithm parameter adjustments
    2. Population management changes
    3. Search strategy modifications
    4. Resource allocation improvements

    Provide 3-7 specific, actionable recommendations as a JSON array:
    ["recommendation1", "recommendation2", ...]
    """
end

# ============================================================================
# LLM Response Parsing
# ============================================================================

"""
Query LLM for analysis
"""
function query_llm_for_analysis(coordinator::InferenceCoordinator, prompt::String)::String
    try
        # Create LLM integration instance
        llm_integration = LLMIntegration.create_llm_integration(coordinator.default_llm_config)

        if llm_integration === nothing
            throw(ArgumentError("Failed to create LLM integration"))
        end

        # Query LLM
        response = LLMIntegration.chat(llm_integration, prompt, cfg=coordinator.default_llm_config)

        return response
    catch e
        @error "LLM query failed" error=e
        rethrow(e)
    end
end

"""
Query LLM for decision making
"""
function query_llm_for_decision(coordinator::InferenceCoordinator, prompt::String)::String
    return query_llm_for_analysis(coordinator, prompt)  # Same underlying mechanism
end

"""
Query LLM for adaptation recommendations
"""
function query_llm_for_adaptation(coordinator::InferenceCoordinator, prompt::String)::String
    return query_llm_for_analysis(coordinator, prompt)  # Same underlying mechanism
end

"""
Parse LLM analysis response
"""
function parse_llm_analysis(response::String)::Tuple{Vector{String}, Vector{String}, Dict{String, Float64}}
    try
        # Extract JSON from response
        json_match = match(r"\{.*\}"s, response)
        if json_match === nothing
            throw(ArgumentError("No JSON found in LLM response"))
        end

        parsed = JSON3.read(json_match.match)

        insights = get(parsed, "insights", String[])
        recommendations = get(parsed, "recommendations", String[])
        confidence_scores = get(parsed, "confidence_scores", Dict{String, Float64}())

        return insights, recommendations, confidence_scores

    catch e
        @warn "Failed to parse LLM analysis response" error=e response=response[1:min(200, length(response))]

        # Fallback parsing
        insights = ["Analysis parsing failed - raw response available in metadata"]
        recommendations = ["Review LLM response format and adjust prompt if needed"]
        confidence_scores = Dict("fallback" => 0.3)

        return insights, recommendations, confidence_scores
    end
end

"""
Parse LLM decision response
"""
function parse_llm_decision(response::String)::StrategyRecommendation
    try
        json_match = match(r"\{.*\}"s, response)
        if json_match === nothing
            throw(ArgumentError("No JSON found in LLM response"))
        end

        parsed = JSON3.read(json_match.match)

        strategy_str = get(parsed, "strategy", "BALANCED_APPROACH")
        strategy = parse_strategy_enum(strategy_str)

        confidence = Float64(get(parsed, "confidence", 0.5))
        reasoning = get(parsed, "reasoning", "No reasoning provided")
        parameter_adjustments = Dict{String, Float64}(get(parsed, "parameter_adjustments", Dict()))
        expected_improvement = Float64(get(parsed, "expected_improvement", 0.0))
        risk_assessment = get(parsed, "risk_assessment", "medium")

        return StrategyRecommendation(strategy, confidence, reasoning,
                                    params=parameter_adjustments,
                                    improvement=expected_improvement,
                                    risk=risk_assessment)

    catch e
        @warn "Failed to parse LLM decision response" error=e response=response[1:min(200, length(response))]
        return StrategyRecommendation(BALANCED_APPROACH, 0.3,
                                    "Fallback strategy due to parsing error: $(string(e))")
    end
end

"""
Parse strategy enum from string
"""
function parse_strategy_enum(strategy_str::String)::CoordinationStrategy
    strategy_map = Dict(
        "EXPLORATION_FOCUSED" => EXPLORATION_FOCUSED,
        "EXPLOITATION_FOCUSED" => EXPLOITATION_FOCUSED,
        "BALANCED_APPROACH" => BALANCED_APPROACH,
        "DIVERSIFICATION" => DIVERSIFICATION,
        "INTENSIFICATION" => INTENSIFICATION,
        "ADAPTIVE_HYBRID" => ADAPTIVE_HYBRID
    )

    return get(strategy_map, uppercase(strategy_str), BALANCED_APPROACH)
end

"""
Parse LLM adaptation recommendations
"""
function parse_llm_adaptations(response::String)::Vector{String}
    try
        # Look for JSON array
        json_match = match(r"\[.*\]"s, response)
        if json_match !== nothing
            parsed = JSON3.read(json_match.match)
            return String.(parsed)
        end

        # Fallback: extract bullet points or numbered items
        lines = split(response, '\n')
        adaptations = String[]

        for line in lines
            cleaned = strip(line)
            if startswith(cleaned, r"[0-9]+\.") || startswith(cleaned, "•") || startswith(cleaned, "-")
                # Remove numbering/bullets and add to adaptations
                adaptation = replace(cleaned, r"^[0-9]+\.\s*" => "")
                adaptation = replace(adaptation, r"^[•\-]\s*" => "")
                if !isempty(adaptation)
                    push!(adaptations, adaptation)
                end
            end
        end

        return isempty(adaptations) ? ["Review optimization parameters and consider algorithm adjustments"] : adaptations

    catch e
        @warn "Failed to parse LLM adaptations" error=e
        return ["Manual review recommended due to parsing error"]
    end
end

# ============================================================================
# Learning and Memory Management
# ============================================================================

"""
Update learning memory with decision outcomes
"""
function update_learning_memory!(intelligence::SwarmIntelligence,
                                context::DecisionContext,
                                recommendation::StrategyRecommendation)
    # Store successful patterns
    if recommendation.confidence > intelligence.confidence_threshold
        pattern_key = "successful_strategies"
        if !haskey(intelligence.learning_memory, pattern_key)
            intelligence.learning_memory[pattern_key] = Dict{String, Int}()
        end

        strategy_str = string(recommendation.recommended_strategy)
        current_count = get(intelligence.learning_memory[pattern_key], strategy_str, 0)
        intelligence.learning_memory[pattern_key][strategy_str] = current_count + 1
    end

    # Store context patterns
    context_key = "context_patterns"
    if !haskey(intelligence.learning_memory, context_key)
        intelligence.learning_memory[context_key] = Dict{String, Vector{Float64}}()
    end

    # Categorize context based on diversity and convergence
    if context.population_diversity > 0.5 && context.convergence_rate < 0.1
        category = "high_diversity_slow_convergence"
    elseif context.population_diversity < 0.2 && context.convergence_rate > 0.3
        category = "low_diversity_fast_convergence"
    elseif context.convergence_rate < 0.05
        category = "stagnation"
    else
        category = "normal_progress"
    end

    if !haskey(intelligence.learning_memory[context_key], category)
        intelligence.learning_memory[context_key][category] = Float64[]
    end

    # Store the fitness improvement (if available)
    if length(context.optimization_history) > 1
        improvement = context.optimization_history[end-1] - context.optimization_history[end]
        push!(intelligence.learning_memory[context_key][category], improvement)

        # Limit memory size
        if length(intelligence.learning_memory[context_key][category]) > 100
            intelligence.learning_memory[context_key][category] =
                intelligence.learning_memory[context_key][category][end-49:end]
        end
    end
end

"""
Analyze swarm performance using historical data
"""
function analyze_swarm_performance!(coordinator::InferenceCoordinator,
                                  swarm_id::String,
                                  performance_window::Int=50)::Dict{String, Any}
    if !haskey(coordinator.swarm_intelligences, swarm_id)
        return Dict("error" => "Swarm intelligence not found")
    end

    intelligence = coordinator.swarm_intelligences[swarm_id]

    if isempty(intelligence.decision_history)
        return Dict("error" => "No decision history available")
    end

    # Analyze recent decisions
    recent_decisions = intelligence.decision_history[max(1, end-performance_window+1):end]

    # Calculate strategy effectiveness
    strategy_performance = Dict{String, Vector{Float64}}()
    for (timestamp, context, recommendation) in recent_decisions
        strategy_str = string(recommendation.recommended_strategy)
        if !haskey(strategy_performance, strategy_str)
            strategy_performance[strategy_str] = Float64[]
        end
        push!(strategy_performance[strategy_str], recommendation.confidence)
    end

    # Calculate average confidence per strategy
    strategy_avg_confidence = Dict{String, Float64}()
    for (strategy, confidences) in strategy_performance
        strategy_avg_confidence[strategy] = mean(confidences)
    end

    # Analyze trends
    recent_confidences = [rec[3].confidence for rec in recent_decisions]
    confidence_trend = length(recent_confidences) > 1 ?
                      recent_confidences[end] - recent_confidences[1] : 0.0

    return Dict{String, Any}(
        "total_decisions" => length(intelligence.decision_history),
        "recent_decisions_analyzed" => length(recent_decisions),
        "strategy_performance" => strategy_avg_confidence,
        "confidence_trend" => confidence_trend,
        "average_confidence" => mean(recent_confidences),
        "learning_memory_size" => length(intelligence.learning_memory),
        "most_used_strategy" => isempty(strategy_performance) ? "none" :
                               argmax(strategy_performance)[1]
    )
end

"""
Get intelligent insights from swarm coordination
"""
function get_intelligent_insights(coordinator::InferenceCoordinator,
                                swarm_id::String)::Vector{String}
    if !haskey(coordinator.swarm_intelligences, swarm_id)
        return ["Swarm intelligence not initialized"]
    end

    intelligence = coordinator.swarm_intelligences[swarm_id]
    insights = String[]

    # Analyze learning memory
    if haskey(intelligence.learning_memory, "successful_strategies")
        successful_strategies = intelligence.learning_memory["successful_strategies"]
        if !isempty(successful_strategies)
            best_strategy = argmax(successful_strategies)
            push!(insights, "Most successful strategy: $(best_strategy[1]) (used $(best_strategy[2]) times)")
        end
    end

    # Analyze context patterns
    if haskey(intelligence.learning_memory, "context_patterns")
        context_patterns = intelligence.learning_memory["context_patterns"]
        for (pattern, improvements) in context_patterns
            if length(improvements) > 5
                avg_improvement = mean(improvements)
                push!(insights, "Pattern '$(pattern)': Average improvement $(round(avg_improvement, digits=4))")
            end
        end
    end

    # Analyze decision history trends
    if length(intelligence.decision_history) > 10
        recent_confidences = [rec[3].confidence for rec in intelligence.decision_history[end-9:end]]
        avg_confidence = mean(recent_confidences)

        if avg_confidence > 0.8
            push!(insights, "High confidence in recent decisions ($(round(avg_confidence, digits=2)))")
        elseif avg_confidence < 0.5
            push!(insights, "Low confidence in recent decisions - consider strategy review")
        end
    end

    return isempty(insights) ? ["Insufficient data for insights"] : insights
end

# ============================================================================
# Setup and Utility Functions
# ============================================================================

"""
Create inference coordinator for swarm
"""
function create_inference_coordinator(; llm_provider::String="openai",
                                    llm_model::String="gpt-4o-mini",
                                    llm_config::Dict{String, Any}=Dict{String, Any}())::InferenceCoordinator
    coordinator = InferenceCoordinator(llm_provider=llm_provider,
                                     llm_model=llm_model,
                                     llm_config=llm_config)

    @info "Inference coordinator created" provider=llm_provider model=llm_model
    return coordinator
end

"""
Setup swarm intelligence for a specific swarm
"""
function setup_swarm_intelligence(coordinator::InferenceCoordinator,
                                swarm_id::String;
                                analysis_frequency::Int=10,
                                confidence_threshold::Float64=0.7)::Bool
    try
        intelligence = SwarmIntelligence(swarm_id, coordinator.default_llm_config,
                                       analysis_frequency=analysis_frequency,
                                       confidence_threshold=confidence_threshold)

        coordinator.swarm_intelligences[swarm_id] = intelligence

        @info "Swarm intelligence setup completed" swarm_id=swarm_id frequency=analysis_frequency
        return true

    catch e
        @error "Failed to setup swarm intelligence" swarm_id=swarm_id error=e
        return false
    end
end

"""
Get coordination statistics
"""
function get_coordination_stats(coordinator::InferenceCoordinator)::Dict{String, Any}
    total_swarms = length(coordinator.swarm_intelligences)
    total_decisions = sum(length(intel.decision_history) for intel in values(coordinator.swarm_intelligences))

    success_rate = coordinator.total_analyses > 0 ?
                  coordinator.successful_recommendations / coordinator.total_analyses : 0.0

    return Dict{String, Any}(
        "total_swarms_managed" => total_swarms,
        "total_analyses" => coordinator.total_analyses,
        "successful_recommendations" => coordinator.successful_recommendations,
        "success_rate" => success_rate,
        "total_decisions_made" => total_decisions,
        "llm_provider" => coordinator.llm_provider,
        "llm_model" => coordinator.llm_model
    )
end

"""
Export swarm intelligence data for analysis
"""
function export_intelligence_data(coordinator::InferenceCoordinator,
                                swarm_id::String)::Dict{String, Any}
    if !haskey(coordinator.swarm_intelligences, swarm_id)
        return Dict("error" => "Swarm not found")
    end

    intelligence = coordinator.swarm_intelligences[swarm_id]

    return Dict{String, Any}(
        "swarm_id" => swarm_id,
        "decision_count" => length(intelligence.decision_history),
        "learning_memory" => intelligence.learning_memory,
        "configuration" => Dict(
            "analysis_frequency" => intelligence.analysis_frequency,
            "confidence_threshold" => intelligence.confidence_threshold,
            "max_history_size" => intelligence.max_history_size
        ),
        "recent_decisions" => if length(intelligence.decision_history) > 10
            [(string(rec[1]), rec[2].current_iteration, string(rec[3].recommended_strategy), rec[3].confidence)
             for rec in intelligence.decision_history[end-9:end]]
        else
            [(string(rec[1]), rec[2].current_iteration, string(rec[3].recommended_strategy), rec[3].confidence)
             for rec in intelligence.decision_history]
        end
    )
end

end # module InferenceCoordination
