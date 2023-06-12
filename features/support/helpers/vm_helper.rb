require 'find'
require 'ipaddr'
require 'libvirt'
require 'rexml/document'

class ExecutionFailedInVM < StandardError
end

class VMNet
  attr_reader :net_name, :net

  def initialize(virt, xml_path)
    @virt = virt
    @net_name = LIBVIRT_NETWORK_NAME
    net_xml = File.read("#{xml_path}/default_net.xml")
    rexml = REXML::Document.new(net_xml)
    rexml.elements['network'].add_element('name')
    rexml.elements['network/name'].text = @net_name
    rexml.elements['network'].add_element('uuid')
    rexml.elements['network/uuid'].text = LIBVIRT_NETWORK_UUID
    update(xml: rexml.to_s)
  rescue StandardError => e
    destroy_and_undefine
    raise e
  end

  # We lookup by name so we also catch networks from previous test
  # suite runs that weren't properly cleaned up (e.g. aborted).
  def destroy_and_undefine
    old_net = @virt.lookup_network_by_name(@net_name)
    old_net.destroy if old_net.active?
    old_net.undefine
  rescue StandardError
    # Nothing to clean up
  end

  def net_xml
    REXML::Document.new(@net.xml_desc)
  end

  def update(xml: nil)
    xml = if block_given?
            xml = net_xml
            # The block modifies the mutable xml (REXML::Document) object
            # as a side-effect.
            yield xml
            xml.to_s
          elsif !xml.nil?
            xml.to_s
          else
            raise 'update needs either XML or a block'
          end
    destroy_and_undefine
    @net = @virt.define_network_xml(xml)
    @net.create
  end

  def bridge_name
    @net.bridge_name
  end

  def bridge_ip_addr
    IPAddr.new(net_xml.elements['network/ip'].attributes['address']).to_s
  end

  def bridge_mac
    File.open("/sys/class/net/#{bridge_name}/address", 'rb').read.chomp
  end
end

# XXX: giving up on a few worst offenders for now
# rubocop:disable Metrics/ClassLength
class VM
  attr_reader :domain, :domain_name, :display, :vmnet, :storage

  def initialize(virt, xml_path, vmnet, storage, x_display)
    @virt = virt
    @xml_path = xml_path
    @vmnet = vmnet
    @storage = storage
    @domain_name = LIBVIRT_DOMAIN_NAME
    default_domain_xml = File.read("#{@xml_path}/default.xml")
    rexml = REXML::Document.new(default_domain_xml)
    rexml.elements['domain'].add_element('name')
    rexml.elements['domain/name'].text = @domain_name
    rexml.elements['domain'].add_element('uuid')
    rexml.elements['domain/uuid'].text = LIBVIRT_DOMAIN_UUID

    if $config['LIBVIRT_CPUMODEL']
      rexml.elements['domain/cpu'].add_attribute('mode', 'custom')
      rexml.elements['domain/cpu'].add_attribute('match', 'exact')
      rexml.elements['domain/cpu'].add_attribute('check', 'partial')
      rexml.elements['domain/cpu'].add_element('model')
      rexml.elements['domain/cpu/model'].text = $config['LIBVIRT_CPUMODEL']
      rexml.elements['domain/cpu/model'].add_attribute('fallback', 'allow')
    end

    if config_bool('EARLY_PATCH')
      rexml.elements['domain/devices'].add_element('filesystem')
      rexml.elements['domain/devices/filesystem'].add_attribute('type', 'mount')
      rexml.elements['domain/devices/filesystem'].add_attribute('accessmode', 'passthrough')
      rexml.elements['domain/devices/filesystem'].add_element('source')
      rexml.elements['domain/devices/filesystem'].add_element('target')
      rexml.elements['domain/devices/filesystem'].add_element('readonly')
      rexml.elements['domain/devices/filesystem/source'].add_attribute('dir', Dir.pwd)
      rexml.elements['domain/devices/filesystem/target'].add_attribute('dir', 'src')
    end

    update(xml: rexml.to_s)
    set_vcpu($config['VCPUS']) if $config['VCPUS']
    @display = Display.new(@domain_name, x_display)
    set_cdrom_boot(TAILS_ISO)
    plug_network
    add_remote_shell_channel
  rescue StandardError => e
    destroy_and_undefine
    raise e
  end

  def domain_xml
    REXML::Document.new(@domain.xml_desc)
  end

  def refresh_domain
    @domain = $virt.lookup_domain_by_name(@domain_name)
  end

  def update(xml: nil)
    xml = if block_given?
            xml = domain_xml
            # The block modifies the mutable xml (REXML::Document) object
            # as a side-effect.
            yield xml
            xml.to_s
          elsif !xml.nil?
            xml.to_s
          else
            raise 'update needs either XML or a block'
          end
    destroy_and_undefine
    @domain = @virt.define_domain_xml(xml)
  end

  # We lookup by name so we also catch domains from previous test
  # suite runs that weren't properly cleaned up (e.g. aborted).
  def destroy_and_undefine
    @display.stop if @display&.active?
    begin
      old_domain = @virt.lookup_domain_by_name(@domain_name)
      old_domain.destroy if old_domain.active?
      old_domain.undefine
    rescue StandardError
      # Nothing to clean up
    end
  end

  def save_snapshot(name)
    @snapshots.save(name)
  end

  def restore_snapshot(name)
    @snapshots.restore(name)
  end

  def disk_path(name)
    # Returns the source file of the specified disk. In case that a
    # snapshot is used, the disk file of the snapshot is returned.
    # Find a disk where the basename of the source file starts with the
    # name of the disk, because that's both the case both for snapshot
    # disks and non-snapshot disks.
    domain_xml.elements.each("domain/devices/disk[@device='disk']") do |disk|
      basename = File.basename(disk.elements['source'].attributes['file'])
      if basename.start_with?(name)
        return disk.elements['source'].attributes['file']
      end
    end

    # We found no disk with a matching basename in the domain XML. Try
    # getting it from the storage pool instead.
    storage.volume_path(name)
  end

  def guestfs_with_disks(*disks)
    assert(block_given?)
    g = Guestfs::Guestfs.new
    g.set_trace(1)
    message_callback = proc do |event, _, message, _|
      debug_log("libguestfs: #{Guestfs.event_to_string(event)}: #{message}")
    end
    g.set_event_callback(message_callback,
                         Guestfs::EVENT_ALL)
    g.set_autosync(1)
    disks.each do |disk|
      if disk.instance_of?(String)
        g.add_drive_opts(disk_path(disk), format: @storage.disk_format(disk))
      elsif disk.instance_of?(Hash)
        g.add_drive_opts(disk[:path], disk[:opts])
      else
        raise "cannot handle type '#{disk.class}'"
      end
    end
    g.launch
    yield(g, *g.list_devices)
  ensure
    g.close
  end

  def disk_mklabel(name, parttype)
    guestfs_with_disks(name) do |g, disk_handle|
      g.part_init(disk_handle, parttype)
    end
  end

  # XXX: giving up on a few worst offenders for now
  # rubocop:disable Metrics/AbcSize
  def disk_mkpartfs(name, parttype, fstype, **opts)
    opts[:label] ||= nil
    opts[:luks_password] ||= nil
    opts[:size] ||= nil
    opts[:unit] ||= nil
    guestfs_with_disks(name) do |g, disk_handle|
      if !opts[:size].nil? && !opts[:unit].nil?
        g.part_init(disk_handle, parttype)
        size_in_bytes = convert_to_bytes(opts[:size].to_f, opts[:unit])
        sector_size = g.blockdev_getss(disk_handle)
        size_in_sectors = (size_in_bytes / sector_size).floor
        # leave some room for the partition table
        offset_in_sectors = (convert_to_bytes(4, 'MiB') / sector_size).floor
        g.part_add(disk_handle, 'primary',
                   offset_in_sectors,
                   offset_in_sectors + size_in_sectors - 1)
      else
        g.part_disk(disk_handle, parttype)
      end
      g.part_set_name(disk_handle, 1, opts[:label]) if opts[:label]
      primary_partition = g.list_partitions[0]
      if opts[:luks_password]
        g.luks_format(primary_partition, opts[:luks_password], 0)
        luks_mapping = File.basename(primary_partition) + '_unlocked'
        g.cryptsetup_open(primary_partition, opts[:luks_password], luks_mapping)
        luks_dev = "/dev/mapper/#{luks_mapping}"
        g.mkfs(fstype, luks_dev)
        g.cryptsetup_close(luks_dev)
      else
        g.mkfs(fstype, primary_partition)
      end
    end
  end
  # rubocop:enable Metrics/AbcSize

  def disk_mkswap(name, parttype)
    guestfs_with_disks(name) do |g, disk_handle|
      g.part_disk(disk_handle, parttype)
      primary_partition = g.list_partitions[0]
      g.mkswap(primary_partition)
    end
  end

  def clone_to_new_disk(from, to)
    from_disk_name = File.basename(disk_path(from))
    @storage.clone_to_new_disk(from_disk_name, to)
  end

  def real_mac(alias_name)
    domain_xml.elements["domain/devices/interface[@type='network']/" \
                        "alias[@name='#{alias_name}']"]
              .parent.elements['mac'].attributes['address'].to_s
  end

  def all_real_macs
    macs = []
    domain_xml
      .elements.each("domain/devices/interface[@type='network']") do |nic|
      macs << nic.elements['mac'].attributes['address'].to_s
    end
    macs
  end

  def set_hardware_clock(time)
    assert(!running?, 'The hardware clock cannot be set when the ' \
                             'VM is running')
    assert(time.instance_of?(Time), "Argument must be of type 'Time'")
    adjustment = (time - Time.now).to_i
    update do |xml|
      xml.elements['domain']
         .add_element('clock')
         .add_attributes('offset'     => 'variable',
                         'basis'      => 'utc',
                         'adjustment' => adjustment.to_s)
    end
  end

  def network_link_state
    domain_xml.elements['domain/devices/interface/link']
              .attributes['state']
  end

  def set_network_link_state(state)
    new_xml = domain_xml
    new_xml.elements['domain/devices/interface/link']
           .attributes['state'] = state
    if running?
      @domain.update_device(
        new_xml.elements['domain/devices/interface'].to_s
      )
    else
      update(xml: new_xml)
    end
  end

  def plug_network
    set_network_link_state('up')
  end

  def unplug_network
    set_network_link_state('down')
  end

  def set_boot_device(dev)
    raise 'boot settings can only be set for inactive vms' if running?

    update do |xml|
      xml.elements['domain/os/boot'].attributes['dev'] = dev
    end
  end

  def add_cdrom_device
    raise "Can't attach a CDROM device to a running domain" if running?

    update do |xml|
      if xml.elements["domain/devices/disk[@device='cdrom']"]
        raise 'A CDROM device already exists'
      end

      cdrom_rexml = REXML::Document.new(
        File.read("#{@xml_path}/cdrom.xml")
      ).root
      xml.elements['domain/devices'].add_element(cdrom_rexml)
    end
  end

  def remove_cdrom_device
    raise "Can't detach a CDROM device to a running domain" if running?

    update do |xml|
      cdrom_el = xml.elements["domain/devices/disk[@device='cdrom']"]
      raise 'No CDROM device is present' if cdrom_el.nil?

      xml.elements['domain/devices'].delete_element(cdrom_el)
    end
  end

  def eject_cdrom
    execute_successfully('/usr/bin/eject -m')
  end

  def remove_cdrom_image
    update do |xml|
      cdrom_el = xml.elements["domain/devices/disk[@device='cdrom']"]
      raise 'No CDROM device is present' if cdrom_el.nil?

      cdrom_el.delete_element('source')
    end
  rescue Libvirt::Error => e
    # While the CD-ROM is removed successfully we still get this
    # error, so let's ignore it.
    acceptable_error =
      'Call to virDomainUpdateDeviceFlags failed: internal error: unable to ' \
      "execute QEMU command 'eject': (Tray of device '.*' is not open|" \
      "Device '.*' is locked)"
    raise e unless Regexp.new(acceptable_error).match(e.to_s)
  end

  def set_cdrom_image(image)
    if image.nil? || (image == '')
      raise "Can't set cdrom image to an empty string"
    end

    remove_cdrom_image
    update do |xml|
      cdrom_el = xml.elements["domain/devices/disk[@device='cdrom']"]
      cdrom_el.add_element('source', { 'file' => image })
    end
  end

  def set_cdrom_boot(image)
    raise 'boot settings can only be set for inactive vms' if running?

    unless domain_xml.elements["domain/devices/disk[@device='cdrom']"]
      add_cdrom_device
    end
    set_cdrom_image(image)
    set_boot_device('cdrom')
  end

  def disk_xml_elements
    res = []
    domain_xml.elements.each("domain/devices/disk[@device='disk']") do |e|
      res << e
    end
    res
  end

  def disk_devs
    res = []
    disk_xml_elements.each do |e|
      res << e.elements['target'].attribute('dev').to_s
    end
    res
  end

  def disk_source_files
    res = []
    disk_xml_elements.each do |e|
      res << e.elements['source'].attribute('file').to_s
    end
    res
  end

  def plug_device(device_xml)
    if running?
      @domain.attach_device(device_xml.to_s)
    else
      update do |xml|
        xml.elements['domain/devices'].add_element(device_xml)
      end
    end
  end

  # XXX: giving up on a few worst offenders for now
  # rubocop:disable Metrics/AbcSize
  def plug_drive(name, type)
    debug_log("Plugging drive '#{name}' of type '#{type}'")
    raise "disk '#{name}' already plugged" if disk_plugged?(name)

    removable_usb = nil
    case type
    when 'removable usb', 'usb'
      type = 'usb'
      removable_usb = 'on'
    when 'non-removable usb'
      type = 'usb'
      removable_usb = 'off'
    end
    # Get the next free /dev/sdX on guest
    letter = 'a'
    dev = 'sd' + letter
    while disk_devs.include?(dev)
      letter = (letter[0].ord + 1).chr
      dev = 'sd' + letter
    end
    assert letter <= 'z'

    xml = REXML::Document.new(File.read("#{@xml_path}/disk.xml"))
    xml.elements['disk/source'].attributes['file'] = disk_path(name)
    xml.elements['disk/driver'].attributes['type'] = @storage.disk_format(name)
    xml.elements['disk/target'].attributes['dev'] = dev
    xml.elements['disk/target'].attributes['bus'] = type
    if removable_usb
      xml.elements['disk/target'].attributes['removable'] = removable_usb
    end

    plug_device(xml)
  end
  # rubocop:enable Metrics/AbcSize

  def disk_xml_desc(name)
    domain_xml.elements.each('domain/devices/disk') do |e|
      # We check if the basename of the file attribute starts with the
      # basename of the disk path because if we created a snapshot, the
      # disk file is in a different directory and has a suffix added to
      # it.
      file = e.elements['source'].attribute('file').to_s
      if File.basename(file).start_with?(name)
        return e.to_s
      end

    rescue StandardError
      next
    end
    nil
  end

  def disk_rexml_desc(name)
    xml = disk_xml_desc(name)
    REXML::Document.new(xml) if xml
  end

  def unplug_drive(name)
    xml = disk_xml_desc(name)
    @domain.detach_device(xml)
  end

  def disk_type(dev)
    domain_xml.elements.each('domain/devices/disk') do |e|
      if e.elements['target'].attribute('dev').to_s == dev
        return e.elements['driver'].attribute('type').to_s
      end
    end
    raise "No such disk device '#{dev}'"
  end

  def disk_dev(name)
    (rexml = disk_rexml_desc(name)) || return
    '/dev/' + rexml.elements['disk/target'].attribute('dev').to_s
  end

  def disk_name(dev)
    dev = File.basename(dev)
    domain_xml.elements.each('domain/devices/disk') do |e|
      if /^#{e.elements['target'].attribute('dev')}/.match(dev)
        return File.basename(e.elements['source'].attribute('file').to_s)
      end
    end
    raise "No such disk device '#{dev}'"
  end

  def udisks_disk_dev(name)
    disk_dev(name).gsub('/dev/', '/org/freedesktop/UDisks/devices/')
  end

  def disk_detected?(name)
    (dev = disk_dev(name)) || (return false)
    execute("udisksctl info -b #{dev}").success?
  end

  def disk_plugged?(name)
    !disk_xml_desc(name).nil?
  end

  def persistent_storage_dev_on_disk(name)
    disk_dev(name) + '2'
  end

  def set_disk_boot(name, type)
    raise 'boot settings can only be set for inactive vms' if running?

    plug_drive(name, type) unless disk_plugged?(name)
    set_boot_device('hd')

    # We must remove the CDROM device to allow disk boot.
    if domain_xml.elements["domain/devices/disk[@device='cdrom']"]
      remove_cdrom_device
    end
  end

  def set_os_loader(type)
    raise 'boot settings can only be set for inactive vms' if running?
    raise 'unsupported OS loader type' unless type == 'UEFI'

    update do |xml|
      xml.elements['domain/os'].add_element(
        REXML::Document.new('<loader>/usr/share/ovmf/OVMF.fd</loader>')
      )
    end
  end

  def running?
    @domain.active?
  rescue StandardError
    false
  end

  def execute(cmd, **options)
    options[:user] ||= 'root'
    options[:spawn] = false unless options.key?(:spawn)
    if options[:libs]
      libs = options[:libs]
      options.delete(:libs)
      libs = [libs] unless libs.methods.include? :map
      cmds = libs.map do |lib_name|
        ". /usr/local/lib/tails-shell-library/#{lib_name}.sh"
      end
      cmds << cmd
      cmd = cmds.join(' && ')
    end
    RemoteShell::ShellCommand.new(self, cmd, **options)
  end

  def execute_successfully(*args, **options)
    p = execute(*args, **options)
    begin
      assert_vmcommand_success(p)
    rescue Test::Unit::AssertionFailedError => e
      raise ExecutionFailedInVM, e
    end
    p
  end

  def spawn(cmd, **options)
    options[:spawn] = true
    execute(cmd, **options)
  end

  def remote_shell_socket_path
    domain_rexml = REXML::Document.new(@domain.xml_desc)
    domain_rexml.elements.each('domain/devices/channel') do |e|
      target = e.elements['target']
      if target.attribute('name').to_s == 'org.tails.remote_shell.0'
        return e.elements['source'].attribute('path').to_s
      end
    end
    nil
  end

  def add_remote_shell_channel
    if running?
      raise 'The remote shell channel can only be added for inactive vms'
    end

    if @remote_shell_socket_path.nil?
      @remote_shell_socket_path =
        '/tmp/remote-shell_' + random_alnum_string(8) + '.socket'
    end
    update do |xml|
      channel_xml = <<-XML
        <channel type='unix'>
          <source mode="bind" path='#{@remote_shell_socket_path}'/>
          <target type='virtio' name='org.tails.remote_shell.0'/>
        </channel>
      XML
      xml.elements['domain/devices'].add_element(
        REXML::Document.new(channel_xml)
      )
    end
  end

  def remote_shell_is_up?
    msg = 'hello?'
    Timeout.timeout(3) do
      execute_successfully("echo '#{msg}'").stdout.chomp == msg
    end
  rescue StandardError
    debug_log('The remote shell failed to respond within 3 seconds')
    false
  end

  def wait_until_remote_shell_is_up(timeout = 90)
    try_for(timeout, msg: 'Remote shell seems to be down') do
      remote_shell_is_up?
    end
  end

  def host_to_guest_time_sync
    host_time = Time.now.utc.strftime('%F %T')
    execute_successfully("timedatectl set-time '#{host_time}'")
  end

  def connected_to_network?
    nmcli_info = execute('nmcli device show eth0').stdout
    has_ipv4_addr = %r{^IP4.ADDRESS(\[\d+\])?:\s*([0-9./]+)$}.match(nmcli_info)
    network_link_state == 'up' && has_ipv4_addr
  end

  def process_running?(process)
    execute("pidof -x -o '%PPID' " + process).success?
  end

  def pidof(process)
    execute("pidof -x -o '%PPID' " + process).stdout.chomp.split
  end

  def file_exist?(file)
    execute("test -e '#{file}'").success?
  end

  def file_empty?(file)
    execute("test -s '#{file}'").failure?
  end

  def directory_exist?(directory)
    execute("test -d '#{directory}'").success?
  end

  def file_glob(expr)
    execute(
      <<-COMMAND
        bash -c '
          shopt -s globstar dotglob nullglob
          set -- #{expr}
          while [ -n "${1}" ]; do
            echo -n "${1}"
            echo -ne "\\0"
            shift
          done'
      COMMAND
    ).stdout.chomp.split("\0")
  end

  def file_open(path, **opts)
    f = RemoteShell::File.new(self, path, **opts)
    yield f if block_given?
    f
  end

  def file_content(paths)
    paths = [paths] unless paths.instance_of?(Array)
    paths.reduce('') do |acc, path|
      acc + file_open(path).read
    end
  end

  def file_overwrite(path, lines, permissions: nil)
    lines = lines.join("\n") if lines.instance_of?(Array)
    file_open(path) { |f| f.write(lines) }
    unless permissions.nil?
      execute_successfully("chmod #{permissions} '#{path}'")
    end
  end

  def file_copy_local(localpath, vm_path)
    debug_log("copying #{localpath} to #{vm_path}")
    content = File.read(localpath)
    permissions = File.stat(localpath).mode.to_s(8)[-3..-1]
    file_overwrite(vm_path, content, permissions: permissions)
  end

  def file_copy_local_dir(localdir, vm_dir)
    localfiles = Dir.chdir(localdir) { Find.find('.').select { |p| FileTest.file?(p) } }
    localfiles.each do |fpath|
      # fpath is, for example,"./etc/amnesia/version"
      vm_path = fpath[1..-1]
      dir = File.dirname(vm_path)

      execute_successfully("mkdir -p '#{File.join(vm_dir, dir)}'")
      file_copy_local(File.join(localdir, fpath), File.join(vm_dir, vm_path))
    end
  end

  def late_patch(fname = nil)
    fname = $config['LATE_PATCH'] if fname.nil?
    if fname.nil? || fname.empty?
      debug_log('late_patch called but no filename found')
      return
    end

    File.open(fname).each_line do |line|
      next unless line.count("\t") == 1 && !line.start_with?('#')

      src, dest = line.strip.split("\t", 2)
      unless File.exist?(src)
        debug_log("Error in --late-patch: #{src} does not exist")
        next
      end
      if File.file?(src)
        $vm.file_copy_local(src, dest)
      elsif File.directory?(src)
        $vm.file_copy_local_dir(src, dest)
      else
        debug_log("Error in --late-patch: #{src} not a file or a dir")
      end
    end
  end

  def file_append(path, lines)
    lines = lines.join("\n") if lines.instance_of?(Array)
    file_open(path) { |f| return f.append(lines) }
  end

  def set_clipboard(text)
    execute_successfully("echo -n '#{text}' | xsel --input --clipboard",
                         user: LIVE_USER)
    try_for(5) do
      get_clipboard == text
    end
  end

  def get_clipboard
    execute_successfully('xsel --output --clipboard', user: LIVE_USER).stdout
  end

  def start
    return if running?

    @domain.create
    @display.start
  end

  def reset
    @domain.reset if running?
  end

  def power_off
    begin
      @domain.destroy if running?
    # We're sometimes running this code while Tails is shutting down (#18972),
    # in which case the above statement is racy (TOCTOU). So we ignore
    # the resulting failures:
    rescue Guestfs::Error => e
      raise e unless e.to_s == 'Call to virDomainDestroyFlags failed: ' \
                               'Requested operation is not valid: ' \
                               'domain is not running'

      debug_log('Tried to destroy a domain that was already stopped, ignoring')
    end
    @display.stop
  end

  def set_vcpu(nr_cpus)
    raise 'Cannot set the number of CPUs for a running domain' if running?

    update { |xml| xml.elements['domain/vcpu'].text = nr_cpus }
  end
end
# rubocop:enable Metrics/ClassLength
