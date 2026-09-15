# frozen_string_literal: true
module RubyAMI
  ##
  # This is the object containing a response from Asterisk.
  #
  class Response
    attr_accessor :text_body # For immediate messages (lines outside of any header block)

    def initialize(headers = {})
      @headers = headers
    end

    def events  # for causal events
      @events ||= []
    end

    def has_text_body?
      !!@text_body
    end

    def [](arg)
      @headers[arg]
    end

    # The Command action answers with one "Output:" header per CLI line,
    # repeated Output keys are joined so no line is lost.
    def []=(key,value)
      if key == 'Output' && @headers.key?(key)
        @headers[key] = "#{@headers[key]}\n#{value}"
      else
        @headers[key] = value
      end
    end

    def action_id
      @headers['ActionID']
    end

    def ==(o)
      self.class == o.class && @headers == o.headers
    end

    protected

    attr_reader :headers
  end
end # RubyAMI
