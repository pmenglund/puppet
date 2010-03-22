#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

describe Puppet::Parser::AST::ComparisonOperator do
    before :each do
        @scope = Puppet::Parser::Scope.new
        @one = stub 'one', :safeevaluate => "1"
        @two = stub 'two', :safeevaluate => "2"
    end

    it "should evaluate both branches" do
        lval = stub "lval"
        lval.expects(:safeevaluate)
        rval = stub "rval"
        rval.expects(:safeevaluate)

        operator = Puppet::Parser::AST::ComparisonOperator.new :lval => lval, :operator => "==", :rval => rval
        operator.evaluate
    end

    it "should convert arguments strings to numbers if they are" do
        Puppet::Parser::Scope.expects(:number?).with("1").returns(1)
        Puppet::Parser::Scope.expects(:number?).with("2").returns(2)

        operator = Puppet::Parser::AST::ComparisonOperator.new :lval => @one, :operator => "==", :rval => @two
        operator.evaluate
    end

    %w{< > <= >= ==}.each do |oper|
        it "should use string comparison #{oper} if operands are strings" do
            lval = stub 'one', :safeevaluate => "one"
            rval = stub 'two', :safeevaluate => "two"
            Puppet::Parser::Scope.stubs(:number?).with("one").returns(nil)
            Puppet::Parser::Scope.stubs(:number?).with("two").returns(nil)

            operator = Puppet::Parser::AST::ComparisonOperator.new :lval => lval, :operator => oper, :rval => rval
            operator.evaluate.should == "one".send(oper,"two")
        end
    end

    it "should fail with arguments of different types" do
        lval = stub 'one', :safeevaluate => "one"
        rval = stub 'two', :safeevaluate => "2"
        Puppet::Parser::Scope.stubs(:number?).with("one").returns(nil)
        Puppet::Parser::Scope.stubs(:number?).with("2").returns(2)

        operator = Puppet::Parser::AST::ComparisonOperator.new :lval => lval, :operator => ">", :rval => rval
        lambda { operator.evaluate }.should raise_error(ArgumentError)
    end

    it "should fail for an unknown operator" do
        lambda { operator = Puppet::Parser::AST::ComparisonOperator.new :lval => @one, :operator => "or", :rval => @two }.should raise_error
    end

    %w{< > <= >= ==}.each do |oper|
        it "should return the result of using '#{oper}' to compare the left and right sides" do
            operator = Puppet::Parser::AST::ComparisonOperator.new :lval => @one, :operator => oper, :rval => @two

            operator.evaluate.should == 1.send(oper,2)
        end
    end

    it "should return the result of using '!=' to compare the left and right sides" do
        operator = Puppet::Parser::AST::ComparisonOperator.new :lval => @one, :operator => '!=', :rval => @two

        operator.evaluate.should == true
    end

    it "should work for variables too" do
        @scope.expects(:future_for).with("one").returns(stub('future_one', :value => 1))
        @scope.expects(:future_for).with("two").returns(stub('future_two', :value => 2))
        one = Puppet::Parser::AST::Variable.new( :value => "one", :scope => @scope )
        two = Puppet::Parser::AST::Variable.new( :value => "two", :scope => @scope )

        operator = Puppet::Parser::AST::ComparisonOperator.new :lval => one, :operator => "<", :rval => two, :scope => @scope
        operator.evaluate.should == true
    end

    # see ticket #1759
    %w{< > <= >=}.each do |oper|
        it "should return the correct result of using '#{oper}' to compare 10 and 9" do
            ten = stub 'one', :safeevaluate => "10"
            nine = stub 'two', :safeevaluate => "9"
            operator = Puppet::Parser::AST::ComparisonOperator.new :lval => ten, :operator => oper, :rval => nine

            operator.evaluate.should == 10.send(oper,9)
        end
    end

end
