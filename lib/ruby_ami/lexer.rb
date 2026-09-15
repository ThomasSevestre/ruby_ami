# frozen_string_literal: true
module RubyAMI
  # Parses the AMI wire protocol as emitted by Asterisk >= 14: every message
  # is a block of "Key: value" headers ended by an empty line. The Command
  # action answers with "Output:" headers, one per CLI line, the pre-14
  # "Response: Follows" / "--END COMMAND--" form is not supported.
  class Lexer
    PROMPT            = /Asterisk Call Manager\/([0-9.]+)\r\n/
    SUCCESS           = /response: *success/i
    PONG              = /response: *pong/i
    EVENT             = /event: *(?<event_name>.*)?/i
    ERROR             = /response: *error/i
    HEADER_SLICE      = /.*\r\n/
    CLASSIFIER        = /((?<event>#{EVENT})|(?<success>#{SUCCESS})|(?<pong>#{PONG})|(?<error>#{ERROR}))\r\n/i

    attr_accessor :ami_version

    def initialize(delegate = nil)
      @delegate = delegate
      @buffer = String.new
      @ami_version = nil
      @current_msg = nil
    end

    def <<(new_data)
      @buffer << new_data
      parse_buffer
    end

    private

    def parse_buffer
      # Special case for the protocol header
      if @buffer.start_with?("Asterisk Call Manager") && @buffer =~ PROMPT
        @ami_version = $1
        @buffer.slice! HEADER_SLICE
        @current_msg = nil
      end

      processed = 0
      buffer_size = @buffer.size

      @buffer.each_line("\r\n") do |line|
        # do not process last line if incomplete
        if line.size + processed == buffer_size && !line.end_with?("\r\n")
          break
        end

        processed+= line.size

        if @current_msg.nil?
          match = line.match CLASSIFIER

          if match.nil?
            if line == "\r\n" || line.empty?
            elsif line.include?(':')
              syntax_error_encountered line
            elsif line =~ /^(.+)\r\n$/
              immediate_msg= Response.new
              immediate_msg.text_body = $1
              message_received immediate_msg
            end
            next
          end

          @current_msg = if match[:event]
            Event.new match[:event_name]
          elsif match[:success] || match[:pong]
            Response.new
          elsif match[:error]
            Error.new
          end

        elsif line == "\r\n"
          case @current_msg
          when Error
            error_received @current_msg
          else
            message_received @current_msg
          end
          @current_msg = nil

        else
          i= line.index(': ')
          if i
            line.chop!
            key= line[0..i-1]
            value= line[i+1..-1]
            value.lstrip!
            @current_msg[key]= value
          else
            # unsuported use case
            puts <<~EOS
              current_msg: #{@current_msg.inspect}
              line: #{line.inspect}
              buffer: #{@buffer.inspect}
            EOS

            if defined?(Sentry)
              begin
                raise
              rescue => e
                Sentry.capture_exception(e, level: "error")
              end
            end

            @current_msg = nil
          end
        end
      end

    rescue
      @current_msg = nil
      raise
    ensure
      @buffer.slice! 0, processed
    end

    ##
    # Called after a response or event has been successfully parsed.
    #
    # @param [Response, Event] message The message just received
    #
    def message_received(message)
      @delegate.message_received message
    end

    ##
    # Called after an AMI error has been successfully parsed.
    #
    # @param [Response, Event] message The message just received
    #
    def error_received(message)
      @delegate.error_received message
    end

    ##
    # Called when there's a syntax error on the socket. This doesn't happen as often as it should because, in many cases,
    # it's impossible to distinguish between a syntax error and an immediate packet.
    #
    # @param [String] ignored_chunk The offending text which caused the syntax error.
    def syntax_error_encountered(ignored_chunk)
      @delegate.syntax_error_encountered ignored_chunk
    end
  end
end
