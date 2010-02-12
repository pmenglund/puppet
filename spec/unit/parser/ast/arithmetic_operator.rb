#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

describe Puppet::Parser::AST::ArithmeticOperator do

    ast = Puppet::Parser::AST

    before :each do
        @scope = Puppet::Parser::Scope.new()
        @one = stub 'lval', :safeevaluate => 1
        @two = stub 'rval', :safeevaluate => 2
    end

    it "should evaluate both branches" do
        lval = stub "lval"
        lval.expects(:safeevaluate).returns(1)
        rval = stub "rval"
        rval.expects(:safeevaluate).returns(2)

        operator = ast::ArithmeticOperator.new :rval => rval, :operator => "+", :lval => lval
        operator.evaluate
    end

    it "should fail for an unknown operator" do
        lambda { operator = ast::ArithmeticOperator.new :lval => @one, :operator => "%", :rval => @two }.should raise_error
    end

    it "should call Puppet::Parser::Scope.number?" do
        Puppet::Parser::Scope.expects(:number?).with(1).returns(1)
        Puppet::Parser::Scope.expects(:number?).with(2).returns(2)

        ast::ArithmeticOperator.new(:lval => @one, :operator => "+", :rval => @two).evaluate
    end


    %w{ + - * / << >>}.each do |op|
        it "should call ruby Numeric '#{op}'" do
            one = stub 'one'
            two = stub 'two'
            operator = ast::ArithmeticOperator.new :lval => @one, :operator => op, :rval => @two
            Puppet::Parser::Scope.stubs(:number?).with(1).returns(one)
            Puppet::Parser::Scope.stubs(:number?).with(2).returns(two)
            one.expects(:send).with(op,two)
            operator.evaluate
        end
    end

    it "should work even with numbers embedded in strings" do
        two = stub 'two', :safeevaluate => "2"
        one = stub 'one', :safeevaluate => "1"
        operator = ast::ArithmeticOperator.new :lval => two, :operator => "+", :rval => one
        operator.evaluate.should == 3
    end

    it "should work even with floats" do
        two = stub 'two', :safeevaluate => 2.53
        one = stub 'one', :safeevaluate => 1.80
        operator = ast::ArithmeticOperator.new :lval => two, :operator => "+", :rval => one
        operator.evaluate.should == 4.33
    end

    it "should work for variables too" do
        @scope.expects(:future_for).with("one").returns(stub('future_one', :value => 1))
        @scope.expects(:future_for).with("two").returns(stub('future_two', :value => 2))
        one = ast::Variable.new( :value => "one", :scope => @scope )
        two = ast::Variable.new( :value => "two", :scope => @scope )

        operator = ast::ArithmeticOperator.new :lval => one, :operator => "+", :rval => two
        operator.evaluate.should == 3
    end

end
