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

    def []=(key,value)
      self.message = value if key == 'Message'
      @headers[key] = value
    end

    def merge_headers!(hash)
      self.message = hash['Message'] if hash.has_key?('Message')
      @headers.merge!(hash)
    end

    def action_id
      @headers['ActionID']
    end
  end
end # RubyAMI
