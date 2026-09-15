# frozen_string_literal: true
module RubyAMI
  class Error < StandardError
    attr_accessor :message, :action

    def initialize(headers = {})
      @headers = headers
    end

    def [](key)
      @headers[key]
    end

    # Since Asterisk 14, a failed Command action answers with the fixed text
    # "Message: Command output follows" and the real reason in one or more
    # "Output:" headers, one per CLI line. Output lines are therefore appended
    # to the message, and joined in the headers so repeated keys are not lost.
    def []=(key,value)
      case key
      when 'Message'
        self.message = @headers.key?('Output') ? "#{value}: #{@headers['Output']}" : value
        @headers[key] = value
      when 'Output'
        self.message = message.nil? ? value : "#{message}#{message_separator}#{value}"
        @headers[key] = @headers[key].nil? ? value : "#{@headers[key]}\n#{value}"
      else
        @headers[key] = value
      end
    end

    def action_id
      @headers['ActionID']
    end

    private

    # First Output line follows the Message on the same line, next ones
    # go on their own line.
    def message_separator
      @headers.key?('Output') ? "\n" : ': '
    end
  end
end # RubyAMI
