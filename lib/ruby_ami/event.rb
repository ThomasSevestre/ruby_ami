# frozen_string_literal: true
require 'ruby_ami/response'

module RubyAMI
  class Event < Response
    attr_reader :name

    def initialize(name, headers = {})
      super headers
      @name = name
    end

    def ==(o)
      super && @name == o.name
    end
  end
end # RubyAMI
