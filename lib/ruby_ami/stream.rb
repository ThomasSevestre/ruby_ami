# frozen_string_literal: true
module RubyAMI
  class Stream < EventMachine::Connection
    class ConnectionStatus
      attr_reader :ip, :port

      def initialize(ip, port)
        @ip= ip
        @port= port
      end

      def ==(other)
        other.is_a?(self.class) && other.ip == @ip && other.port == @port
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

    # Must be called in EM main thread.
    # This can be done by wrapping with EM.next_tick
    def async_send_action(name, headers = {}, causal_event_callback = nil, &block)
      action = Action.new(name, headers, causal_event_callback, &block)
      if causal_event_callback || block
        @sent_actions[action.action_id] = action
        if action.has_causal_events?
          @causal_actions[action.action_id] = action
        end
      end
      # puts "[SEND] #{action.to_s}"
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
    end

    def connection_completed
      post_init unless started?
      @connected_port, @connected_ip = Socket.unpack_sockaddr_in(self.get_peername)
      fire_event Connected.new(@connected_ip, @connected_port)
      login @username, @password if @username && @password
    end

    def receive_data(data)
      # puts "[RECV] #{data}"
      @lexer << data
    end

    def unbind
      logger.debug "Finalizing stream"
      @state = :stopped
      fire_event Disconnected.new(@connected_ip, @connected_port)
      @unbind_callback&.call(self)
    end

    ####################
    # lexer callbacks
    def message_received(message)
      # puts "[RECV] #{message.inspect}"
      case message
      when Event
        action = @causal_actions[message.action_id]
        if action
          action << message
          @causal_actions.delete(message.action_id) if action.complete?
        else
          fire_event message
        end
      when Response, Error
        action = @sent_actions.delete(message.action_id)
        if action
          action << message
        else
          # puts "Received an AMI response with an unrecognized ActionID! #{message.inspect}" unless action
        end
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
  end
end
