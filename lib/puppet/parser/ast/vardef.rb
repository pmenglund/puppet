require 'puppet/parser/ast/branch'

class Puppet::Parser::AST
    # Define a variable.  Stores the value in the current scope.
    class VarDef < AST::Branch

        associates_doc

        attr_accessor :name, :value, :append

        def initialize(args)
            super
            n = name.safeevaluate
            @future = scope.future_for(n)
            @future.source = self
        end

        # Look up our name and value, and store them appropriately.  The
        # lexer strips off the syntax stuff like '$'.
        def evaluate(scope)
            @value.safeevaluate
        end

        def each
            [@name,@value].each { |child| yield child }
        end
    end

end
