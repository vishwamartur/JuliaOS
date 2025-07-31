"""
SwarmCommunication.jl - Agent-to-Agent communication system for JuliaOS swarms

This module provides robust messaging protocols, pub/sub systems, message routing,
and communication reliability mechanisms for swarm coordination.
"""
module SwarmCommunication

using Dates, UUIDs, JSON3, Logging
using Base.Threads
using DataStructures: Queue, enqueue!, dequeue!

export SwarmMessage, MessageType, CommunicationChannel, MessageRouter,
       SwarmCommunicationManager, ReliabilityManager, MessagePriority,
       send_message!, receive_message!, broadcast_message!, subscribe_to_topic!,
       unsubscribe_from_topic!, create_communication_channel, setup_swarm_communication,
       get_communication_stats, cleanup_communication!

# ============================================================================
# Message Types and Structures
# ============================================================================

@enum MessageType begin
    COORDINATION = 1
    DATA_SHARING = 2
    STATUS_UPDATE = 3
    TASK_ASSIGNMENT = 4
    RESULT_SHARING = 5
    HEARTBEAT = 6
    EMERGENCY = 7
    CUSTOM = 8
end

@enum MessagePriority begin
    LOW = 1
    NORMAL = 2
    HIGH = 3
    CRITICAL = 4
end

"""
Swarm message structure for agent-to-agent communication
"""
struct SwarmMessage
    id::String
    sender_id::String
    recipient_id::Union{String, Nothing}  # Nothing for broadcast
    topic::String
    message_type::MessageType
    priority::MessagePriority
    payload::Dict{String, Any}
    timestamp::DateTime
    ttl_seconds::Int  # Time to live
    retry_count::Int
    correlation_id::Union{String, Nothing}  # For request-response patterns
    
    function SwarmMessage(sender_id::String, topic::String, payload::Dict{String, Any};
                         recipient_id::Union{String, Nothing}=nothing,
                         message_type::MessageType=DATA_SHARING,
                         priority::MessagePriority=NORMAL,
                         ttl_seconds::Int=300,
                         correlation_id::Union{String, Nothing}=nothing)
        new(string(uuid4()), sender_id, recipient_id, topic, message_type, priority,
            payload, now(UTC), ttl_seconds, 0, correlation_id)
    end
end

"""
Check if message has expired
"""
function is_expired(message::SwarmMessage)::Bool
    return (now(UTC) - message.timestamp).value / 1000 > message.ttl_seconds
end

"""
Create response message
"""
function create_response(original::SwarmMessage, sender_id::String, response_payload::Dict{String, Any})::SwarmMessage
    return SwarmMessage(sender_id, original.topic, response_payload,
                       recipient_id=original.sender_id,
                       message_type=original.message_type,
                       priority=original.priority,
                       correlation_id=original.id)
end

# ============================================================================
# Communication Channels
# ============================================================================

"""
Communication channel for message passing between agents
"""
mutable struct CommunicationChannel
    name::String
    subscribers::Set{String}
    message_queue::Queue{SwarmMessage}
    max_queue_size::Int
    total_messages::Int
    dropped_messages::Int
    last_activity::DateTime
    
    function CommunicationChannel(name::String; max_queue_size::Int=1000)
        new(name, Set{String}(), Queue{SwarmMessage}(), max_queue_size, 0, 0, now(UTC))
    end
end

"""
Add message to channel
"""
function add_message!(channel::CommunicationChannel, message::SwarmMessage)::Bool
    if length(channel.message_queue) >= channel.max_queue_size
        # Drop oldest message if queue is full
        if !isempty(channel.message_queue)
            dequeue!(channel.message_queue)
            channel.dropped_messages += 1
        end
    end
    
    enqueue!(channel.message_queue, message)
    channel.total_messages += 1
    channel.last_activity = now(UTC)
    return true
end

"""
Get next message from channel for specific agent
"""
function get_next_message(channel::CommunicationChannel, agent_id::String)::Union{SwarmMessage, Nothing}
    if isempty(channel.message_queue)
        return nothing
    end
    
    # Look for messages for this agent or broadcasts
    temp_queue = Queue{SwarmMessage}()
    found_message = nothing
    
    while !isempty(channel.message_queue)
        message = dequeue!(channel.message_queue)
        
        # Check if message is for this agent or is a broadcast
        if (message.recipient_id === nothing || message.recipient_id == agent_id) && 
           !is_expired(message) && found_message === nothing
            found_message = message
        else
            enqueue!(temp_queue, message)
        end
    end
    
    # Put remaining messages back
    while !isempty(temp_queue)
        enqueue!(channel.message_queue, dequeue!(temp_queue))
    end
    
    return found_message
end

# ============================================================================
# Message Router
# ============================================================================

"""
Message router for handling message delivery and routing
"""
mutable struct MessageRouter
    channels::Dict{String, CommunicationChannel}
    agent_subscriptions::Dict{String, Set{String}}  # agent_id -> topics
    topic_subscribers::Dict{String, Set{String}}    # topic -> agent_ids
    routing_table::Dict{String, String}             # agent_id -> preferred_channel
    message_history::Vector{SwarmMessage}
    max_history_size::Int
    
    function MessageRouter(; max_history_size::Int=10000)
        new(Dict{String, CommunicationChannel}(),
            Dict{String, Set{String}}(),
            Dict{String, Set{String}}(),
            Dict{String, String}(),
            Vector{SwarmMessage}(),
            max_history_size)
    end
end

"""
Create or get communication channel
"""
function get_or_create_channel!(router::MessageRouter, channel_name::String)::CommunicationChannel
    if !haskey(router.channels, channel_name)
        router.channels[channel_name] = CommunicationChannel(channel_name)
    end
    return router.channels[channel_name]
end

"""
Subscribe agent to topic
"""
function subscribe_agent!(router::MessageRouter, agent_id::String, topic::String, channel_name::String="default")
    # Update agent subscriptions
    if !haskey(router.agent_subscriptions, agent_id)
        router.agent_subscriptions[agent_id] = Set{String}()
    end
    push!(router.agent_subscriptions[agent_id], topic)
    
    # Update topic subscribers
    if !haskey(router.topic_subscribers, topic)
        router.topic_subscribers[topic] = Set{String}()
    end
    push!(router.topic_subscribers[topic], agent_id)
    
    # Add to channel
    channel = get_or_create_channel!(router, channel_name)
    push!(channel.subscribers, agent_id)
    
    # Set routing preference
    router.routing_table[agent_id] = channel_name
    
    @debug "Agent subscribed to topic" agent_id=agent_id topic=topic channel=channel_name
end

"""
Unsubscribe agent from topic
"""
function unsubscribe_agent!(router::MessageRouter, agent_id::String, topic::String)
    # Remove from agent subscriptions
    if haskey(router.agent_subscriptions, agent_id)
        delete!(router.agent_subscriptions[agent_id], topic)
    end
    
    # Remove from topic subscribers
    if haskey(router.topic_subscribers, topic)
        delete!(router.topic_subscribers[topic], agent_id)
    end
    
    @debug "Agent unsubscribed from topic" agent_id=agent_id topic=topic
end

"""
Route message to appropriate channels
"""
function route_message!(router::MessageRouter, message::SwarmMessage)::Bool
    try
        # Add to history
        push!(router.message_history, message)
        if length(router.message_history) > router.max_history_size
            router.message_history = router.message_history[end-router.max_history_size÷2:end]
        end
        
        # Determine target agents
        target_agents = Set{String}()
        
        if message.recipient_id !== nothing
            # Direct message
            push!(target_agents, message.recipient_id)
        else
            # Broadcast to topic subscribers
            if haskey(router.topic_subscribers, message.topic)
                union!(target_agents, router.topic_subscribers[message.topic])
            end
        end
        
        # Route to appropriate channels
        routed_count = 0
        for agent_id in target_agents
            channel_name = get(router.routing_table, agent_id, "default")
            channel = get_or_create_channel!(router, channel_name)
            
            if add_message!(channel, message)
                routed_count += 1
            end
        end
        
        @debug "Message routed" message_id=message.id targets=length(target_agents) routed=routed_count
        return routed_count > 0
    catch e
        @error "Error routing message" message_id=message.id error=e
        return false
    end
end

"""
Get messages for agent from all subscribed topics
"""
function get_messages_for_agent(router::MessageRouter, agent_id::String)::Vector{SwarmMessage}
    messages = SwarmMessage[]
    
    # Get preferred channel
    channel_name = get(router.routing_table, agent_id, "default")
    if haskey(router.channels, channel_name)
        channel = router.channels[channel_name]
        
        # Collect all messages for this agent
        while true
            message = get_next_message(channel, agent_id)
            if message === nothing
                break
            end
            push!(messages, message)
        end
    end
    
    # Sort by priority and timestamp
    sort!(messages, by=m -> (Int(m.priority), m.timestamp), rev=true)
    
    return messages
end

# ============================================================================
# Reliability Manager
# ============================================================================

"""
Reliability manager for ensuring message delivery and handling failures
"""
mutable struct ReliabilityManager
    pending_messages::Dict{String, SwarmMessage}  # message_id -> message
    acknowledgments::Dict{String, DateTime}       # message_id -> ack_time
    retry_intervals::Vector{Int}                  # Retry intervals in seconds
    max_retries::Int
    ack_timeout_seconds::Int

    function ReliabilityManager(; retry_intervals::Vector{Int}=[1, 2, 5, 10, 30],
                              max_retries::Int=5, ack_timeout_seconds::Int=60)
        new(Dict{String, SwarmMessage}(), Dict{String, DateTime}(),
            retry_intervals, max_retries, ack_timeout_seconds)
    end
end

"""
Add message to reliability tracking
"""
function track_message!(manager::ReliabilityManager, message::SwarmMessage)
    if message.priority in [HIGH, CRITICAL]
        manager.pending_messages[message.id] = message
    end
end

"""
Acknowledge message receipt
"""
function acknowledge_message!(manager::ReliabilityManager, message_id::String)
    manager.acknowledgments[message_id] = now(UTC)
    delete!(manager.pending_messages, message_id)
    @debug "Message acknowledged" message_id=message_id
end

"""
Check for messages that need retry
"""
function get_retry_messages(manager::ReliabilityManager)::Vector{SwarmMessage}
    retry_messages = SwarmMessage[]
    current_time = now(UTC)

    for (message_id, message) in manager.pending_messages
        # Check if message has timed out
        elapsed_seconds = (current_time - message.timestamp).value ÷ 1000

        if elapsed_seconds > manager.ack_timeout_seconds && message.retry_count < manager.max_retries
            # Create retry message
            retry_interval_idx = min(message.retry_count + 1, length(manager.retry_intervals))
            retry_interval = manager.retry_intervals[retry_interval_idx]

            if elapsed_seconds > manager.ack_timeout_seconds + retry_interval
                retry_message = SwarmMessage(
                    message.sender_id, message.topic, message.payload,
                    recipient_id=message.recipient_id,
                    message_type=message.message_type,
                    priority=message.priority,
                    ttl_seconds=message.ttl_seconds,
                    correlation_id=message.correlation_id
                )

                # Update retry count
                retry_message = SwarmMessage(
                    retry_message.sender_id, retry_message.topic, retry_message.payload,
                    recipient_id=retry_message.recipient_id,
                    message_type=retry_message.message_type,
                    priority=retry_message.priority,
                    ttl_seconds=retry_message.ttl_seconds,
                    correlation_id=retry_message.correlation_id
                )

                push!(retry_messages, retry_message)

                # Update pending message
                manager.pending_messages[message_id] = retry_message
            end
        elseif message.retry_count >= manager.max_retries
            # Give up on message
            delete!(manager.pending_messages, message_id)
            @warn "Message delivery failed after max retries" message_id=message_id retries=message.retry_count
        end
    end

    return retry_messages
end

# ============================================================================
# Main Communication Manager
# ============================================================================

"""
Main swarm communication manager
"""
mutable struct SwarmCommunicationManager
    router::MessageRouter
    reliability_manager::ReliabilityManager
    active_agents::Set{String}
    communication_stats::Dict{String, Any}
    background_task::Union{Task, Nothing}
    is_running::Bool

    function SwarmCommunicationManager()
        stats = Dict{String, Any}(
            "messages_sent" => 0,
            "messages_received" => 0,
            "messages_dropped" => 0,
            "active_channels" => 0,
            "active_subscriptions" => 0
        )

        new(MessageRouter(), ReliabilityManager(), Set{String}(), stats, nothing, false)
    end
end

"""
Start communication manager background tasks
"""
function start_communication_manager!(manager::SwarmCommunicationManager)
    if manager.is_running
        return
    end

    manager.is_running = true
    manager.background_task = @async begin
        while manager.is_running
            try
                # Process retry messages
                retry_messages = get_retry_messages(manager.reliability_manager)
                for message in retry_messages
                    route_message!(manager.router, message)
                end

                # Clean up expired messages
                cleanup_expired_messages!(manager)

                # Update statistics
                update_communication_stats!(manager)

                sleep(1)  # Check every second
            catch e
                @error "Error in communication manager background task" error=e
            end
        end
    end

    @info "Swarm communication manager started"
end

"""
Stop communication manager
"""
function stop_communication_manager!(manager::SwarmCommunicationManager)
    manager.is_running = false
    if manager.background_task !== nothing
        wait(manager.background_task)
        manager.background_task = nothing
    end
    @info "Swarm communication manager stopped"
end

"""
Send message through the communication system
"""
function send_message!(manager::SwarmCommunicationManager, message::SwarmMessage)::Bool
    try
        # Track for reliability if needed
        track_message!(manager.reliability_manager, message)

        # Route message
        success = route_message!(manager.router, message)

        if success
            manager.communication_stats["messages_sent"] += 1
            @debug "Message sent successfully" message_id=message.id topic=message.topic
        else
            @warn "Failed to send message" message_id=message.id topic=message.topic
        end

        return success
    catch e
        @error "Error sending message" message_id=message.id error=e
        return false
    end
end

"""
Receive messages for agent
"""
function receive_messages!(manager::SwarmCommunicationManager, agent_id::String)::Vector{SwarmMessage}
    try
        messages = get_messages_for_agent(manager.router, agent_id)
        manager.communication_stats["messages_received"] += length(messages)

        # Send acknowledgments for high-priority messages
        for message in messages
            if message.priority in [HIGH, CRITICAL]
                acknowledge_message!(manager.reliability_manager, message.id)
            end
        end

        return messages
    catch e
        @error "Error receiving messages for agent" agent_id=agent_id error=e
        return SwarmMessage[]
    end
end

"""
Broadcast message to all subscribers of a topic
"""
function broadcast_message!(manager::SwarmCommunicationManager, sender_id::String,
                          topic::String, payload::Dict{String, Any};
                          message_type::MessageType=DATA_SHARING,
                          priority::MessagePriority=NORMAL)::Bool
    message = SwarmMessage(sender_id, topic, payload,
                          message_type=message_type, priority=priority)
    return send_message!(manager, message)
end

"""
Subscribe agent to topic
"""
function subscribe_to_topic!(manager::SwarmCommunicationManager, agent_id::String,
                           topic::String, channel_name::String="default")
    subscribe_agent!(manager.router, agent_id, topic, channel_name)
    push!(manager.active_agents, agent_id)
    @info "Agent subscribed to topic" agent_id=agent_id topic=topic
end

"""
Unsubscribe agent from topic
"""
function unsubscribe_from_topic!(manager::SwarmCommunicationManager, agent_id::String, topic::String)
    unsubscribe_agent!(manager.router, agent_id, topic)
    @info "Agent unsubscribed from topic" agent_id=agent_id topic=topic
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
Clean up expired messages from all channels
"""
function cleanup_expired_messages!(manager::SwarmCommunicationManager)
    for (channel_name, channel) in manager.router.channels
        temp_queue = Queue{SwarmMessage}()
        expired_count = 0

        while !isempty(channel.message_queue)
            message = dequeue!(channel.message_queue)
            if !is_expired(message)
                enqueue!(temp_queue, message)
            else
                expired_count += 1
            end
        end

        # Put non-expired messages back
        while !isempty(temp_queue)
            enqueue!(channel.message_queue, dequeue!(temp_queue))
        end

        if expired_count > 0
            @debug "Cleaned up expired messages" channel=channel_name count=expired_count
        end
    end
end

"""
Update communication statistics
"""
function update_communication_stats!(manager::SwarmCommunicationManager)
    manager.communication_stats["active_channels"] = length(manager.router.channels)
    manager.communication_stats["active_subscriptions"] = sum(length(subs) for subs in values(manager.router.agent_subscriptions))

    # Calculate dropped messages
    total_dropped = sum(channel.dropped_messages for channel in values(manager.router.channels))
    manager.communication_stats["messages_dropped"] = total_dropped
end

"""
Get communication statistics
"""
function get_communication_stats(manager::SwarmCommunicationManager)::Dict{String, Any}
    update_communication_stats!(manager)

    stats = copy(manager.communication_stats)
    stats["pending_reliable_messages"] = length(manager.reliability_manager.pending_messages)
    stats["total_acknowledgments"] = length(manager.reliability_manager.acknowledgments)
    stats["active_agents"] = length(manager.active_agents)

    # Channel-specific stats
    channel_stats = Dict{String, Any}()
    for (name, channel) in manager.router.channels
        channel_stats[name] = Dict(
            "subscribers" => length(channel.subscribers),
            "queue_size" => length(channel.message_queue),
            "total_messages" => channel.total_messages,
            "dropped_messages" => channel.dropped_messages,
            "last_activity" => channel.last_activity
        )
    end
    stats["channels"] = channel_stats

    return stats
end

"""
Create communication channel with specific configuration
"""
function create_communication_channel(manager::SwarmCommunicationManager,
                                    channel_name::String;
                                    max_queue_size::Int=1000)::CommunicationChannel
    channel = CommunicationChannel(channel_name, max_queue_size=max_queue_size)
    manager.router.channels[channel_name] = channel
    @info "Communication channel created" name=channel_name max_queue_size=max_queue_size
    return channel
end

"""
Setup swarm communication for a list of agents
"""
function setup_swarm_communication(agent_ids::Vector{String},
                                 topics::Vector{String}=["coordination", "data_sharing"];
                                 channel_name::String="default")::SwarmCommunicationManager
    manager = SwarmCommunicationManager()

    # Create default channel
    create_communication_channel(manager, channel_name)

    # Subscribe all agents to all topics
    for agent_id in agent_ids
        for topic in topics
            subscribe_to_topic!(manager, agent_id, topic, channel_name)
        end
    end

    # Start background tasks
    start_communication_manager!(manager)

    @info "Swarm communication setup complete" agents=length(agent_ids) topics=length(topics)
    return manager
end

"""
Cleanup communication resources
"""
function cleanup_communication!(manager::SwarmCommunicationManager)
    # Stop background tasks
    stop_communication_manager!(manager)

    # Clear all data structures
    empty!(manager.router.channels)
    empty!(manager.router.agent_subscriptions)
    empty!(manager.router.topic_subscribers)
    empty!(manager.router.routing_table)
    empty!(manager.router.message_history)
    empty!(manager.reliability_manager.pending_messages)
    empty!(manager.reliability_manager.acknowledgments)
    empty!(manager.active_agents)

    @info "Communication resources cleaned up"
end

"""
Helper function to create standard message types
"""
function create_coordination_message(sender_id::String, payload::Dict{String, Any};
                                   recipient_id::Union{String, Nothing}=nothing)::SwarmMessage
    return SwarmMessage(sender_id, "coordination", payload,
                       recipient_id=recipient_id, message_type=COORDINATION, priority=HIGH)
end

function create_data_sharing_message(sender_id::String, payload::Dict{String, Any};
                                   recipient_id::Union{String, Nothing}=nothing)::SwarmMessage
    return SwarmMessage(sender_id, "data_sharing", payload,
                       recipient_id=recipient_id, message_type=DATA_SHARING, priority=NORMAL)
end

function create_status_update_message(sender_id::String, status::Dict{String, Any})::SwarmMessage
    return SwarmMessage(sender_id, "status_updates", status,
                       message_type=STATUS_UPDATE, priority=NORMAL)
end

function create_emergency_message(sender_id::String, emergency_data::Dict{String, Any};
                                recipient_id::Union{String, Nothing}=nothing)::SwarmMessage
    return SwarmMessage(sender_id, "emergency", emergency_data,
                       recipient_id=recipient_id, message_type=EMERGENCY, priority=CRITICAL)
end

"""
Message filtering and search utilities
"""
function filter_messages_by_type(messages::Vector{SwarmMessage}, message_type::MessageType)::Vector{SwarmMessage}
    return filter(m -> m.message_type == message_type, messages)
end

function filter_messages_by_sender(messages::Vector{SwarmMessage}, sender_id::String)::Vector{SwarmMessage}
    return filter(m -> m.sender_id == sender_id, messages)
end

function filter_messages_by_topic(messages::Vector{SwarmMessage}, topic::String)::Vector{SwarmMessage}
    return filter(m -> m.topic == topic, messages)
end

function find_message_by_correlation_id(messages::Vector{SwarmMessage}, correlation_id::String)::Union{SwarmMessage, Nothing}
    for message in messages
        if message.correlation_id == correlation_id
            return message
        end
    end
    return nothing
end

end # module SwarmCommunication
