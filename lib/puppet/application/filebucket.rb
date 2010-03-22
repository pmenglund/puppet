require 'puppet'
require 'puppet/application'
require 'puppet/file_bucket/dipper'

Puppet::Application.new(:filebucket) do

    should_not_parse_config

    option("--bucket BUCKET","-b")
    option("--debug","-d")
    option("--local","-l")
    option("--remote","-r")
    option("--verbose","-v")

    dispatch do
        ARGV.shift
    end

    command(:get) do
        md5 = ARGV.shift
        out = @client.getfile(md5)
        print out
    end

    command(:backup) do
        ARGV.each do |file|
            unless FileTest.exists?(file)
                $stderr.puts "#{file}: no such file"
                next
            end
            unless FileTest.readable?(file)
                $stderr.puts "#{file}: cannot read file"
                next
            end
            md5 = @client.backup(file)
            puts "#{file}: #{md5}"
        end
    end

    command(:restore) do
        file = ARGV.shift
        md5 = ARGV.shift
        @client.restore(file, md5)
    end

    setup do
        Puppet::Log.newdestination(:console)

        @client = nil
        @server = nil

        trap(:INT) do
            $stderr.puts "Cancelling"
            exit(1)
        end

        if options[:debug]
            Puppet::Log.level = :debug
        elsif options[:verbose]
            Puppet::Log.level = :info
        end

        # Now parse the config
        Puppet.parse_config

            exit(Puppet.settings.print_configs ? 0 : 1) if Puppet.settings.print_configs?

        begin
            if options[:local] or options[:bucket]
                path = options[:bucket] || Puppet[:bucketdir]
                @client = Puppet::FileBucket::Dipper.new(:Path => path)
            else
                require 'puppet/network/handler'
                @client = Puppet::FileBucket::Dipper.new(:Server => Puppet[:server])
            end
        rescue => detail
            $stderr.puts detail
            puts detail.backtrace if Puppet[:trace]
            exit(1)
        end
    end

end

