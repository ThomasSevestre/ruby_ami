# frozen_string_literal: true
module RubyAMI
  class Stream
    class ConnectionStatus
      def ==(other)
        other.is_a? self.class
      end
    end

    Connected = Class.new ConnectionStatus
    Disconnected = Class.new ConnectionStatus

    include Celluloid::IO

    attr_reader :logger

    finalizer :finalize

    def initialize(host, port, username, password, event_callback, logger = Logger, timeout = 0)
      super()
      @host, @port, @username, @password, @event_callback, @logger, @timeout = host, port, username, password, event_callback, logger, timeout
      logger.debug "Starting up..."
      @lexer = Lexer.new self
      @sent_actions   = {}
      @causal_actions = {}
      @custom_event_queue= Queue.new
    end

    [:started, :stopped].each do |state|
      define_method("#{state}?") { @state == state }
    end

    def add_custom_event(event)
      @custom_event_queue<< event
    end

    def run
      Timeout::timeout(@timeout) do
        @socket = TCPSocket.from_ruby_socket ::TCPSocket.new(@host, @port)
      end
      post_init
      loop do
        # handle custom events
        loop do
          begin
            fire_event(@custom_event_queue.pop(true))
          rescue ThreadError
            break
          end
        end
        # handle asterisk events
        receive_data @socket.readpartial(4096)
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      logger.error "Connection failed due to #{e.class}. Check your config and the server."
    rescue EOFError
      logger.info "Client socket closed!"
    rescue Timeout::Error
      logger.error "Timeout exceeded while trying to connect."
    ensure
      async.terminate
    end

    def post_init
      @state = :started
      fire_event Connected.new
      login @username, @password if @username && @password
    end

    def send_data(data)
      @socket.write data
    end

    def send_action(name, headers = {})
      condition = Celluloid::Condition.new
      action = dispatch_action name, headers do |response|
        condition.signal response
      end
      condition.wait
      action.response.tap do |resp|
        abort resp if resp.is_a? Exception
      end
    end

    def receive_data(data)
      logger.trace "[RECV] #{data}"
      @lexer << data
    end

    # lexer callback
    def message_received(message)
      logger.trace "[RECV] #{message.inspect}"
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

    # lexer callback
    def syntax_error_encountered(ignored_chunk)
      logger.error "Encountered a syntax error. Ignoring chunk: #{ignored_chunk.inspect}"
    end

    # lexer callback
    alias :error_received :message_received

    private

    def login(username, password, event_mask = 'On')
      dispatch_action 'Login',
        'Username' => username,
        'Secret'   => password,
        'Events'   => event_mask
    end

    def dispatch_action(*args, &block)
      action = Action.new *args, &block
      logger.trace "[SEND] #{action.to_s}"
      register_sent_action action
      send_data action.to_s
      action
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

    def finalize
      logger.debug "Finalizing stream"
      @socket.close if @socket
      @state = :stopped
      fire_event Disconnected.new
    end
  end
end
