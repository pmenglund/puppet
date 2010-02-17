require 'puppet'
require 'puppet/application'
require 'puppet/util/reference'
require 'puppet/network/handler'
require 'puppet/util/rdoc'

$tab = "    "
Reference = Puppet::Util::Reference

Puppet::Application.new(:puppetdoc) do

  should_not_parse_config

  attr_accessor :unknown_args, :manifest

  preinit do
    {:references => [], :mode => :text, :format => :to_rest }.each do |name,value|
      options[name] = value
    end
    @unknown_args = []
    @manifest = false
  end

  option("--all","-a")
  option("--outputdir OUTPUTDIR","-o")
  option("--verbose","-v")
  option("--debug","-d")

  option("--format FORMAT", "-f") do |arg|
    method = "to_#{arg}"
    if Reference.method_defined?(method)
      options[:format] = method
    else
      raise "Invalid output format #{arg}"
    end
  end

  option("--mode MODE", "-m") do |arg|
    if Reference.modes.include?(arg) or arg.intern==:rdoc
      options[:mode] = arg.intern
    else
      raise "Invalid output mode #{arg}"
    end
  end

  option("--list", "-l") do |arg|
    puts Reference.references.collect { |r| Reference.reference(r).doc }.join("\n")
    exit(0)
  end

  option("--reference REFERENCE", "-r") do |arg|
    options[:references] << arg.intern
  end

  unknown do |opt, arg|
    @unknown_args << {:opt => opt, :arg => arg }
    true
  end

  dispatch do
    if [:rdoc, :trac, :markdown].include?(options[:mode])
      return options[:mode]
    else
      return :other
    end
  end

  command(:rdoc) do
    exit_code = 0
    files = []
    unless @manifest
      env = Puppet::Node::Environment.new
      files += env.modulepath
      files << File.dirname(env[:manifest])
    end
    files += ARGV
    Puppet.info "scanning: #{files.inspect}"

          Puppet.settings.setdefaults(
        "puppetdoc",
    
      "document_all" => [false, "Document all resources"]
    )
    Puppet.settings[:document_all] = options[:all] || false
    begin
      if @manifest
        Puppet::Util::RDoc.manifestdoc(files)
      else
        options[:outputdir] = "doc" unless options[:outputdir]
        Puppet::Util::RDoc.rdoc(options[:outputdir], files)
      end
    rescue => detail
      puts detail.backtrace if Puppet[:trace]
      $stderr.puts "Could not generate documentation: #{detail}"
      exit_code = 1
    end
    exit exit_code
  end

  command(:trac) do
    options[:references].each do |name|
      section = Puppet::Util::Reference.reference(name) or raise "Could not find section #{name}"
      section.trac unless options[:mode] == :pdf
    end
  end

  command(:markdown) do
    text = ""
    with_contents = false
    exit_code = 0
    options[:references].sort { |a,b| a.to_s <=> b.to_s }.each do |name|
      raise "Could not find reference #{name}" unless section = Puppet::Util::Reference.reference(name)

      begin
        # Add the per-section text, but with no ToC
        text += section.send(options[:format], with_contents)
        text += Puppet::Util::Reference.footer
        text.gsub!(/`\w+\s+([^`]+)`:trac:/) { |m| $1 }
        Puppet::Util::Reference.markdown(name, text)
        text = ""
      rescue => detail
        puts detail.backtrace
        $stderr.puts "Could not generate reference #{name}: #{detail}"
        exit_code = 1
        next
      end
    end

    exit exit_code
  end

  command(:other) do
    text = ""
    with_contents = !(options[:references].length > 1)
    exit_code = 0
    options[:references].sort { |a,b| a.to_s <=> b.to_s }.each do |name|
      raise "Could not find reference #{name}" unless section = Puppet::Util::Reference.reference(name)

      begin
        # Add the per-section text, but with no ToC
        text += section.send(options[:format], with_contents)
      rescue => detail
        puts detail.backtrace
        $stderr.puts "Could not generate reference #{name}: #{detail}"
        exit_code = 1
        next
      end
    end

    text += Puppet::Util::Reference.footer unless with_contents # We've only got one reference

    # Replace the trac links, since they're invalid everywhere else
    text.gsub!(/`\w+\s+([^`]+)`:trac:/) { |m| $1 }

    if options[:mode] == :pdf
      Puppet::Util::Reference.pdf(text)
    else
      puts text
    end

    exit exit_code
  end

  setup do
    # sole manifest documentation
    if ARGV.size > 0
      options[:mode] = :rdoc
      @manifest = true
    end

    if options[:mode] == :rdoc
      setup_rdoc
    else
      setup_reference
    end
  end

  def setup_reference
    if options[:all]
      # Don't add dynamic references to the "all" list.
      options[:references] = Reference.references.reject do |ref|
        Reference.reference(ref).dynamic?
      end
    end

    options[:references] << :type if options[:references].empty?
  end

  def setup_rdoc(dummy_argument=:work_arround_for_ruby_GC_bug)
    # consume the unknown options
    # and feed them as settings
    if @unknown_args.size > 0
      @unknown_args.each do |option|
        # force absolute path for modulepath when passed on commandline
        if option[:opt]=="--modulepath" or option[:opt] == "--manifestdir"
          option[:arg] = option[:arg].split(':').collect { |p| File.expand_path(p) }.join(':')
        end
        Puppet.settings.handlearg(option[:opt], option[:arg])
      end
    end

    # hack to get access to puppetmasterd modulepath and manifestdir
    Puppet[:name] = "puppetmasterd"
    # Now parse the config
    Puppet.parse_config

    # Handle the logging settings.
    if options[:debug] or options[:verbose]
      if options[:debug]
        Puppet::Util::Log.level = :debug
      else
        Puppet::Util::Log.level = :info
      end

      Puppet::Util::Log.newdestination(:console)
    end
  end
end
