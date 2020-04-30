# frozen_string_literal: true
module RubyAMI
  class Lexer
    PROMPT            = /Asterisk Call Manager\/([0-9.]+)\r\n/
    SUCCESS           = /response: *success/i
    PONG              = /response: *pong/i
    EVENT             = /event: *(?<event_name>.*)?/i
    ERROR             = /response: *error/i
    FOLLOWS           = /response: *follows/i
    HEADER_SLICE      = /.*\r\n/
    CLASSIFIER        = /((?<event>#{EVENT})|(?<success>#{SUCCESS})|(?<pong>#{PONG})|(?<follows>#{FOLLOWS})|(?<error>#{ERROR}))\r\n/i

    attr_accessor :ami_version

    def initialize(delegate = nil)
      @delegate = delegate
      @buffer = String.new
      @ami_version = nil
      reset_current_message
    end

    def <<(new_data)
      @buffer << new_data
      parse_buffer
    end

    private

    def reset_current_message
      @current_msg= nil
      @current_response_follows= false
      @current_end_command= false
    end

    def parse_buffer
      # Special case for the protocol header
      if @buffer.start_with?("Asterisk Call Manager") && @buffer =~ PROMPT
        @ami_version = $1
        @buffer.slice! HEADER_SLICE
        reset_current_message
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
              immediate_msg
              message_received immediate_msg
            end
            next
          end

          @current_msg = if match[:event]
            Event.new match[:event_name]
          elsif match[:success] || match[:pong]
            Response.new
          elsif match[:follows]
            @current_response_follows = true
            msg= Response.new
            msg.text_body = String.new
            msg
          elsif match[:error]
            Error.new
          end

        elsif line == "\r\n" || ( @current_end_command && line.include?("--END COMMAND--") )
          if @current_end_command
            @current_msg.text_body.chop!
          end

          case @current_msg
          when Error
            error_received @current_msg
          else
            message_received @current_msg
          end
          reset_current_message

        elsif @current_end_command
          @current_msg.text_body<< line

        else
          i= line.index(': ')
          if i
            line.chop!
            key= line[0..i-1]
            value= line[i+1..-1]
            value.lstrip!
            @current_msg[key]= value
          elsif @current_response_follows
            @current_end_command= true
            @current_msg.text_body<< line
          else
            raise
          end
        end
      end

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

