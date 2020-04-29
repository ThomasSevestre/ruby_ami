# encoding: utf-8
require 'spec_helper'

module RubyAMI
  describe Stream do
    let(:server_port) { 50000 - rand(1000) }

    let(:username) { nil }
    let(:password) { nil }

    def message_received(m)
      (@message_received||= Queue.new)<< m
    end

    def client_messages
      messages = []
      while !@message_received.empty?
        messages << @message_received.pop
      end
      messages
    end

    def mocked_server(times = nil, fake_client = nil, &block)
      mock_target = MockServer.new
      mock_target.should_receive(:receive_data).send(*(times ? [:exactly, times] : [:at_least, 1])).with &block

      s = ServerMock.new '127.0.0.1', server_port, mock_target

      Thread.new do
        begin
          EM::run do
            @stream= EM.connect(
              '127.0.0.1', server_port, Stream,
              username, password, ->(m){ message_received(m)}
            )
            fake_client.call if fake_client
          end
        rescue => e
          puts "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
        end
      end

      Celluloid::Actor.join s

    ensure
      EM::next_tick{ EM::stop }
      sleep 0.01 while EM::reactor_running?
    end

    def expect_connected_event
      should_receive(:message_received).with Stream::Connected.new
    end

    def expect_disconnected_event
      should_receive(:message_received).with Stream::Disconnected.new
    end

    before { @sequence = 1 }

    describe "after connection" do
      it "should be started" do
        expect_connected_event
        expect_disconnected_event
        mocked_server 0, -> { @stream.started?.should be_true }
      end

      it "can send an action" do
        expect_connected_event
        expect_disconnected_event
        
        mocked_server(1, lambda do
          EM::defer do
            @stream.send_action('Command')
          end
        end) do |val, server|
          val.should == <<~ACTION
            Action: command\r
            ActionID: #{RubyAMI.new_uuid}\r
            \r
          ACTION

          server.send_data <<~EVENT
            Response: Success
            ActionID: #{RubyAMI.new_uuid}
            Message: Recording started

          EVENT
        end
      end

      it "can send an action from a fiber" do
        expect_connected_event
        expect_disconnected_event

        mocked_server(1, lambda do
          Fiber.new do
            @stream.fiber_send_action('Command')
          end.resume
        end) do |val, server|
          val.should == <<~ACTION
            Action: command\r
            ActionID: #{RubyAMI.new_uuid}\r
            \r
          ACTION

          server.send_data <<~EVENT
            Response: Success
            ActionID: #{RubyAMI.new_uuid}
            Message: Recording started

          EVENT
        end
      end

      it "can send an action with headers" do
        expect_connected_event
        expect_disconnected_event
        mocked_server(1, lambda do
          EM::defer do
            @stream.send_action('Command', 'Command' => 'RECORD FILE evil')
          end
        end) do |val, server|
          val.should == <<~ACTION
            Action: command\r
            ActionID: #{RubyAMI.new_uuid}\r
            Command: RECORD FILE evil\r
            \r
          ACTION

          server.send_data <<~EVENT
            Response: Success
            ActionID: #{RubyAMI.new_uuid}
            Message: Recording started

          EVENT
        end
      end

      it "can process an action with a Response: Follows result" do
        action_id = RubyAMI.new_uuid
        response = nil
        mocked_server(1, lambda do
          EM::defer do
            response = @stream.send_action('Command', 'Command' => 'dialplan add extension 1,1,AGI,agi:async into adhearsion-redirect')
          end
        end) do |val, server|
          val.should == <<~ACTION
            Action: command\r
            ActionID: #{action_id}\r
            Command: dialplan add extension 1,1,AGI,agi:async into adhearsion-redirect\r
            \r
          ACTION

          server.send_data <<~EVENT
            Response: Follows
            Privilege: Command
            ActionID: #{action_id}
            Extension '1,1,AGI(agi:async)' added into 'adhearsion-redirect' context
            --END COMMAND--

          EVENT
        end

        expected_response = Response.new 'Privilege' => 'Command', 'ActionID' => action_id
        expected_response.text_body = %q{Extension '1,1,AGI(agi:async)' added into 'adhearsion-redirect' context}
        response.should == expected_response
      end

      context "with a username and password set" do
        let(:username) { 'fred' }
        let(:password) { 'jones' }

        it "should log itself in" do
          expect_connected_event
          expect_disconnected_event
          mocked_server(1, lambda { }) do |val, server|
            val.should == <<~ACTION
              Action: login\r
              ActionID: #{RubyAMI.new_uuid}\r
              Username: fred\r
              Secret: jones\r
              Events: On\r
              \r
            ACTION

            server.send_data <<~EVENT
              Response: Success
              ActionID: #{RubyAMI.new_uuid}
              Message: Authentication accepted

            EVENT
          end
        end
      end
    end

    it 'sends events to the client when the stream is ready' do
      mocked_server(1, lambda { @stream.send_data 'Foo' }) do |val, server|
        server.send_data <<-EVENT
Event: Hangup
Channel: SIP/101-3f3f
Uniqueid: 1094154427.10
Cause: 0

        EVENT
      end

      client_messages.should be == [
        Stream::Connected.new,
        Event.new('Hangup', 'Channel' => 'SIP/101-3f3f', 'Uniqueid' => '1094154427.10', 'Cause' => '0'),
        Stream::Disconnected.new
      ]
    end

    describe 'when a response is received' do
      before do
        expect_connected_event
        expect_disconnected_event
      end

      it 'should be returned from #send_action' do
        response = nil
        mocked_server(1, lambda do
          EM::defer do
            response = @stream.send_action 'Command', 'Command' => 'RECORD FILE evil'
          end
        end) do |val, server|
          server.send_data <<~EVENT
            Response: Success
            ActionID: #{RubyAMI.new_uuid}
            Message: Recording started

          EVENT
        end

        response.should == Response.new('ActionID' => RubyAMI.new_uuid, 'Message' => 'Recording started')
      end

      describe 'when it is an error' do
        it 'should be raised by #send_action, but not kill the stream' do
          send_action = lambda do
            EM::defer do
              expect { @stream.send_action 'status' }.to raise_error(RubyAMI::Error, 'Action failed')
              @stream.stopped?.should be false
            end
          end

          mocked_server(1, send_action) do |val, server|
            server.send_data <<~EVENT
              Response: Error
              ActionID: #{RubyAMI.new_uuid}
              Message: Action failed

            EVENT
          end
        end

        it 'should be raised by #fiber_send_action, but not kill the stream' do
          send_action = lambda do
            Fiber.new do
              expect { @stream.fiber_send_action 'status' }.to raise_error(RubyAMI::Error, 'Action failed')
              @stream.stopped?.should be false
            end.resume
          end

          mocked_server(1, send_action) do |val, server|
            server.send_data <<~EVENT
              Response: Error
              ActionID: #{RubyAMI.new_uuid}
              Message: Action failed

            EVENT
          end
        end
      end

      describe 'for a causal action' do
        let :expected_events do
          [
            Event.new('PeerEntry', 'ActionID' => RubyAMI.new_uuid, 'Channeltype' => 'SIP', 'ObjectName' => 'usera'),
            Event.new('PeerlistComplete', 'ActionID' => RubyAMI.new_uuid, 'EventList' => 'Complete', 'ListItems' => '2')
          ]
        end

        let :expected_response do
          Response.new('ActionID' => RubyAMI.new_uuid, 'Message' => 'Events to follow').tap do |response|
            response.events = expected_events
          end
        end

        it "should return the response with events" do
          response = nil
          mocked_server(1, lambda do
            EM::defer do
              response = @stream.send_action 'sippeers'
            end
          end) do |val, server|
            server.send_data <<~EVENT
              Response: Success
              ActionID: #{RubyAMI.new_uuid}
              Message: Events to follow

              Event: PeerEntry
              ActionID: #{RubyAMI.new_uuid}
              Channeltype: SIP
              ObjectName: usera

              Event: PeerlistComplete
              EventList: Complete
              ListItems: 2
              ActionID: #{RubyAMI.new_uuid}

            EVENT
          end

          response.should == expected_response
        end
      end
    end

    it 'puts itself in the stopped state and fires a disconnected event when unbound' do
      expect_connected_event
      expect_disconnected_event
      mocked_server(1, lambda { @stream.send_data 'Foo' }) do |val, server|
        @stream.stopped?.should be false
      end
      @stream.stopped?.should be true
    end
  end
end
