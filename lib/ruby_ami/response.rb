# frozen_string_literal: true
module RubyAMI
  ##
  # This is the object containing a response from Asterisk.
  #
  class Response
    def self.from_immediate_response(text)
      instance= new
      instance.text_body = text
      instance
    end

    attr_accessor :text_body, # For "Response: Follows" sections
                  :events

    def initialize(headers = {})
      @headers = headers
      @events = []
    end

    def has_text_body?
      !!@text_body
    end

    def headers
      @headers.clone
    end

    def merge_headers!(hash)
      @headers.merge!(hash)
    end

    def [](arg)
      @headers[arg.to_s]
    end

    def []=(key,value)
      @headers[key.to_s] = value
    end

    def action_id
      @headers['ActionID']
    end

    def ==(o)
      self.class == o.class && @headers == o.headers
    end
  end
end # RubyAMI
