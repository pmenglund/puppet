#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

describe Puppet::Parser::AST::Nop do

    before do
        @scope = mock 'scope'
    end

    it "should do nothing on evaluation" do
        Puppet::Parser::AST.expects(:safeevaluate).never
        Puppet::Parser::AST::Nop.new({}).evaluate
    end

    it "should not return anything" do
        Puppet::Parser::AST::Nop.new({}).evaluate.should be_nil
    end

end
