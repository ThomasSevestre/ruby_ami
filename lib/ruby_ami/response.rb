# frozen_string_literal: true
module RubyAMI
  ##
  # This is the object containing a response from Asterisk.
  #
  class Response
    attr_accessor :text_body # For "Response: Follows" sections

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

    def []=(key,value)
      @headers[key] = value
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
