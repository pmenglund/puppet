#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

describe Puppet::Parser::AST::Function do
    before :each do
        @scope = mock 'scope'
    end

    describe "when initializing" do
        it "should not fail if the function doesn't exist" do
            Puppet::Parser::Functions.stubs(:function).returns(false)

            lambda{ Puppet::Parser::AST::Function.new :name => "dontexist", :scope => @scope }.should_not raise_error(Puppet::ParseError)

        end
    end

    it "should return its representation with to_s" do
        args = stub 'args', :is_a? => true, :to_s => "[a, b]"

        Puppet::Parser::AST::Function.new(:name => "func", :arguments => args).to_s.should == "func(a, b)"
    end

    describe "when evaluating" do

        it "should fail if the function doesn't exist" do
            Puppet::Parser::Functions.stubs(:function).returns(false)
            func = Puppet::Parser::AST::Function.new :name => "dontexist", :scope => @scope

            lambda{ func.evaluate }.should raise_error(Puppet::ParseError)
        end

        it "should fail if the function is a statement used as rvalue" do
            Puppet::Parser::Functions.stubs(:function).with("exist").returns(true)
            Puppet::Parser::Functions.stubs(:rvalue?).with("exist").returns(false)

            func = Puppet::Parser::AST::Function.new :name => "exist", :ftype => :rvalue, :scope => @scope

            lambda{ func.evaluate }.should raise_error(Puppet::ParseError, "Function 'exist' does not return a value")
        end

        it "should fail if the function is an rvalue used as statement" do
            Puppet::Parser::Functions.stubs(:function).with("exist").returns(true)
            Puppet::Parser::Functions.stubs(:rvalue?).with("exist").returns(true)

            func = Puppet::Parser::AST::Function.new :name => "exist", :ftype => :statement, :scope => @scope

            lambda{ func.evaluate }.should raise_error(Puppet::ParseError,"Function 'exist' must be the value of a statement")
        end

        it "should evaluate its arguments" do
            argument = stub 'arg'
            Puppet::Parser::Functions.stubs(:function).with("exist").returns(true)
            func = Puppet::Parser::AST::Function.new :name => "exist", :ftype => :statement, :arguments => argument, :scope => @scope
            @scope.stubs(:function_exist)

            argument.expects(:safeevaluate).returns("argument")

            func.evaluate
        end

        it "should call the underlying ruby function" do
            argument = stub 'arg', :safeevaluate => "nothing"
            Puppet::Parser::Functions.stubs(:function).with("exist").returns(true)
            func = Puppet::Parser::AST::Function.new :name => "exist", :ftype => :statement, :arguments => argument, :scope => @scope

            @scope.expects(:function_exist).with("nothing")

            func.evaluate
        end

        it "should return the ruby function return for rvalue functions" do
            argument = stub 'arg', :safeevaluate => "nothing"
            Puppet::Parser::Functions.stubs(:function).with("exist").returns(true)
            func = Puppet::Parser::AST::Function.new :name => "exist", :ftype => :statement, :arguments => argument, :scope => @scope
            @scope.stubs(:function_exist).with("nothing").returns("returning")

            func.evaluate.should == "returning"
        end

    end
end
