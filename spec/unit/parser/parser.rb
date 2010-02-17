#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

describe Puppet::Parser do

    ast = Puppet::Parser::AST

    before :each do
        @resource_type_collection = Puppet::Parser::ResourceTypeCollection.new("development")
        @parser = Puppet::Parser::Parser.new :environment => "development", :resource_type_collection => @resource_type_collection
        @true_ast = Puppet::Parser::AST::Boolean.new :value => true
    end

    describe "when parsing files" do
        before do
            FileTest.stubs(:exist?).returns true
            File.stubs(:open)
            @parser.stubs(:check_and_add_to_watched_files).returns true
        end

        it "should treat files ending in 'rb' as ruby files" do
            @parser.expects(:parse_ruby_file)
            @parser.file = "/my/file.rb"
            @parser.parse
        end

        describe "in ruby" do
            it "should use the ruby interpreter to load the file" do
                @parser.file = "/my/file.rb"
                @parser.expects(:require).with "/my/file.rb"

                @parser.parse_ruby_file
            end
        end
    end

    describe "when parsing append operator" do

        it "should not raise syntax errors" do
            lambda { @parser.parse("$var += something") }.should_not raise_error
        end

        it "shouldraise syntax error on incomplete syntax " do
            lambda { @parser.parse("$var += ") }.should raise_error
        end

        it "should call ast::VarDef with append=true" do
            ast::VarDef.expects(:new).with { |h| h[:append] == true }
            @parser.parse("$var += 2")
        end

        it "should work with arrays too" do
            ast::VarDef.expects(:new).with { |h| h[:append] == true }
            @parser.parse("$var += ['test']")
        end

    end

    describe "when parsing 'if'" do
        it "not, it should create the correct ast objects" do
            ast::Not.expects(:new).with { |h| h[:value].is_a?(ast::Boolean) }
            @parser.parse("if ! true { $var = 1 }")
        end

        it "boolean operation, it should create the correct ast objects" do
            ast::BooleanOperator.expects(:new).with {
                |h| h[:rval].is_a?(ast::Boolean) and h[:lval].is_a?(ast::Boolean) and h[:operator]=="or"
            }
            @parser.parse("if true or true { $var = 1 }")

        end

        it "comparison operation, it should create the correct ast objects" do
             ast::ComparisonOperator.expects(:new).with {
                 |h| h[:lval].is_a?(ast::Name) and h[:rval].is_a?(ast::Name) and h[:operator]=="<"
             }
             @parser.parse("if 1 < 2 { $var = 1 }")

        end

    end

    describe "when parsing if complex expressions" do
         it "should create a correct ast tree" do
             aststub = stub_everything 'ast'
             ast::ComparisonOperator.expects(:new).with {
                 |h| h[:rval].is_a?(ast::Name) and h[:lval].is_a?(ast::Name) and h[:operator]==">"
             }.returns(aststub)
             ast::ComparisonOperator.expects(:new).with {
                 |h| h[:rval].is_a?(ast::Name) and h[:lval].is_a?(ast::Name) and h[:operator]=="=="
             }.returns(aststub)
             ast::BooleanOperator.expects(:new).with {
                 |h| h[:rval]==aststub and h[:lval]==aststub and h[:operator]=="and"
             }
             @parser.parse("if (1 > 2) and (1 == 2) { $var = 1 }")
         end

         it "should raise an error on incorrect expression" do
             lambda { @parser.parse("if (1 > 2 > ) or (1 == 2) { $var = 1 }") }.should raise_error
        end

    end

    describe "when parsing resource references" do

        it "should not raise syntax errors" do
            lambda { @parser.parse('exec { test: param => File["a"] }') }.should_not raise_error
        end

        it "should not raise syntax errors with multiple references" do
            lambda { @parser.parse('exec { test: param => File["a","b"] }') }.should_not raise_error
        end

        it "should create an ast::ResourceReference" do
            ast::Resource.stubs(:new)
            ast::ResourceReference.expects(:new).with { |arg|
                arg[:line]==1 and arg[:type]=="File" and arg[:title].is_a?(ast::ASTArray)
            }
            @parser.parse('exec { test: command => File["a","b"] }')
        end
    end

    describe "when parsing resource overrides" do

        it "should not raise syntax errors" do
            lambda { @parser.parse('Resource["title"] { param => value }') }.should_not raise_error
        end

        it "should not raise syntax errors with multiple overrides" do
            lambda { @parser.parse('Resource["title1","title2"] { param => value }') }.should_not raise_error
        end

        it "should create an ast::ResourceOverride" do
            ast::ResourceOverride.expects(:new).with { |arg|
                arg[:line]==1 and arg[:object].is_a?(ast::ResourceReference) and arg[:params].is_a?(ast::ResourceParam)
            }
            @parser.parse('Resource["title1","title2"] { param => value }')
        end

    end

    describe "when parsing if statements" do

        it "should not raise errors with empty if" do
            lambda { @parser.parse("if true { }") }.should_not raise_error
        end

        it "should not raise errors with empty else" do
            lambda { @parser.parse("if false { notice('if') } else { }") }.should_not raise_error
        end

        it "should not raise errors with empty if and else" do
            lambda { @parser.parse("if false { } else { }") }.should_not raise_error
        end

        it "should create a nop node for empty branch" do
            ast::Nop.expects(:new)
            @parser.parse("if true { }")
        end

        it "should create a nop node for empty else branch" do
            ast::Nop.expects(:new)
            @parser.parse("if true { notice('test') } else { }")
        end

    end

    describe "when parsing function calls" do

        it "should not raise errors with no arguments" do
            lambda { @parser.parse("tag()") }.should_not raise_error
        end

        it "should not raise errors with rvalue function with no args" do
            lambda { @parser.parse("$a = template()") }.should_not raise_error
        end

        it "should not raise errors with arguments" do
            lambda { @parser.parse("notice(1)") }.should_not raise_error
        end

        it "should not raise errors with multiple arguments" do
            lambda { @parser.parse("notice(1,2)") }.should_not raise_error
        end

        it "should not raise errors with multiple arguments and a trailing comma" do
            lambda { @parser.parse("notice(1,2,)") }.should_not raise_error
        end

    end

    describe "when parsing arrays with trailing comma" do

        it "should not raise errors with a trailing comma" do
            lambda { @parser.parse("$a = [1,2,]") }.should_not raise_error
        end
    end

    describe "when providing AST context" do
        before do
            @lexer = stub 'lexer', :line => 50, :file => "/foo/bar", :getcomment => "whev"
            @parser.stubs(:lexer).returns @lexer
        end

        it "should include the lexer's line" do
            @parser.ast_context[:line].should == 50
        end

        it "should include the lexer's file" do
            @parser.ast_context[:file].should == "/foo/bar"
        end

        it "should include the docs if directed to do so" do
            @parser.ast_context(true)[:doc].should == "whev"
        end

        it "should not include the docs when told not to" do
            @parser.ast_context(false)[:doc].should be_nil
        end

        it "should not include the docs by default" do
            @parser.ast_context()[:doc].should be_nil
        end
    end

    describe "when building ast nodes" do
        before do
            @lexer = stub 'lexer', :line => 50, :file => "/foo/bar", :getcomment => "whev"
            @parser.stubs(:lexer).returns @lexer
            @class = stub 'class', :use_docs => false
        end

        it "should return a new instance of the provided class created with the provided options" do
            @class.expects(:new).with { |opts| opts[:foo] == "bar" }
            @parser.ast(@class, :foo => "bar")
        end

        it "should merge the ast context into the provided options" do
            @class.expects(:new).with { |opts| opts[:file] == "/foo" }
            @parser.expects(:ast_context).returns :file => "/foo"
            @parser.ast(@class, :foo => "bar")
        end

        it "should prefer provided options over AST context" do
            @class.expects(:new).with { |opts| opts[:file] == "/bar" }
            @parser.expects(:ast_context).returns :file => "/foo"
            @parser.ast(@class, :file => "/bar")
        end

        it "should include docs when the AST class uses them" do
            @class.expects(:use_docs).returns true
            @class.stubs(:new)
            @parser.expects(:ast_context).with(true).returns({})
            @parser.ast(@class, :file => "/bar")
        end
    end

    describe "when creating a node" do
        before :each do
            @lexer = stub 'lexer'
            @lexer.stubs(:getcomment)
            @parser.stubs(:lexer).returns(@lexer)
            @node = stub_everything 'node'
            @parser.stubs(:ast_context).returns({})
            @parser.stubs(:node).returns(nil)

            @nodename = stub 'nodename', :is_a? => false, :value => "foo"
            @nodename.stubs(:is_a?).with(Puppet::Parser::AST::HostName).returns(true)
        end

        it "should return an array of nodes" do
            @parser.newnode(@nodename).should be_instance_of(Array)
        end
    end

    describe "when retrieving a specific node" do
        it "should delegate to the resource_type_collection node" do
            @resource_type_collection.expects(:node).with("node")

            @parser.node("node")
        end
    end

    describe "when retrieving a specific class" do
        it "should delegate to the loaded code" do
            @resource_type_collection.expects(:hostclass).with("class")

            @parser.hostclass("class")
        end
    end

    describe "when retrieving a specific definitions" do
        it "should delegate to the loaded code" do
            @resource_type_collection.expects(:definition).with("define")

            @parser.definition("define")
        end
    end

    describe "when determining the configuration version" do
        it "should default to the current time" do
            time = Time.now

            Time.stubs(:now).returns time
            @parser.version.should == time.to_i
        end

        it "should use the output of the config_version setting if one is provided" do
            Puppet.settings.stubs(:[]).with(:config_version).returns("/my/foo")

            Puppet::Util.expects(:execute).with(["/my/foo"]).returns "output\n"
            @parser.version.should == "output"
        end

        it "should raise a puppet parser error if executing config_version fails" do
            Puppet.settings.stubs(:[]).with(:config_version).returns("test")
            Puppet::Util.expects(:execute).raises(Puppet::ExecutionFailure.new("msg"))

            lambda { @parser.version }.should raise_error(Puppet::ParseError)
        end

    end

    describe "when looking up definitions" do
        it "should check for them by name" do
            @parser.stubs(:find_or_load).with("namespace","name",:definition).returns(:this_value)
            @parser.find_definition("namespace","name").should == :this_value
        end
    end

    describe "when looking up hostclasses" do
        it "should check for them by name" do
            @parser.stubs(:find_or_load).with("namespace","name",:hostclass).returns(:this_value)
            @parser.find_hostclass("namespace","name").should == :this_value
        end
    end

    describe "when looking up names" do
        before :each do
            @resource_type_collection = mock 'loaded code'
            @resource_type_collection.stubs(:find_my_type).with('loaded_namespace',  'loaded_name').returns(true)
            @resource_type_collection.stubs(:find_my_type).with('bogus_namespace',   'bogus_name' ).returns(false)
            @parser = Puppet::Parser::Parser.new :environment => "development",:resource_type_collection => @resource_type_collection
        end

        describe "that are already loaded" do
            it "should not try to load anything" do
                @parser.expects(:load).never
                @parser.find_or_load("loaded_namespace","loaded_name",:my_type)
            end
            it "should return true" do
                @parser.find_or_load("loaded_namespace","loaded_name",:my_type).should == true
            end
        end

        describe "that aren't already loaded" do
            it "should first attempt to load them with the all lowercase fully qualified name" do
                @resource_type_collection.stubs(:find_my_type).with("foo_namespace","foo_name").returns(false,true,true)
                @parser.expects(:load).with("foo_namespace::foo_name").returns(true).then.raises(Exception)
                @parser.find_or_load("Foo_namespace","Foo_name",:my_type).should == true
            end

            it "should next attempt to load them with the all lowercase namespace" do
                @resource_type_collection.stubs(:find_my_type).with("foo_namespace","foo_name").returns(false,false,true,true)
                @parser.expects(:load).with("foo_namespace::foo_name").returns(false).then.raises(Exception)
                @parser.expects(:load).with("foo_namespace"          ).returns(true ).then.raises(Exception)
                @parser.find_or_load("Foo_namespace","Foo_name",:my_type).should == true
            end

            it "should finally attempt to load them with the all lowercase unqualified name" do
                @resource_type_collection.stubs(:find_my_type).with("foo_namespace","foo_name").returns(false,false,false,true,true)
                @parser.expects(:load).with("foo_namespace::foo_name").returns(false).then.raises(Exception)
                @parser.expects(:load).with("foo_namespace"          ).returns(false).then.raises(Exception)
                @parser.expects(:load).with(               "foo_name").returns(true ).then.raises(Exception)
                @parser.find_or_load("Foo_namespace","Foo_name",:my_type).should == true
            end

            it "should return false if the name isn't found" do
                @parser.stubs(:load).returns(false)
                @parser.find_or_load("Bogus_namespace","Bogus_name",:my_type).should == false
            end

            it "should directly look for fully qualified classes" do
                @resource_type_collection.stubs(:find_hostclass).with("foo_namespace","::foo_name").returns(false, true)
                @parser.expects(:load).with("foo_name").returns true
                @parser.find_or_load("foo_namespace","::foo_name",:hostclass)
            end
        end
    end

    describe "when loading classnames" do
        before :each do
            @resource_type_collection = mock 'loaded code'
            @parser = Puppet::Parser::Parser.new :environment => "development",:resource_type_collection => @resource_type_collection
        end

        it "should just return false if the classname is empty" do
            @parser.expects(:import).never
            @parser.load("").should == false
        end

        it "should just return true if the item is loaded" do
            pending "Need to access internal state (@parser's @loaded) to force this"
            @parser.load("").should == false
        end
    end
end
