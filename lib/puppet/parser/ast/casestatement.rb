require 'puppet/parser/ast/branch'

class Puppet::Parser::AST
    # The basic logical structure in Puppet.  Supports a list of
    # tests and statement arrays.
    class CaseStatement < AST::Branch
        attr_accessor :test, :options, :default

        associates_doc

        # Short-curcuit evaluation.  Return the value of the statements for
        # the first option that matches.
        def evaluate
            value = @test.safeevaluate
            sensitive = Puppet[:casesensitive]
            value = value.downcase if ! sensitive and value.respond_to?(:downcase)

            retvalue = nil
            found = false

            # Iterate across the options looking for a match.
            default = nil
            @options.each do |option|
                option.eachopt do |opt|
                    return option.safeevaluate if opt.evaluate_match(value, :file => file, :line => line, :sensitive => sensitive)
                end

                default = option if option.default?
            end

            # Unless we found something, look for the default.
            return default.safeevaluate if default

            Puppet.debug "No true answers and no default"
            return nil
        ensure
            scope.unset_ephemeral_var
        end

        def each
            [@test,@options].each { |child| yield child }
        end
    end
end
