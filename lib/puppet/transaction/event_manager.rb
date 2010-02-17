require 'puppet/transaction'

class Puppet::Transaction::EventManager
    attr_reader :transaction, :events

    def initialize(transaction)
        @transaction = transaction
        @event_queues = {}
        @events = []
    end

    def relationship_graph
        transaction.relationship_graph
    end

    def report
        transaction.report
    end

    # Respond to any queued events for this resource.
    def process_events(resource)
        restarted = false
        queued_events(resource) do |callback, events|
            r = process_callback(resource, callback, events)
            restarted ||= r
        end

        if restarted
            queue_event(resource, resource.event(:name => :restarted, :status => "success"))

            transaction.resourcemetrics[:restarted] += 1
        end
    end

    # Queue events for other resources to respond to.  All of these events have
    # to be from the same resource.
    def queue_event(resource, event)
        @events << event

        report.register_event event

        # Collect the targets of any subscriptions to those events.  We pass
        # the parent resource in so it will override the source in the events,
        # since eval_generated children can't have direct relationships.
        relationship_graph.matching_edges(event, resource).each do |edge|
            next unless method = edge.callback
            next unless edge.target.respond_to?(method)

            queue_event_for_resource(resource, edge.target, method, event)
        end

        if resource.self_refresh? and ! resource.deleting?
            queue_event_for_resource(resource, resource, :refresh, event)
        end
    end

    def queue_event_for_resource(source, target, callback, event)
        source.info "Scheduling #{callback} of #{target}"

        @event_queues[target] ||= {}
        @event_queues[target][callback] ||= []
        @event_queues[target][callback] << event
    end

    def queued_events(resource)
        return unless callbacks = @event_queues[resource]
        callbacks.each do |callback, events|
            yield callback, events
        end
    end

    private

    def process_callback(resource, callback, events)
        # XXX Should it be any event, or all events?
        process_noop_events(resource, callback, events) and return false unless events.detect { |e| e.status != "noop" }
        resource.send(callback)

        resource.notice "Triggered '#{callback}' from #{events.length} events"
        return true
    rescue => detail
        resource.err "Failed to call #{callback}: #{detail}"

        transaction.resourcemetrics[:failed_restarts] += 1
        puts detail.backtrace if Puppet[:trace]
        return false
    end

    def process_noop_events(resource, callback, events)
        resource.notice "Would have triggered '#{callback}' from #{events.length} events"

        # And then add an event for it.
        queue_event(resource, resource.event(:status => "noop", :name => :noop_restart))
        true # so the 'and if' works
    end
end
