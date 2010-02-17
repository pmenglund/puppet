# The scope class, which handles storing and retrieving variables and types and
# such.

require 'puppet/parser/parser'
require 'puppet/parser/templatewrapper'
require 'puppet/transportable'
require 'strscan'

require 'puppet/resource/type_collection_helper'

class Puppet::Parser::Scope
    include Puppet::Resource::TypeCollectionHelper
    require 'puppet/parser/resource'

    AST = Puppet::Parser::AST

    Puppet::Util.logmethods(self)

    include Enumerable
    include Puppet::Util::Errors
    attr_accessor :level, :source, :resource
    attr_accessor :base, :keyword, :nodescope
    attr_accessor :top, :translated, :compiler
    attr_accessor :parent
    attr_reader :namespaces

    # A demeterific shortcut to the catalog.
    def catalog
        compiler.catalog
    end

    def environment
        compiler.environment
    end

    # Proxy accessors
    def host
        @compiler.node.name
    end

    # Is the value true?  This allows us to control the definition of truth
    # in one place.
    def self.true?(value)
        return !(value == false or value == "" or value == :undef)
    end

    # Is the value a number?, return the correct object or nil if not a number
    def self.number?(value)
        return nil unless value.is_a?(Fixnum) or value.is_a?(Bignum) or value.is_a?(Float) or value.is_a?(String)

        if value.is_a?(String)
            if value =~ /^-?\d+(:?\.\d+|(:?\.\d+)?e\d+)$/
                return value.to_f
            elsif value =~ /^0x[0-9a-f]+$/i
                return value.to_i(16)
            elsif value =~ /^0[0-7]+$/
                return value.to_i(8)
            elsif value =~ /^-?\d+$/
                return value.to_i
            else
                return nil
            end
        end
        # it is one of Fixnum,Bignum or Float
        return value
    end

    # Add to our list of namespaces.
    def add_namespace(ns)
        return false if @namespaces.include?(ns)
        if @namespaces == [""]
            @namespaces = [ns]
        else
            @namespaces << ns
        end
    end

    # Are we the top scope?
    def topscope?
        @level == 1
    end

    def find_hostclass(name)
        known_resource_types.find_hostclass(namespaces, name)
    end

    def find_definition(name)
        known_resource_types.find_definition(namespaces, name)
    end

    def findresource(string, name = nil)
        compiler.findresource(string, name)
    end

    # Initialize our new scope.  Defaults to having no parent.
    def initialize(hash = {})
        if hash.include?(:namespace)
            if n = hash[:namespace]
                @namespaces = [n]
            end
            hash.delete(:namespace)
        else
            @namespaces = [""]
        end
        hash.each { |name, val|
            method = name.to_s + "="
            if self.respond_to? method
                self.send(method, val)
            else
                raise Puppet::DevError, "Invalid scope argument #{name}"
            end
        }

        @tags = []

        # The symbol table for this scope.  This is where we store variables.
        @symtable = {}

        @futures = {}

        # the ephemeral symbol tables
        # those should not persist long, and are used for the moment only
        # for $0..$xy capture variables of regexes
        @ephemeral = {}

        # All of the defaults set for types.  It's a hash of hashes,
        # with the first key being the type, then the second key being
        # the parameter.
        @defaults = Hash.new { |dhash,type|
            dhash[type] = {}
        }

        # The table for storing class singletons.  This will only actually
        # be used by top scopes and node scopes.
        @class_scopes = {}
    end

    # Store the fact that we've evaluated a class, and store a reference to
    # the scope in which it was evaluated, so that we can look it up later.
    def class_set(name, scope)
        return parent.class_set(name,scope) if parent
        if existing = @class_scopes[name]
            if existing.nodescope? != scope.nodescope?
                raise Puppet::ParseError, "Cannot have classes, nodes, or definitions with the same name"
            else
                raise Puppet::DevError, "Somehow evaluated #{existing.nodescope? ? "node" : "class"} #{name} twice"
            end
        end
        @class_scopes[name] = scope
    end

    # Return the scope associated with a class.  This is just here so
    # that subclasses can set their parent scopes to be the scope of
    # their parent class, and it's also used when looking up qualified
    # variables.
    def class_scope(klass)
        # They might pass in either the class or class name
        k = klass.respond_to?(:name) ? klass.name : klass
        @class_scopes[k] || (parent && parent.class_scope(k))
    end

    class Future
        define_accessors :source,:resolved?,:scope,:name
        def initialize(scope,name)
            @scope,@name = scope,name
        end
        def value
            if    resolved?    then @value
            elsif source       then resolved!; @value = source.evaluate
            elsif scope.parent then scope.parent.future_for(name).value
            else                    :undef
            end
        end
    end

    class No_future < Future
        def initialize(scope,name,message)
            super(scope,name)
            warning message
        end
        def value
            :undefined
        end
    end

    def future_for(name)
        if name =~ /(.*)::([^:]+)/
            klassname,varname = $1,$2
            if not (klass = find_hostclass(klassname))
                No_future.new(self,name,"Could not look up qualified variable '#{name}'; class #{klassname} could not be found")
            elsif not (kscope = compiler.class_scope(klass))
                No_future.new(self,name,"Could not look up qualified variable '#{name}'; class #{klassname} has not been evaluated")
            else
                kscope.future_for(varname)
            end
        else
            @futures[name] ||= Future.new(self,name)
        end
    end

    # Collect all of the defaults set at any higher scopes.
    # This is a different type of lookup because it's additive --
    # it collects all of the defaults, with defaults in closer scopes
    # overriding those in later scopes.
    def lookupdefaults(type)
        values = {}

        # first collect the values from the parents
        unless parent.nil?
            parent.lookupdefaults(type).each { |var,value|
                values[var] = value
            }
        end

        # then override them with any current values
        # this should probably be done differently
        if @defaults.include?(type)
            @defaults[type].each { |var,value|
                values[var] = value
            }
        end

        #Puppet.debug "Got defaults for %s: %s" %
        #    [type,values.inspect]
        return values
    end

    # Look up a defined type.
    def lookuptype(name)
        find_definition(name) || find_hostclass(name)
    end

    # Look up a variable.  The simplest value search we do.  Default to returning
    # an empty string for missing values, but support returning a constant.
    def lookupvar(name, usestring = true)
        # If the variable is qualified, then find the specified scope and look the variable up there instead.
        if name =~ /::/
            parts = name.split(/::/)
            shortname = parts.pop
            klassname = parts.join("::")
            klass = find_hostclass(klassname)
            unless klass
                warning "Could not look up qualified variable '#{name}'; class #{klassname} could not be found"
                return usestring ? "" : :undefined
            end
            unless kscope = compiler.class_scope(klass)
                warning "Could not look up qualified variable '#{name}'; class #{klassname} has not been evaluated"
                return usestring ? "" : :undefined
            end
            return kscope.lookupvar(shortname, usestring)
        end
        table = ephemeral?(name) ? @ephemeral : @symtable
        # We can't use "if table[name]" here because the value might be false
        if table.include?(name)
            (usestring and table[name] == :undef) ? "" : table[name]
        elsif parent
            parent.lookupvar(name, usestring)
        else
            usestring ? "" : :undefined
        end
    end

    # Return a hash containing our variables and their values, optionally (and
    # by default) including the values defined in our parent.  Local values
    # shadow parent values.
    def to_hash(recursive = true)
        target = parent.to_hash(recursive) if recursive and parent
        target ||= Hash.new
        @symtable.keys.each { |name|
            value = @symtable[name]
            if value == :undef
                target.delete(name)
            else
                target[name] = value
            end
        }
        return target
    end

    def namespaces
        @namespaces.dup
    end

    # Create a new scope and set these options.
    def newscope(options = {})
        compiler.newscope(self, options)
    end

    # Is this class for a node?  This is used to make sure that
    # nodes and classes with the same name conflict (#620), which
    # is required because of how often the names are used throughout
    # the system, including on the client.
    def nodescope?
        self.nodescope
    end

    # Return the list of scopes up to the top scope, ordered with our own first.
    # This is used for looking up variables and defaults.
    def scope_path
        if parent
            [self, parent.scope_path].flatten.compact
        else
            [self]
        end
    end

    # Set defaults for a type.  The typename should already be downcased,
    # so that the syntax is isolated.  We don't do any kind of type-checking
    # here; instead we let the resource do it when the defaults are used.
    def setdefaults(type, params)
        table = @defaults[type]

        # if we got a single param, it'll be in its own array
        params = [params] unless params.is_a?(Array)

        params.each { |param|
            #Puppet.debug "Default for %s is %s => %s" %
            #    [type,ary[0].inspect,ary[1].inspect]
            if table.include?(param.name)
                raise Puppet::ParseError.new("Default already defined for #{type} { #{param.name} }; cannot redefine", param.line, param.file)
            end
            table[param.name] = param
        }
    end

    # Set a variable in the current scope.  This will override settings
    # in scopes above, but will not allow variables in the current scope
    # to be reassigned.
    def setvar(name,value, options = {})
        table = options[:ephemeral] ? @ephemeral : @symtable
        #Puppet.debug "Setting %s to '%s' at level %s mode append %s" %
        #    [name.inspect,value,self.level, append]
        if table.include?(name)
            unless options[:append]
                error = Puppet::ParseError.new("Cannot reassign variable #{name}")
            else
                error = Puppet::ParseError.new("Cannot append, variable #{name} is defined in this scope")
            end
            error.file = options[:file] if options[:file]
            error.line = options[:line] if options[:line]
            raise error
        end

        unless options[:append]
            table[name] = value
        else # append case
            # lookup the value in the scope if it exists and insert the var
            table[name] = lookupvar(name)
            # concatenate if string, append if array, nothing for other types
            case value
            when Array
                table[name] += value
            when Hash
                raise ArgumentError, "Trying to append to a hash with something which is not a hash is unsupported" unless value.is_a?(Hash)
                table[name].merge!(value)
            else
                table[name] << value
            end
        end
    end

    # Return an interpolated string.
    def strinterp(string, file = nil, line = nil)
        # Most strings won't have variables in them.
        ss = StringScanner.new(string)
        out = ""
        while not ss.eos?
            if ss.scan(/^\$\{((\w*::)*\w+|[0-9]+)\}|^\$([0-9])|^\$((\w*::)*\w+)/)
                # If it matches the backslash, then just retun the dollar sign.
                if ss.matched == '\\$'
                    out << '$'
                else # look the variable up
                    # make sure $0-$9 are lookupable only if ephemeral
                    var = ss[1] || ss[3] || ss[4]
                    if var and var =~ /^[0-9]+$/ and not ephemeral?(var)
                        next
                    end
                    #out << lookupvar(var).to_s || ""
                    out << future_for(var).value.to_s
                end
            elsif ss.scan(/^\\(.)/)
                # Puppet.debug("Got escape: pos:%d; m:%s" % [ss.pos, ss.matched])
                case ss[1]
                when 'n'
                    out << "\n"
                when 't'
                    out << "\t"
                when 's'
                    out << " "
                when '\\'
                    out << '\\'
                when '$'
                    out << '$'
                else
                    str = "Unrecognised escape sequence '#{ss.matched}'"
                    str += " in file #{file}" if file
                    str += " at line #{line}" if line
                    Puppet.warning str
                    out << ss.matched
                end
            elsif ss.scan(/^\$/)
                out << '$'
            elsif ss.scan(/^\\\n/) # an escaped carriage return
                next
            else
                tmp = ss.scan(/[^\\$]+/)
                # Puppet.debug("Got other: pos:%d; m:%s" % [ss.pos, tmp])
                unless tmp
                    error = Puppet::ParseError.new("Could not parse string #{string.inspect}")
                    {:file= => file, :line= => line}.each do |m,v|
                        error.send(m, v) if v
                    end
                    raise error
                end
                out << tmp
            end
        end

        return out
    end

    # Return the tags associated with this scope.  It's basically
    # just our parents' tags, plus our type.  We don't cache this value
    # because our parent tags might change between calls.
    def tags
        resource.tags
    end

    # Used mainly for logging
    def to_s
        "Scope(#{@resource})"
    end

    # Undefine a variable; only used for testing.
    def unsetvar(var)
        table = ephemeral?(var) ? @ephemeral : @symtable
        table.delete(var) if table.include?(var)
    end

    def unset_ephemeral_var
        @ephemeral = {}
    end

    def ephemeral?(name)
        @ephemeral.include?(name)
    end

    def ephemeral_from(match, file = nil, line = nil)
        raise(ArgumentError,"Invalid regex match data") unless match.is_a?(MatchData)

        setvar("0", match[0], :file => file, :line => line, :ephemeral => true)
        match.captures.each_with_index do |m,i|
            setvar("#{i+1}", m, :file => file, :line => line, :ephemeral => true)
        end
    end
end
