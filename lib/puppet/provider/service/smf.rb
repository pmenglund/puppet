# Solaris 10 SMF-style services.
Puppet::Type.type(:service).provide :smf, :parent => :base do
  desc "Support for Sun's new Service Management Framework.

  Starting a service is effectively equivalent to enabling it, so there is
  only support for starting and stopping services, which also enables and
  disables them, respectively.

  By specifying manifest => \"/path/to/service.xml\", the SMF manifest will
  be imported if it does not exist.

  "

  defaultfor :operatingsystem => :solaris

  confine :operatingsystem => :solaris

  commands :adm => "/usr/sbin/svcadm", :svcs => "/usr/bin/svcs"
  commands :svccfg => "/usr/sbin/svccfg"

  def setupservice
    begin
      if resource[:manifest]
        [command(:svcs), "-l", @resource[:name]]
        if $CHILD_STATUS.exitstatus == 1
          Puppet.notice "Importing #{@resource[:manifest]} for #{@resource[:name]}"
          svccfg :import, resource[:manifest]
        end
      end
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error.new( "Cannot config #{self.service} to enable it: #{detail}" )
    end
  end

  def enable
    self.start
  end

  def enabled?
    case self.status
    when :running
      return :true
    else
      return :false
    end
  end

  def disable
    self.stop
  end

  def restartcmd
    [command(:adm), :restart, @resource[:name]]
  end

  def startcmd
    self.setupservice
    case self.status
    when :stopped
      [command(:adm), :enable, @resource[:name]]
    when :maintenance
      [command(:adm), :clear, @resource[:name]]
    end
  end

  def status
    if @resource[:status]
      super
      return
    end

    begin
      state = svcs("-H", "-o", "state", @resource[:name]).chomp
    rescue Puppet::ExecutionFailure
      info "Could not get status on service #{self.name}"
      return :stopped
    end


    case state
    when "online"
      #self.warning "matched running #{line.inspect}"
      return :running
    when "offline", "disabled", "uninitialized"
      #self.warning "matched stopped #{line.inspect}"
      return :stopped
    when "maintenance"
      return :maintenance
    when "legacy_run"
      raise Puppet::Error,
        "Cannot manage legacy services through SMF"
    else
      raise Puppet::Error,
        "Unmanageable state '#{state}' on service #{self.name}"
    end

  end

  def stopcmd
    [command(:adm), :disable, @resource[:name]]
  end
end

