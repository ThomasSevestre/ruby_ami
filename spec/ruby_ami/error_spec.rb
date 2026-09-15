# encoding: utf-8
require 'spec_helper'

module RubyAMI
  describe Error do
    subject { Error.new }

    describe "#[]=" do
      it "takes the message from the Message header" do
        subject['ActionID'] = '1234'
        subject['Message'] = 'Action failed'

        subject.message.should == 'Action failed'
        subject['Message'].should == 'Action failed'
        subject.action_id.should == '1234'
      end

      it "appends a single Output line to the message" do
        subject['Message'] = 'Command output follows'
        subject['Output'] = 'Unable to retrieve endpoint 1234'

        subject.message.should == "Command output follows: Unable to retrieve endpoint 1234"
        subject['Output'].should == 'Unable to retrieve endpoint 1234'
      end

      it "keeps every Output line when the header is repeated" do
        subject['Message'] = 'Command output follows'
        subject['Output'] = 'No such command'
        subject['Output'] = 'Usage: devstate change <device> <state>'
        subject['Output'] = '       Change a custom device to a new state.'

        subject.message.should == <<~MSG.chomp
          Command output follows: No such command
          Usage: devstate change <device> <state>
                 Change a custom device to a new state.
        MSG
        subject['Output'].should == <<~OUT.chomp
          No such command
          Usage: devstate change <device> <state>
                 Change a custom device to a new state.
        OUT
      end

      it "builds the same message when Output arrives before Message" do
        subject['Output'] = 'first line'
        subject['Output'] = 'second line'
        subject['Message'] = 'Command output follows'

        subject.message.should == "Command output follows: first line\nsecond line"
      end

      it "uses the Output text alone when there is no Message header" do
        subject['Output'] = 'Unable to retrieve endpoint 1234'

        subject.message.should == 'Unable to retrieve endpoint 1234'
      end
    end
  end # Error
end # RubyAMI
