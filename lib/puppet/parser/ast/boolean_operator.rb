require 'puppet'
require 'puppet/parser/ast/branch'

class Puppet::Parser::AST
    class BooleanOperator < AST::Branch

        attr_accessor :operator, :lval, :rval

        # Iterate across all of our children.
        def each
            [@lval,@rval,@operator].each { |child| yield child }
        end

        # Returns a boolean which is the result of the lazy boolean
        # operation of lval and rval operands
        def evaluate
            s = Puppet::Parser::Scope
            case @operator
            when "and"; s.true?(@lval.safeevaluate) and s.true?(@rval.safeevaluate)
            when "or";  s.true?(@lval.safeevaluate) or  s.true?(@rval.safeevaluate)
            end
        end

        def initialize(hash)
            super

            raise ArgumentError, "Invalid boolean operator #{@operator}" unless %w{and or}.include?(@operator)
        end
    end
end
