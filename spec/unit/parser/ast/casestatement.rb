#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

describe Puppet::Parser::AST::CaseStatement do
    before :each do
        @scope = Puppet::Parser::Scope.new()
    end

    describe "when evaluating" do

        before :each do
            @scope = stub 'scope', :unset_ephemeral_var => nil
            @test = stub 'test'
            @test.stubs(:safeevaluate).returns("value")

            @option1 = stub 'option1', :eachopt => nil, :default? => false
            @option2 = stub 'option2', :eachopt => nil, :default? => false

            @options = stub 'options'
            @options.stubs(:each).multiple_yields(@option1, @option2)

            @casestmt = Puppet::Parser::AST::CaseStatement.new :test => @test, :options => @options, :scope => @scope
        end

        it "should evaluate test" do
            @test.expects(:safeevaluate)

            @casestmt.evaluate
        end

        it "should scan each option" do
            @options.expects(:each).multiple_yields(@option1, @option2)

            @casestmt.evaluate
        end

        describe "when scanning options" do
            before :each do
                @opval1 = stub_everything 'opval1'
                @option1.stubs(:eachopt).yields(@opval1)

                @opval2 = stub_everything 'opval2'
                @option2.stubs(:eachopt).yields(@opval2)
            end

            it "should evaluate each sub-option" do
                @option1.expects(:eachopt)
                @option2.expects(:eachopt)

                @casestmt.evaluate
            end

            it "should evaluate first matching option" do
                @opval2.stubs(:evaluate_match).with{ |*arg| arg[0] = "value" }.returns(true)
                @option2.expects(:safeevaluate)

                @casestmt.evaluate
            end

            it "should evaluate_match with sensitive parameter" do
                Puppet.stubs(:[]).with(:casesensitive).returns(true)
                @opval1.expects(:evaluate_match).with { |*arg| arg[1][:sensitive] == true }

                @casestmt.evaluate
            end

            it "should return the first matching evaluated option" do
                @opval2.stubs(:evaluate_match).with { |*arg| arg[0] == "value" }.returns(true)
                @option2.stubs(:safeevaluate).returns(:result)

                @casestmt.evaluate.should == :result
            end

            it "should evaluate the default option if none matched" do
                @option1.stubs(:default?).returns(true)
                @option1.expects(:safeevaluate)

                @casestmt.evaluate
            end

            it "should return the default evaluated option if none matched" do
                @option1.stubs(:default?).returns(true)
                @option1.stubs(:safeevaluate).returns(:result)

                @casestmt.evaluate.should == :result
            end

            it "should return nil if nothing matched" do
                @casestmt.evaluate.should be_nil
            end

            it "should match and set scope ephemeral variables" do
                @opval1.expects(:evaluate_match).with { |*arg| arg[0] = "value" }
                @casestmt.evaluate
            end

            it "should evaluate this regex option if it matches" do
                @opval1.stubs(:evaluate_match).with { |*arg| arg[0] = "value" }.returns(true)
                @option1.expects(:safeevaluate)
                @casestmt.evaluate
            end

            it "should return this evaluated regex option if it matches" do
                @opval1.stubs(:evaluate_match).with { |*arg| arg[0] = "value" }.returns(true)
                @option1.stubs(:safeevaluate).returns(:result)
                @casestmt.evaluate.should == :result
            end

            it "should unset scope ephemeral variables after option evaluation" do
                @opval1.stubs(:evaluate_match).with { |*arg| arg[0] = "value" }.returns(true)
                @option1.stubs(:safeevaluate).returns(:result)
                @scope.expects(:unset_ephemeral_var)
                @casestmt.evaluate
            end

            it "should not leak ephemeral variables even if evaluation fails" do
                @opval1.stubs(:evaluate_match).with { |*arg| arg[0] = "value" }.returns(true)
                @option1.stubs(:safeevaluate).raises
                @scope.expects(:unset_ephemeral_var)
                lambda { @casestmt.evaluate }.should raise_error
            end
        end

    end
end
