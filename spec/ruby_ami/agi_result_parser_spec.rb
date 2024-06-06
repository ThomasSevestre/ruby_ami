# encoding: utf-8
require 'spec_helper'

module RubyAMI
  describe AGIResultParser do
    subject { described_class.new result_string }

    context 'with something that does not match the valid format' do
      let(:result_string) { 'foobar' }

      it 'should raise ArgumentError on creation' do
        expect { subject }.to raise_error(ArgumentError, /format/)
      end
    end

    context 'with a simple result with no data' do
      let(:result_string) { "200%20result=123%0A" }

      it "parse code" do
        subject.code.should == 200
      end
      it "parse result" do
        subject.result.should == 123
      end
      it "parse data" do
        subject.data.should == ''
      end
      it "parse data_hash" do
        subject.data_hash.should == nil
      end
    end

    context 'with a simple unescaped result with no data' do
      let(:result_string) { "200 result=123" }

      it "parse code" do
        subject.code.should == 200
      end
      it "parse result" do
        subject.result.should == 123
      end
      it "parse data" do
        subject.data.should == ''
      end
      it "parse data_hash" do
        subject.data_hash.should == nil
      end
    end

    context 'with a result and data in parens' do
      let(:result_string) { "200%20result=-123%20(timeout)%0A" }

      it "parse code" do
        subject.code.should == 200
      end
      it "parse result" do
        subject.result.should == -123
      end
      it "parse data" do
        subject.data.should == 'timeout'
      end
      it "parse data_hash" do
        subject.data_hash.should == nil
      end
    end

    context 'with a result and key-value data' do
      let(:result_string) { "200%20result=123%20foo=bar%0A" }

      it "parse code" do
        subject.code.should == 200
      end
      it "parse result" do
        subject.result.should == 123
      end
      it "parse data" do
        subject.data.should == 'foo=bar'
      end
      it "parse data_hash" do
        subject.data_hash.should == {'foo' => 'bar'}
      end
    end

    context 'with a 5xx error' do
      let(:result_string) { "510%20Invalid%20or%20unknown%20command%0A" }

      it "parse code" do
        subject.code.should == 510
      end
      it "parse result" do
        subject.result.should be_nil
      end
      it "parse data" do
        subject.data.should == 'Invalid or unknown command'
      end
      it "parse data_hash" do
        subject.data_hash.should be_nil
      end
    end
  end
end
