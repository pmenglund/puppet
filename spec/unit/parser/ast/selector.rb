#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

describe Puppet::Parser::AST::Selector do
  before :each do
    @scope = Puppet::Parser::Scope.new
  end

  describe "when evaluating" do

    before :each do
      @scope = stub_everything 'scope'

      @param = stub 'param'
      @param.stubs(:safeevaluate).returns("value")

      @value1 = stub 'value1'
      @param1 = stub_everything 'param1'
      @param1.stubs(:safeevaluate).returns(@param1)
      @param1.stubs(:respond_to?).with(:downcase).returns(false)
      @value1.stubs(:param).returns(@param1)
      @value1.stubs(:value).returns(@value1)

      @value2 = stub 'value2'
      @param2 = stub_everything 'param2'
      @param2.stubs(:safeevaluate).returns(@param2)
      @param2.stubs(:respond_to?).with(:downcase).returns(false)
      @value2.stubs(:param).returns(@param2)
      @value2.stubs(:value).returns(@value2)

      @values = stub 'values', :instance_of? => true
      @values.stubs(:each).multiple_yields(@value1, @value2)

      @selector = Puppet::Parser::AST::Selector.new :param => @param, :values => @values, :scope => @scope
      @selector.stubs(:fail)
    end

    it "should evaluate param" do
      @param.expects(:safeevaluate)

      @selector.evaluate
    end

    it "should scan each option" do
      @values.expects(:each).multiple_yields(@value1, @value2)

      @selector.evaluate
    end

    describe "when scanning values" do
      it "should evaluate first matching option" do
        @param2.stubs(:evaluate_match).with { |*arg| arg[0] == "value" }.returns(true)
        @value2.expects(:safeevaluate)

        @selector.evaluate
      end

      it "should return the first matching evaluated option" do
        @param2.stubs(:evaluate_match).with { |*arg| arg[0] == "value" }.returns(true)
        @value2.stubs(:safeevaluate).returns(:result)

        @selector.evaluate.should == :result
      end

      it "should evaluate the default option if none matched" do
        @param1.stubs(:is_a?).with(Puppet::Parser::AST::Default).returns(true)
        @value1.expects(:safeevaluate).returns(@param1)

        @selector.evaluate
      end

      it "should return the default evaluated option if none matched" do
        result = stub 'result'
        @param1.stubs(:is_a?).with(Puppet::Parser::AST::Default).returns(true)
        @value1.stubs(:safeevaluate).returns(result)

        @selector.evaluate.should == result
      end

      it "should return nil if nothing matched" do
        @selector.evaluate.should be_nil
      end

      it "should delegate matching to evaluate_match" do
        @param1.expects(:evaluate_match).with { |*arg| arg[0] == "value" }
        @selector.evaluate
      end

      it "should transmit the sensitive parameter to evaluate_match" do
        Puppet.stubs(:[]).with(:casesensitive).returns(:sensitive)
        @param1.expects(:evaluate_match).with { |*arg| arg[1][:sensitive] == :sensitive }

        @selector.evaluate
      end

      it "should transmit the AST file and line to evaluate_match" do
        @selector.file = :file
        @selector.line = :line
        @param1.expects(:evaluate_match).with { |*arg| arg[1][:file] == :file and arg[1][:line] == :line }

        @selector.evaluate
      end


      it "should evaluate the matching param" do
        @param1.stubs(:evaluate_match).with { |*arg| arg[0] == "value" }.returns(true)
        @value1.expects(:safeevaluate)
        @selector.evaluate
      end

      it "should return this evaluated option if it matches" do
        @param1.stubs(:evaluate_match).with { |*arg| arg[0] == "value" }.returns(true)
        @value1.stubs(:safeevaluate).returns(:result)
        @selector.evaluate.should == :result
      end

      it "should unset scope ephemeral variables after option evaluation" do
        @param1.stubs(:evaluate_match).with { |*arg| arg[0] == "value" }.returns(true)
        @value1.stubs(:safeevaluate).returns(:result)
        @scope.expects(:unset_ephemeral_var)
        @selector.evaluate
      end

      it "should not leak ephemeral variables even if evaluation fails" do
        @param1.stubs(:evaluate_match).with { |*arg| arg[0] == "value" }.returns(true)
        @value1.stubs(:safeevaluate).raises
        @scope.expects(:unset_ephemeral_var)
        lambda { @selector.evaluate }.should raise_error
      end

      it "should fail if there is no default" do
        @selector.expects(:fail)
        @selector.evaluate
      end
    end
  end
  describe "when converting to string" do
    it "should produce a string version of this selector" do
      values = Puppet::Parser::AST::ASTArray.new :children => [ Puppet::Parser::AST::ResourceParam.new(:param => "type", :value => "value", :add => false, :scope => @scope) ]
      param = Puppet::Parser::AST::Variable.new :value => "myvar", :scope => @scope
      selector = Puppet::Parser::AST::Selector.new :param => param, :values => values, :scope => @scope
      selector.to_s.should == "$myvar ? { type => value }"
    end
  end
end
