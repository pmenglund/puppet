#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../lib/puppettest'

require 'mocha'
require 'puppet'
require 'puppet/parser/parser'
require 'puppettest'
require 'puppettest/support/utils'

class TestParser < Test::Unit::TestCase
    include PuppetTest
    include PuppetTest::ParserTesting
    include PuppetTest::Support::Utils
    def setup
        super
        Puppet[:parseonly] = true
        #@lexer = Puppet::Parser::Lexer.new()
    end

    def test_each_file
        textfiles { |file|
            parser = mkparser
            Puppet.debug("parsing %s" % file) if __FILE__ == $0
            assert_nothing_raised() {
                parser.file = file
                parser.parse
            }
        }
    end

    def test_failers
        failers { |file|
            parser = mkparser
            Puppet.debug("parsing failer %s" % file) if __FILE__ == $0
            assert_raise(Puppet::ParseError, "Did not fail while parsing %s" % file) {
                parser.file = file
                ast = parser.parse
                config = mkcompiler(parser)
                config.compile
                #ast.hostclass("").evaluate config.topscope
            }
        }
    end

    def test_arrayrvalues
        parser = mkparser
        ret = nil
        file = tempfile()
        assert_nothing_raised {
            parser.string = "file { \"#{file}\": mode => [755, 640] }"
        }

        assert_nothing_raised {
            ret = parser.parse
        }
    end

    def test_arrayrvalueswithtrailingcomma
        parser = mkparser
        ret = nil
        file = tempfile()
        assert_nothing_raised {
            parser.string = "file { \"#{file}\": mode => [755, 640,] }"
        }

        assert_nothing_raised {
            ret = parser.parse
        }
    end

    def mkmanifest(file)
        name = File.join(tmpdir, "file%s" % rand(100))
        @@tmpfiles << name

        File.open(file, "w") { |f|
            f.puts "file { \"%s\": ensure => file, mode => 755 }\n" %
               name
        }
    end

    def test_importglobbing
        basedir = File.join(tmpdir(), "importesting")
        @@tmpfiles << basedir
        Dir.mkdir(basedir)

        subdir = "subdir"
        Dir.mkdir(File.join(basedir, subdir))
        manifest = File.join(basedir, "manifest")
        File.open(manifest, "w") { |f|
            f.puts "import \"%s/*\"" % subdir
        }

        4.times { |i|
            path = File.join(basedir, subdir, "subfile%s" % i)
            mkmanifest(path)
        }

        assert_nothing_raised("Could not parse multiple files") {
            parser = mkparser
            parser.file = manifest
            parser.parse
        }
    end

    def test_nonexistent_import
        basedir = File.join(tmpdir(), "importesting")
        @@tmpfiles << basedir
        Dir.mkdir(basedir)
        manifest = File.join(basedir, "manifest")
        File.open(manifest, "w") do |f|
            f.puts "import \" no such file \""
        end
        assert_raise(Puppet::ParseError) {
            parser = mkparser
            parser.file = manifest
            parser.parse
        }
    end

    def test_trailingcomma
        path = tempfile()
        str = %{file { "#{path}": ensure => file, }
        }

        parser = mkparser
        parser.string = str

        assert_nothing_raised("Could not parse trailing comma") {
            parser.parse
        }
    end

    def test_importedclasses
        imported = tempfile()
        importer = tempfile()

        made = tempfile()

        File.open(imported, "w") do |f|
            f.puts %{class foo { file { "#{made}": ensure => file }}}
        end

        File.open(importer, "w") do |f|
            f.puts %{import "#{imported}"\ninclude foo}
        end

        parser = mkparser
        parser.file = importer

        # Make sure it parses fine
        assert_nothing_raised {
            parser.parse
        }

        # Now make sure it actually does the work
        assert_creates(importer, made)
    end

    # Make sure fully qualified and unqualified files can be imported
    def test_fqfilesandlocalfiles
        dir = tempfile()
        Dir.mkdir(dir)
        importer = File.join(dir, "site.pp")
        fullfile = File.join(dir, "full.pp")
        localfile = File.join(dir, "local.pp")

        files = []

        File.open(importer, "w") do |f|
            f.puts %{import "#{fullfile}"\ninclude full\nimport "local.pp"\ninclude local}
        end

        fullmaker = tempfile()
        files << fullmaker

        File.open(fullfile, "w") do |f|
            f.puts %{class full { file { "#{fullmaker}": ensure => file }}}
        end

        localmaker = tempfile()
        files << localmaker

        File.open(localfile, "w") do |f|
            f.puts %{class local { file { "#{localmaker}": ensure => file }}}
        end

        parser = mkparser
        parser.file = importer

        # Make sure it parses
        assert_nothing_raised {
            parser.parse
        }

        # Now make sure it actually does the work
        assert_creates(importer, *files)
    end

    # Make sure the parser adds '.pp' when necessary
    def test_addingpp
        dir = tempfile()
        Dir.mkdir(dir)
        importer = File.join(dir, "site.pp")
        localfile = File.join(dir, "local.pp")

        files = []

        File.open(importer, "w") do |f|
            f.puts %{import "local"\ninclude local}
        end

        file = tempfile()
        files << file

        File.open(localfile, "w") do |f|
            f.puts %{class local { file { "#{file}": ensure => file }}}
        end

        parser = mkparser
        parser.file = importer

        assert_nothing_raised {
            parser.parse
        }
    end

    # Make sure that file importing changes file relative names.
    def test_changingrelativenames
        dir = tempfile()
        Dir.mkdir(dir)
        Dir.mkdir(File.join(dir, "subdir"))
        top = File.join(dir, "site.pp")
        subone = File.join(dir, "subdir/subone")
        subtwo = File.join(dir, "subdir/subtwo")

        files = []
        file = tempfile()
        files << file

        File.open(subone + ".pp", "w") do |f|
            f.puts %{class one { file { "#{file}": ensure => file }}}
        end

        otherfile = tempfile()
        files << otherfile
        File.open(subtwo + ".pp", "w") do |f|
            f.puts %{import "subone"\n class two inherits one {
                file { "#{otherfile}": ensure => file }
            }}
        end

        File.open(top, "w") do |f|
            f.puts %{import "subdir/subtwo"}
        end

        parser = mkparser
        parser.file = top

        assert_nothing_raised {
            parser.parse
        }
    end

    # Defaults are purely syntactical, so it doesn't make sense to be able to
    # collect them.
    def test_uncollectabledefaults
        string = "@Port { protocols => tcp }"

        assert_raise(Puppet::ParseError) {
            mkparser.parse(string)
        }
    end

    # Verify that we can parse collections
    def test_collecting
        text = "Port <| |>"
        parser = mkparser
        parser.string = text

        ret = nil
        assert_nothing_raised {
            ret = parser.parse
        }

        ret.hostclass("").code.each do |obj|
            assert_instance_of(AST::Collection, obj)
        end
    end

    def test_emptyfile
        file = tempfile()
        File.open(file, "w") do |f|
            f.puts %{}
        end
        parser = mkparser
        parser.file = file
        assert_nothing_raised {
            parser.parse
        }
    end

    def test_multiple_nodes_named
        file = tempfile()
        other = tempfile()

        File.open(file, "w") do |f|
            f.puts %{
node nodeA, nodeB {
    file { "#{other}": ensure => file }

}
}
        end

        parser = mkparser
        parser.file = file
        ast = nil
        assert_nothing_raised {
            ast = parser.parse
        }
    end

    def test_emptyarrays
        str = %{$var = []\n}

        parser = mkparser
        parser.string = str

        # Make sure it parses fine
        assert_nothing_raised {
            parser.parse
        }
    end

    # Make sure function names aren't reserved words.
    def test_functionnamecollision
        str = %{tag yayness
tag(rahness)

file { "/tmp/yayness":
    tag => "rahness",
    ensure => exists
}
}
        parser = mkparser
        parser.string = str

        # Make sure it parses fine
        assert_nothing_raised {
            parser.parse
        }
    end

    def test_metaparams_in_definition_prototypes
        parser = mkparser


        assert_raise(Puppet::ParseError) {
            parser.parse %{define mydef($schedule) {}}
        }

        assert_nothing_raised {
            parser.parse %{define adef($schedule = false) {}}
            parser.parse %{define mydef($schedule = daily) {}}
        }
    end

    def test_parsingif
        parser = mkparser
        exec = proc do |val|
            %{exec { "/bin/echo #{val}": logoutput => true }}
        end
        str1 = %{if true { #{exec.call("true")} }}
        ret = nil
        assert_nothing_raised {
            ret = parser.parse(str1).hostclass("").code[0]
        }
        assert_instance_of(Puppet::Parser::AST::IfStatement, ret)
        parser = mkparser
        str2 = %{if true { #{exec.call("true")} } else { #{exec.call("false")} }}
        assert_nothing_raised {
            ret = parser.parse(str2).hostclass("").code[0]
        }
        assert_instance_of(Puppet::Parser::AST::IfStatement, ret)
        assert_instance_of(Puppet::Parser::AST::Else, ret.else)
    end

    def test_hostclass
        parser = mkparser

        assert_nothing_raised {
            parser.parse %{class myclass { class other {} }}
        }
        assert(parser.hostclass("myclass"), "Could not find myclass")
        assert(parser.hostclass("myclass::other"), "Could not find myclass::other")

        assert_nothing_raised {
            parser.parse "class base {}
            class container {
                class deep::sub inherits base {}
            }"
        }
        sub = parser.hostclass("container::deep::sub")
        assert(sub, "Could not find sub")

        # Now try it with a parent class being a fq class
        assert_nothing_raised {
            parser.parse "class container::one inherits container::deep::sub {}"
        }
        sub = parser.hostclass("container::one")
        assert(sub, "Could not find one")
        assert_equal("container::deep::sub", sub.parentclass)

        # Finally, try including a qualified class
        assert_nothing_raised("Could not include fully qualified class") {
            parser.parse "include container::deep::sub"
        }
    end

    def test_topnamespace
        parser = mkparser

        # Make sure we put the top-level code into a class called "" in
        # the "" namespace
        assert_nothing_raised do
            out = parser.parse ""

            assert_instance_of(Puppet::Parser::ResourceTypeCollection, out)
            assert_nil(parser.hostclass(""), "Got a 'main' class when we had no code")
        end

        # Now try something a touch more complicated
        parser.initvars
        assert_nothing_raised do
            out = parser.parse "Exec { path => '/usr/bin:/usr/sbin' }"
            assert_instance_of(Puppet::Parser::ResourceTypeCollection, out)
            assert_equal("", parser.hostclass("").classname)
            assert_equal("", parser.hostclass("").namespace)
        end
    end

    # Make sure virtual and exported resources work appropriately.
    def test_virtualresources
        tests = [:virtual]
        if Puppet.features.rails?
            catalog_cache_class = Puppet::Resource::Catalog.indirection.cache_class
            facts_cache_class = Puppet::Node::Facts.indirection.cache_class
            node_cache_class = Puppet::Node.indirection.cache_class
            Puppet[:storeconfigs] = true
            tests << :exported
        end

        tests.each do |form|
            parser = mkparser

            if form == :virtual
                at = "@"
            else
                at = "@@"
            end

            check = proc do |res, msg|
                if res.is_a?(Puppet::Parser::Resource)
                    txt = res.ref
                else
                    txt = res.class
                end
                # Real resources get marked virtual when exported
                if form == :virtual or res.is_a?(Puppet::Parser::Resource)
                    assert(res.virtual, "#{msg} #{at}#{txt} is not virtual")
                end
                if form == :virtual
                    assert(! res.exported, "#{msg} #{at}#{txt} is exported")
                else
                    assert(res.exported, "#{msg} #{at}#{txt} is not exported")
                end
            end

            ret = nil
            assert_nothing_raised do
                ret = parser.parse("#{at}file { '/tmp/testing': owner => root }")
            end

            assert_instance_of(AST::ASTArray, ret.hostclass("").code)
            resdef = ret.hostclass("").code[0]
            assert_instance_of(AST::Resource, resdef)
            assert_equal("/tmp/testing", resdef.title.value)
            # We always get an astarray back, so...
            check.call(resdef, "simple resource")

            # Now let's try it with multiple resources in the same spec
            assert_nothing_raised do
                ret = parser.parse("#{at}file { ['/tmp/1', '/tmp/2']: owner => root }")
            end

            ret.hostclass("").each do |res|
                assert_instance_of(AST::Resource, res)
                check.call(res, "multiresource")
            end
        end
        if Puppet.features.rails?
            Puppet[:storeconfigs] = false
            Puppet::Resource::Catalog.cache_class =  catalog_cache_class
            Puppet::Node::Facts.cache_class = facts_cache_class
            Puppet::Node.cache_class = node_cache_class
        end
    end

    def test_collections
        tests = [:virtual]
        if Puppet.features.rails?
            catalog_cache_class = Puppet::Resource::Catalog.indirection.cache_class
            facts_cache_class = Puppet::Node::Facts.indirection.cache_class
            node_cache_class = Puppet::Node.indirection.cache_class
            Puppet[:storeconfigs] = true
            tests << :exported
        end

        tests.each do |form|
            parser = mkparser

            if form == :virtual
                arrow = "<||>"
            else
                arrow = "<<||>>"
            end

            ret = nil
            assert_nothing_raised do
                ret = parser.parse("File #{arrow}")
            end

            coll = ret.hostclass("").code[0]
            assert_instance_of(AST::Collection, coll)
            assert_equal(form, coll.form)
        end
        if Puppet.features.rails?
            Puppet[:storeconfigs] = false
            Puppet::Resource::Catalog.cache_class =  catalog_cache_class
            Puppet::Node::Facts.cache_class = facts_cache_class
            Puppet::Node.cache_class = node_cache_class
        end
    end

    def test_collectionexpressions
        %w{== !=}.each do |oper|
            str = "File <| title #{oper} '/tmp/testing' |>"

            parser = mkparser

            res = nil
            assert_nothing_raised do
                res = parser.parse(str).hostclass("").code[0]
            end

            assert_instance_of(AST::Collection, res)

            query = res.query
            assert_instance_of(AST::CollExpr, query)

            assert_equal(:virtual, query.form)
            assert_equal("title", query.test1.value)
            assert_equal("/tmp/testing", query.test2.value)
            assert_equal(oper, query.oper)
        end
    end

    def test_collectionstatements
        %w{and or}.each do |joiner|
            str = "File <| title == '/tmp/testing' #{joiner} owner == root |>"

            parser = mkparser

            res = nil
            assert_nothing_raised do
                res = parser.parse(str).hostclass("").code[0]
            end

            assert_instance_of(AST::Collection, res)

            query = res.query
            assert_instance_of(AST::CollExpr, query)

            assert_equal(joiner, query.oper)
            assert_instance_of(AST::CollExpr, query.test1)
            assert_instance_of(AST::CollExpr, query.test2)
        end
    end

    def test_collectionstatements_with_parens
        [
            "(title == '/tmp/testing' and owner == root) or owner == wheel",
            "(title == '/tmp/testing')"
        ].each do |test|
            str = "File <| #{test} |>"
            parser = mkparser

            res = nil
            assert_nothing_raised("Could not parse '#{test}'") do
                res = parser.parse(str).hostclass("").code[0]
            end

            assert_instance_of(AST::Collection, res)

            query = res.query
            assert_instance_of(AST::CollExpr, query)

            #assert_equal(joiner, query.oper)
            #assert_instance_of(AST::CollExpr, query.test1)
            #assert_instance_of(AST::CollExpr, query.test2)
        end
    end

    # We've had problems with files other than site.pp importing into main.
    def test_importing_into_main
        top = tempfile()
        other = tempfile()
        File.open(top, "w") do |f|
            f.puts "import '#{other}'"
        end

        file = tempfile()
        File.open(other, "w") do |f|
            f.puts "file { '#{file}': ensure => present }"
        end

        Puppet[:manifest] = top
        interp = Puppet::Parser::Interpreter.new

        code = nil
        assert_nothing_raised do
            code = interp.compile(mknode).extract.flatten
        end
        assert(code.length == 1, "Did not get the file")
        assert_instance_of(Puppet::TransObject, code[0])
    end

    def test_fully_qualified_definitions
        parser = mkparser

        assert_nothing_raised("Could not parse fully-qualified definition") {
            parser.parse %{define one::two { }}
        }
        assert(parser.definition("one::two"), "Could not find one::two with no namespace")
        
        # Now try using the definition
        assert_nothing_raised("Could not parse fully-qualified definition usage") {
            parser.parse %{one::two { yayness: }}
        }
    end

    # #524
    def test_functions_with_no_arguments
        parser = mkparser
        assert_nothing_raised("Could not parse statement function with no args") {
            parser.parse %{tag()}
        }
        assert_nothing_raised("Could not parse rvalue function with no args") {
            parser.parse %{$testing = template()}
        }
    end

    # #774
    def test_fully_qualified_collection_statement
        parser = mkparser
        assert_nothing_raised("Could not parse fully qualified collection statement") {
            parser.parse %{Foo::Bar <||>}
        }
    end

    def test_module_import
        basedir = File.join(tmpdir(), "module-import")
        @@tmpfiles << basedir
        Dir.mkdir(basedir)
        modfiles = [ "init.pp", "mani1.pp", "mani2.pp",
                     "sub/smani1.pp", "sub/smani2.pp" ]

        modpath = File.join(basedir, "modules")
        Puppet[:modulepath] = modpath

        modname = "amod"
        manipath = File::join(modpath, modname, Puppet::Module::MANIFESTS)
        FileUtils::mkdir_p(File::join(manipath, "sub"))
        targets = []
        modfiles.each do |fname|
            target = File::join(basedir, File::basename(fname, '.pp'))
            targets << target
            txt = %[ file { '#{target}': content => "#{fname}" } ]
            if fname == "init.pp"
                txt = %[import 'mani1' \nimport '#{modname}/mani2'\nimport '#{modname}/sub/*.pp'\n ] + txt
            end
            File::open(File::join(manipath, fname), "w") do |f|
                f.puts txt
            end
        end

        manifest_texts = [ "import '#{modname}'",
                           "import '#{modname}/init'",
                           "import '#{modname}/init.pp'" ]

        manifest = File.join(modpath, "manifest.pp")
        manifest_texts.each do |txt|
            File.open(manifest, "w") { |f| f.puts txt }

            assert_nothing_raised {
                parser = mkparser
                parser.file = manifest
                parser.parse
            }
            assert_creates(manifest, *targets)
        end
    end

    # #544
    def test_ignoreimports
        parser = mkparser

        assert(! Puppet[:ignoreimport], ":ignoreimport defaulted to true")
        assert_raise(Puppet::ParseError, "Did not fail on missing import") do
            parser.parse("import 'nosuchfile'")
        end
        assert_nothing_raised("could not set :ignoreimport") do
            Puppet[:ignoreimport] = true
        end
        assert_nothing_raised("Parser did not follow :ignoreimports") do
            parser.parse("import 'nosuchfile'")
        end
    end

    def test_multiple_imports_on_one_line
        one = tempfile
        two = tempfile
        base = tempfile
        File.open(one, "w") { |f| f.puts "$var = value" }
        File.open(two, "w") { |f| f.puts "$var = value" }
        File.open(base, "w") { |f| f.puts "import '#{one}', '#{two}'" }

        parser = mkparser
        parser.file = base

        # Importing is logged at debug time.
        Puppet::Util::Log.level = :debug
        assert_nothing_raised("Parser could not import multiple files at once") do
            parser.parse
        end

        [one, two].each do |file|
            assert(@logs.detect { |l| l.message =~ /importing '#{file}'/},
                "did not import %s" % file)
        end
    end

    def test_cannot_assign_qualified_variables
        parser = mkparser
        assert_raise(Puppet::ParseError, "successfully assigned a qualified variable") do
            parser.parse("$one::two = yay")
        end
    end

    # #588
    def test_globbing_with_directories
        dir = tempfile
        Dir.mkdir(dir)
        subdir = File.join(dir, "subdir")
        Dir.mkdir(subdir)
        file = File.join(dir, "file.pp")
        maker = tempfile
        File.open(file, "w") { |f| f.puts "file { '#{maker}': ensure => file }" }

        parser = mkparser
        assert_nothing_raised("Globbing failed when it matched a directory") do
            parser.import("%s/*" % dir)
        end
    end

    # #629 - undef keyword
    def test_undef
        parser = mkparser
        result = nil
        assert_nothing_raised("Could not parse assignment to undef") {
            result = parser.parse %{$variable = undef}
        }

        main = result.hostclass("").code
        children = main.children
        assert_instance_of(AST::VarDef, main.children[0])
        assert_instance_of(AST::Undef, main.children[0].value)
    end

    # Prompted by #729 -- parsing should not modify the interpreter.
    def test_parse
        parser = mkparser

        str = "file { '/tmp/yay': ensure => file }\nclass yay {}\nnode foo {}\ndefine bar {}\n"
        result = nil
        assert_nothing_raised("Could not parse") do
            result = parser.parse(str)
        end
        assert_instance_of(Puppet::Parser::ResourceTypeCollection, result, "Did not get a ASTSet back from parsing")

        assert_instance_of(AST::HostClass, result.hostclass("yay"), "Did not create 'yay' class")
        assert_instance_of(AST::HostClass, result.hostclass(""), "Did not create main class")
        assert_instance_of(AST::Definition, result.definition("bar"), "Did not create 'bar' definition")
        assert_instance_of(AST::Node, result.node("foo"), "Did not create 'foo' node")
    end

    # Make sure our node gets added to the node table.
    def test_newnode
        parser = mkparser

        # First just try calling it directly
        assert_nothing_raised {
            parser.newnode("mynode", :code => :yay)
        }

        assert_equal(:yay, parser.node("mynode").code)

        # Now make sure that trying to redefine it throws an error.
        assert_raise(Puppet::ParseError) {
            parser.newnode("mynode", {})
        }

        # Now try one with no code
        assert_nothing_raised {
            parser.newnode("simplenode", :parent => :foo)
        }

        # Now define the parent node
        parser.newnode(:foo)

        # And make sure we get things back correctly
        assert_equal(:foo, parser.node("simplenode").parentclass)
        assert_nil(parser.node("simplenode").code)

        # Now make sure that trying to redefine it throws an error.
        assert_raise(Puppet::ParseError) {
            parser.newnode("mynode", {})
        }

        # Test multiple names
        names = ["one", "two", "three"]
        assert_nothing_raised {
            parser.newnode(names, {:code => :yay, :parent => :foo})
        }

        names.each do |name|
            assert_equal(:yay, parser.node(name).code)
            assert_equal(:foo, parser.node(name).parentclass)
            # Now make sure that trying to redefine it throws an error.
            assert_raise(Puppet::ParseError) {
                parser.newnode(name, {})
            }
        end
    end

    def test_newdefine
        parser = mkparser

        assert_nothing_raised {
            parser.newdefine("mydefine", :code => :yay,
                :arguments => ["a", stringobj("b")])
        }

        mydefine = parser.definition("mydefine")
        assert(mydefine, "Could not find definition")
        assert_equal("", mydefine.namespace)
        assert_equal("mydefine", mydefine.classname)

        assert_raise(Puppet::ParseError) do
            parser.newdefine("mydefine", :code => :yay,
                :arguments => ["a", stringobj("b")])
        end

        # Now define the same thing in a different scope
        assert_nothing_raised {
            parser.newdefine("other::mydefine", :code => :other,
                :arguments => ["a", stringobj("b")])
        }
        other = parser.definition("other::mydefine")
        assert(other, "Could not find definition")
        assert(parser.definition("other::mydefine"),
            "Could not find other::mydefine")
        assert_equal(:other, other.code)
        assert_equal("other", other.namespace)
        assert_equal("other::mydefine", other.classname)
    end

    def test_newclass
        scope = mkscope
        parser = scope.compiler.parser

        mkcode = proc do |ary|
            classes = ary.collect do |string|
                AST::FlatString.new(:value => string)
            end
            AST::ASTArray.new(:children => classes)
        end


        # First make sure that code is being appended
        code = mkcode.call(%w{original code})

        klass = nil
        assert_nothing_raised {
            klass = parser.newclass("myclass", :code => code)
        }

        assert(klass, "Did not return class")

        assert(parser.hostclass("myclass"), "Could not find definition")
        assert_equal("myclass", parser.hostclass("myclass").classname)
        assert_equal(%w{original code},
             parser.hostclass("myclass").code.evaluate(scope))

        # Newclass behaves differently than the others -- it just appends
        # the code to the existing class.
        code = mkcode.call(%w{something new})
        assert_nothing_raised do
            klass = parser.newclass("myclass", :code => code)
        end
        assert(klass, "Did not return class when appending")
        assert_equal(%w{original code something new},
            parser.hostclass("myclass").code.evaluate(scope))

        # Now create the same class name in a different scope
        assert_nothing_raised {
            klass = parser.newclass("other::myclass",
                            :code => mkcode.call(%w{something diff}))
        }
        assert(klass, "Did not return class")
        other = parser.hostclass("other::myclass")
        assert(other, "Could not find class")
        assert_equal("other::myclass", other.classname)
        assert_equal("other::myclass", other.namespace)
        assert_equal(%w{something diff},
             other.code.evaluate(scope))

        # Make sure newclass deals correctly with nodes with no code
        klass = parser.newclass("nocode")
        assert(klass, "Did not return class")

        assert_nothing_raised do
            klass = parser.newclass("nocode", :code => mkcode.call(%w{yay test}))
        end
        assert(klass, "Did not return class with no code")
        assert_equal(%w{yay test},
            parser.hostclass("nocode").code.evaluate(scope))

        # Then try merging something into nothing
        parser.newclass("nocode2", :code => mkcode.call(%w{foo test}))
        assert(klass, "Did not return class with no code")

        assert_nothing_raised do
            klass = parser.newclass("nocode2")
        end
        assert(klass, "Did not return class with no code")
        assert_equal(%w{foo test},
            parser.hostclass("nocode2").code.evaluate(scope))

        # And lastly, nothing and nothing
        klass = parser.newclass("nocode3")
        assert(klass, "Did not return class with no code")

        assert_nothing_raised do
            klass = parser.newclass("nocode3")
        end
        assert(klass, "Did not return class with no code")
        assert_nil(parser.hostclass("nocode3").code)
    end

    # Make sure you can't have classes and defines with the same name in the
    # same scope.
    def test_classes_beat_defines
        parser = mkparser

        assert_nothing_raised {
            parser.newclass("yay::funtest")
        }

        assert_raise(Puppet::ParseError) do
            parser.newdefine("yay::funtest")
        end

        assert_nothing_raised {
            parser.newdefine("yay::yaytest")
        }

        assert_raise(Puppet::ParseError) do
            parser.newclass("yay::yaytest")
        end
    end

    def test_namesplit
        parser = mkparser

        assert_nothing_raised do
            {"base::sub" => %w{base sub},
                "main" => ["", "main"],
                "one::two::three::four" => ["one::two::three", "four"],
            }.each do |name, ary|
                result = parser.namesplit(name)
                assert_equal(ary, result, "%s split to %s" % [name, result])
            end
        end
    end

    # Now make sure we get appropriate behaviour with parent class conflicts.
    def test_newclass_parentage
        parser = mkparser
        parser.newclass("base1")
        parser.newclass("one::two::three")

        # First create it with no parentclass.
        assert_nothing_raised {
            parser.newclass("sub")
        }
        assert(parser.hostclass("sub"), "Could not find definition")
        assert_nil(parser.hostclass("sub").parentclass)

        # Make sure we can't set the parent class to ourself.
        assert_raise(Puppet::ParseError) {
            parser.newclass("sub", :parent => "sub")
        }

        # Now create another one, with a parentclass.
        assert_nothing_raised {
            parser.newclass("sub", :parent => "base1")
        }

        # Make sure we get the right parent class, and make sure it's not an object.
        assert_equal("base1",
                    parser.hostclass("sub").parentclass)

        # Now make sure we get a failure if we try to conflict.
        assert_raise(Puppet::ParseError) {
            parser.newclass("sub", :parent => "one::two::three")
        }

        # Make sure that failure didn't screw us up in any way.
        assert_equal("base1",
                    parser.hostclass("sub").parentclass)
        # But make sure we can create a class with a fq parent
        assert_nothing_raised {
            parser.newclass("another", :parent => "one::two::three")
        }
        assert_equal("one::two::three",
                    parser.hostclass("another").parentclass)

    end

    # Setup a module.
    def mk_module(name, files = {})
        mdir = File.join(@dir, name)
        mandir = File.join(mdir, "manifests")
        FileUtils.mkdir_p mandir

        if defs = files[:define]
            files.delete(:define)
        end
        Dir.chdir(mandir) do
            files.each do |file, classes|
                File.open("%s.pp" % file, "w") do |f|
                    classes.each { |klass|
                        if defs
                            f.puts "define %s {}" % klass
                        else
                            f.puts "class %s {}" % klass
                        end
                    }
                end
            end
        end
    end

    # #596 - make sure classes and definitions load automatically if they're in modules, so we don't have to manually load each one.
    def test_module_autoloading
        @dir = tempfile
        Puppet[:modulepath] = @dir

        FileUtils.mkdir_p @dir

        parser = mkparser

        # Make sure we fail like normal for actually missing classes
        assert_nil(parser.find_hostclass("", "nosuchclass"), "Did not return nil on missing classes")

        # test the simple case -- the module class itself
        name = "simple"
        mk_module(name, :init => [name])

        # Try to load the module automatically now
        klass = parser.find_hostclass("", name)
        assert_instance_of(AST::HostClass, klass, "Did not autoload class from module init file")
        assert_equal(name, klass.classname, "Incorrect class was returned")

        # Try loading the simple module when we're in something other than the base namespace.
        parser = mkparser
        klass = parser.find_hostclass("something::else", name)
        assert_instance_of(AST::HostClass, klass, "Did not autoload class from module init file")
        assert_equal(name, klass.classname, "Incorrect class was returned")

        # Now try it with a definition as the base file
        name = "simpdef"
        mk_module(name, :define => true, :init => [name])

        klass = parser.find_definition("", name)
        assert_instance_of(AST::Definition, klass, "Did not autoload class from module init file")
        assert_equal(name, klass.classname, "Incorrect class was returned")

        # Now try it with namespace classes where both classes are in the init file
        parser = mkparser
        modname = "both"
        name = "sub"
        mk_module(modname, :init => %w{both both::sub})

        # First try it with a namespace
        klass = parser.find_hostclass("both", name)
        assert_instance_of(AST::HostClass, klass, "Did not autoload sub class from module init file with a namespace")
        assert_equal("both::sub", klass.classname, "Incorrect class was returned")

        # Now try it using the fully qualified name
        parser = mkparser
        klass = parser.find_hostclass("", "both::sub")
        assert_instance_of(AST::HostClass, klass, "Did not autoload sub class from module init file with no namespace")
        assert_equal("both::sub", klass.classname, "Incorrect class was returned")


        # Now try it with the class in a different file
        parser = mkparser
        modname = "separate"
        name = "sub"
        mk_module(modname, :init => %w{separate}, :sub => %w{separate::sub})

        # First try it with a namespace
        klass = parser.find_hostclass("separate", name)
        assert_instance_of(AST::HostClass, klass, "Did not autoload sub class from separate file with a namespace")
        assert_equal("separate::sub", klass.classname, "Incorrect class was returned")

        # Now try it using the fully qualified name
        parser = mkparser
        klass = parser.find_hostclass("", "separate::sub")
        assert_instance_of(AST::HostClass, klass, "Did not autoload sub class from separate file with no namespace")
        assert_equal("separate::sub", klass.classname, "Incorrect class was returned")

        # Now make sure we don't get a failure when there's no module file
        parser = mkparser
        modname = "alone"
        name = "sub"
        mk_module(modname, :sub => %w{alone::sub})

        # First try it with a namespace
        assert_nothing_raised("Could not autoload file when module file is missing") do
            klass = parser.find_hostclass("alone", name)
        end
        assert_instance_of(AST::HostClass, klass, "Did not autoload sub class from alone file with a namespace")
        assert_equal("alone::sub", klass.classname, "Incorrect class was returned")

        # Now try it using the fully qualified name
        parser = mkparser
        klass = parser.find_hostclass("", "alone::sub")
        assert_instance_of(AST::HostClass, klass, "Did not autoload sub class from alone file with no namespace")
        assert_equal("alone::sub", klass.classname, "Incorrect class was returned")

        # and with the definition in its own file
        name = "mymod"
        mk_module(name, :define => true, :mydefine => ["mymod::mydefine"])

        klass = parser.find_definition("", "mymod::mydefine")
        assert_instance_of(AST::Definition, klass, "Did not autoload definition from its own file")
        assert_equal("mymod::mydefine", klass.classname, "Incorrect definition was returned")
    end

    # Make sure class, node, and define methods are case-insensitive
    def test_structure_case_insensitivity
        parser = mkparser

        result = nil
        assert_nothing_raised do
            result = parser.newclass "Yayness"
        end
        assert_equal(result, parser.find_hostclass("", "yayNess"))
        
        assert_nothing_raised do
            result = parser.newdefine "FunTest"
        end
        assert_equal(result, parser.find_definition("", "fUntEst"),
            "%s was not matched" % "fUntEst")
    end

    def test_manifests_with_multiple_environments
        parser = mkparser :environment => "something"

        # We use an exception to cut short the processing to simplify our stubbing
        #Puppet::Module.expects(:find_manifests).with("test", {:cwd => ".", :environment => "something"}).raises(Puppet::ParseError)
        Puppet::Parser::Files.expects(:find_manifests).with("test", {:cwd => ".", :environment => "something"}).returns([])

        assert_raise(Puppet::ImportError) do
            parser.import("test")
        end
    end

    def test_watch_file_only_once
        FileTest.stubs(:exists?).returns(true)
        parser = mkparser
        parser.watch_file("doh")
        parser.watch_file("doh")
        assert_equal(1, parser.files.select { |name, file| file.file == "doh" }.length, "Length of watched 'doh' files was not 1")
    end
end

