# frozen_string_literal: true
module RubyAMI
  class Stream < EventMachine::Connection
    class ConnectionStatus
      def ==(other)
        other.is_a? self.class
      end
    end

    Connected = Class.new ConnectionStatus
    Disconnected = Class.new ConnectionStatus

    attr_reader :logger

    def initialize(username, password, event_callback, unbind_callback= nil, logger = Logger.new(STDOUT) )
      @username= username
      @password= password
      @event_callback= event_callback
      @unbind_callback= unbind_callback
      @logger = logger

      logger.debug "Starting up..."
      @lexer = Lexer.new self
      @sent_actions   = {}
      @causal_actions = {}
    end

    [:started, :stopped].each do |state|
      define_method("#{state}?") { @state == state }
    end

    def async_send_action(*args, &block)
      action = Action.new *args, &block
      # puts "[SEND] #{action.to_s}"
      register_sent_action action
      send_data action.to_s
      action
    end

    def send_action(name, headers = {}, &causal_event_callback)
      ivar= Concurrent::IVar.new

      EM.next_tick do
        begin
          async_send_action(name, headers, causal_event_callback) do |response|
            ivar.set(response)
          end
        rescue => e
          ivar.set(e)
        end
      end

      ivar.wait

      if ivar.value.is_a?(Exception)
        raise ivar.value
      else
        ivar.value
      end
    end

    def fiber_send_action(name, headers = {}, &causal_event_callback)
      fiber= Fiber.current

      async_send_action(name, headers, causal_event_callback) do |response|
        fiber.resume(response)
      end

      response= Fiber.yield

      if response.is_a?(Exception)
        raise response
      else
        response
      end
    end

    ####################
    # EM callbacks
    def post_init
      @state = :started
      fire_event Connected.new
      login @username, @password if @username && @password
    end

    def connection_completed
      post_init unless started?
    end

    def receive_data(data)
      # puts "[RECV] #{data}"
      @lexer << data
    end

    def unbind
      logger.debug "Finalizing stream"
      @state = :stopped
      fire_event Disconnected.new
      @unbind_callback&.call(self)
    end

    ####################
    # lexer callbacks
    def message_received(message)
      # puts "[RECV] #{message.inspect}"
      case message
      when Event
        action = causal_action_for_event message
        if action
          action << message
          complete_causal_action_for_event message if action.complete?
        else
          fire_event message
        end
      when Response, Error
        action = sent_action_for_response message
        raise "Received an AMI response with an unrecognized ActionID! #{message.inspect}" unless action
        action << message
      end
    end

    def syntax_error_encountered(ignored_chunk)
      logger.error "Encountered a syntax error. Ignoring chunk: #{ignored_chunk.inspect}"
    end

    alias :error_received :message_received

    private

    def login(username, password, event_mask = 'On')
      async_send_action 'Login',
        'Username' => username,
        'Secret'   => password,
        'Events'   => event_mask
    end

    def fire_event(event)
      @event_callback.call event
    end

    def register_sent_action(action)
      @sent_actions[action.action_id] = action
      register_causal_action action if action.has_causal_events?
    end

    def sent_action_with_id(action_id)
      @sent_actions.delete action_id
    end

    def sent_action_for_response(response)
      sent_action_with_id response.action_id
    end

    def register_causal_action(action)
      @causal_actions[action.action_id] = action
    end

    def causal_action_for_event(event)
      @causal_actions[event.action_id]
    end

    def complete_causal_action_for_event(event)
      @causal_actions.delete event.action_id
    end
  end
end
