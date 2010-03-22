#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

describe Puppet::Parser::AST::IfStatement do
    before :each do
        @scope = Puppet::Parser::Scope.new
    end

    describe "when evaluating" do

        before :each do
            @test = stub 'test'
            @test.stubs(:safeevaluate)

            @stmt = stub 'stmt'
            @stmt.stubs(:safeevaluate)

            @else = stub 'else'
            @else.stubs(:safeevaluate)

            @ifstmt = Puppet::Parser::AST::IfStatement.new :test => @test, :statements => @stmt, :scope => @scope
            @ifelsestmt = Puppet::Parser::AST::IfStatement.new :test => @test, :statements => @stmt, :else => @else, :scope => @scope
        end

        it "should evaluate test" do
            Puppet::Parser::Scope.stubs(:true?).returns(false)

            @test.expects(:safeevaluate)

            @ifstmt.evaluate
        end

        it "should evaluate if statements if test is true" do
            Puppet::Parser::Scope.stubs(:true?).returns(true)

            @stmt.expects(:safeevaluate)

            @ifstmt.evaluate
        end

        it "should not evaluate if statements if test is false" do
            Puppet::Parser::Scope.stubs(:true?).returns(false)

            @stmt.expects(:safeevaluate).never

            @ifstmt.evaluate
        end

        it "should evaluate the else branch if test is false" do
            Puppet::Parser::Scope.stubs(:true?).returns(false)

            @else.expects(:safeevaluate)

            @ifelsestmt.evaluate
        end

        it "should not evaluate the else branch if test is true" do
            Puppet::Parser::Scope.stubs(:true?).returns(true)

            @else.expects(:safeevaluate).never

            @ifelsestmt.evaluate
        end

        it "should reset ephemeral statements after evaluation" do
            Puppet::Parser::Scope.stubs(:true?).returns(true)

            @stmt.expects(:safeevaluate)
            @scope.expects(:unset_ephemeral_var)

            @ifstmt.evaluate
        end
    end
end
