# RubyAMI

Eventmachine based fork

## Installation

    gem install ruby_ami

## Usage

```ruby
require 'ruby_ami'

EM::run do
  asterisk_ip= '127.0.0.1'
  asterisk_port= 5038
  asterisk_username= nil
  asterisk_password= nil

  logger = Logger.new(STDOUT)
  logger.level = Logger::INFO

  # asterisk connection
  stream= EM.connect(
    # EM.connect parameters
    asterisk_ip,
    asterisk_port,
    RubyAMI::Stream,

    # AMI credentials
    asterisk_username,
    asterisk_password,

    # event callback
    ->(e) {
      case e
      when RubyAMI::Stream::Connected
        puts "connected"
      when RubyAMI::Stream::Disconnected
        puts "disconnected"
      else
        puts "event received : #{e.name}: #{e.headers.inspect}"
      end
     },

    # optional reconnection callback
    ->(s) {
      EM::add_timer(1) {
        puts "reconnecting..."
        s.reconnect(asterisk_ip, asterisk_port)
      }
    },

    # optional logger
    logger
  )

  # async actions
  EM::next_tick do
    stream.async_send_action('Originate', 'Channel' => 'SIP/foo') do |response|
      puts response.inspect
    end
  end

  # sync actions in thread
  EM::defer do
    response= stream.send_action('Originate', 'Channel' => 'SIP/foo')
    puts response.inspect
  end

  # sync actions in fiber
  Fiber.new do
    response= stream.fiber_send_action('Originate', 'Channel' => 'SIP/foo')
    puts response.inspect
  end.resume
end
```

## Copyright

Copyright (c) 2013 Ben Langfeld, Jay Phillips. MIT licence (see LICENSE for details).
