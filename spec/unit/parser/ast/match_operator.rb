#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

describe Puppet::Parser::AST::MatchOperator do
    before :each do
        @scope = Puppet::Parser::Scope.new()

        @lval = stub 'lval'
        @lval.stubs(:safeevaluate).returns("this is a string")

        @rval = stub 'rval'
        @rval.stubs(:evaluate_match)

        @operator = Puppet::Parser::AST::MatchOperator.new :lval => @lval, :rval => @rval, :operator => "=~"
    end

    it "should evaluate the left operand" do
        @lval.expects(:safeevaluate)

        @operator.evaluate
    end

    it "should fail for an unknown operator" do
        lambda { operator = Puppet::Parser::AST::MatchOperator.new :lval => @lval, :operator => "unknown", :rval => @rval }.should raise_error
    end

    it "should evaluate_match the left operand" do
        @rval.expects(:evaluate_match).with("this is a string").returns(:match)

        @operator.evaluate
    end

    { "=~" => true, "!~" => false }.each do |op, res|
        it "should return #{res} if the regexp matches with #{op}" do
            match = stub 'match'
            @rval.stubs(:evaluate_match).with("this is a string").returns(match)

            operator = Puppet::Parser::AST::MatchOperator.new :lval => @lval, :rval => @rval, :operator => op
            operator.evaluate.should == res
        end

        it "should return #{!res} if the regexp doesn't match" do
            @rval.stubs(:evaluate_match).with("this is a string").returns(nil)

            operator = Puppet::Parser::AST::MatchOperator.new :lval => @lval, :rval => @rval, :operator => op
            operator.evaluate.should == !res
        end
    end
end
