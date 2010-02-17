require 'puppet/parser/ast/branch'

class Puppet::Parser::AST
    # The code associated with a class.  This is different from components
    # in that each class is a singleton -- only one will exist for a given
    # node.
    class Tag < AST::Branch
        @name = :class
        attr_accessor :type

        def evaluate(scope)
            [@type.safeevaluate].flatten.each do |type|
                # Now set our class.  We don't have to worry about checking
                # whether we've been evaluated because we're not evaluating
                # any code.
                scope.setclass(self.object_id, type)
            end
        end
    end
end
