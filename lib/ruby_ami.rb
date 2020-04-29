require "eventmachine"
require "concurrent/ivar"

require "logger"

class Logger
  alias :trace :debug
end

module RubyAMI
  def self.new_uuid
    SecureRandom.uuid
  end
end

%w{
  action
  agi_result_parser
  async_agi_environment_parser
  error
  event
  lexer
  response
  stream
  version
}.each { |f| require "ruby_ami/#{f}" }
