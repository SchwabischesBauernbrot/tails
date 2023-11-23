require 'libvirt'
require 'rexml/document'

VIR_DOMAIN_SNAPSHOT_CREATE_NO_METADATA = 0x4
VIR_DOMAIN_SNAPSHOT_CREATE_DISK_ONLY = 0x10

SNAPSHOTS = {}

def snapshots_dir
  "#{$config['TMPDIR']}/snapshots"
end

def snapshot_dir(name)
  "#{snapshots_dir}/#{name}"
end

def snapshot_memstate_path(name)
  "#{snapshot_dir(name)}/memstate"
end

class Snapshot
  attr_reader :name, :base_disk_xmls, :memstate

  def initialize(name, base_disk_xmls)
    @name = name
    @base_disk_xmls = base_disk_xmls
    @memstate = snapshot_memstate_path(name)
  end

  def delete
    # Remove the snapshot directory
    FileUtils.rm_rf(snapshot_dir(@name))
  end
end

class SnapshotManager
  def exists?(name)
    return true if SNAPSHOTS.key?(name)

    if File.exist?(snapshot_dir(name))
      # Try to load the snapshot, if an exception occurs, return false
      begin
        load_snapshot(name)
        return true
      rescue StandardError => e
        info_log("Warning: Failed to load snapshot '#{name}': #{e}")
        return false
      end
    end
    false
  end

  def delete(name)
    SNAPSHOTS[name].delete
    SNAPSHOTS.delete(name)
  end

  def delete_all
    SNAPSHOTS.keys.each do |name|
      delete(name)
    end
    # Remove the snapshots directory
    FileUtils.rm_rf(snapshots_dir)
  end

  def save(name)
    debug_log("Saving snapshot '#{name}'...")
    # We use external snapshots for memory and disks because they are
    # created a *lot* faster (~1 second vs 3-5 minutes) than internal
    # snapshots and they don't require the domain to be paused.
    # libvirt knows how to create external snapshots but unfortunately
    # it doesn't know how to restore them, so we do that manually
    # (see restore).
    #
    # Some useful resources to learn about the state of external
    # snapshots in libvirt and how to work around the limitations:
    # * https://www.mail-archive.com/libvirt-users@redhat.com/msg12623.html
    # * https://fabianlee.org/2021/01/10/kvm-creating-and-reverting-libvirt-external-snapshots/
    # * https://wiki.libvirt.org/I_created_an_external_snapshot_but_libvirt_will_not_let_me_delete_or_revert_to_it.html

    # Under certain circumstances, external snapshots are not created
    # correctly when the domain is not running.
    unless $vm.running?
      raise "Cannot save snapshot '#{name}' because the domain is not running"
    end

    # Delete the snapshot directory if it already exists
    dir = snapshot_dir(name)
    if Dir.exist?(dir)
      FileUtils.rm_rf(dir)
    end

    # Create the snapshot directory
    FileUtils.mkdir_p(dir)

    # Create a first external snapshot without memory. This is needed
    # to work around a bug in libvirt which causes an external snapshot
    # disk to be created without the original disk being added as backing
    # storage when:
    # 1. The machine is not running, and
    # 2. The original disk itself does not have any backing storage
    #
    # That is the case when we create a snapshot in the restore method
    # (to avoid that we write to the original disk after restoring the
    # snapshot, because the original disk could still be used as backing
    # storage for other snapshots).
    #
    # As a workaround, we first create a disk-only snapshot 'base' and then
    # a second snapshot 'top'. When restoring the snapshot, we change the
    # disk back to the one from snapshot 'base' instead of the original
    # disk and create a new snapshot 'restored' on top of 'base':
    #
    # save
    # ----
    #
    # 1. Create snapshot 'base':
    #
    #   original <- $name.base
    #
    # 2. Create snapshot 'top':
    #
    #   original <- $name.base <- $name.top
    #
    # restore
    # -------
    #
    # 1. Restore snapshot 'base':
    #
    #   original <- $name.base
    #
    # 2. Create snapshot 'restored':
    #
    #   original <- $name.base <- $name.restored
    #
    # This way, snapshot 'restored' is correctly created with backing
    # storage because it's created on top of snapshot 'base' which
    # already has backing storage so the libvirt bug is not triggered.
    create_external_snapshot(name, 'base', disk_only = true)

    # Save the XML of the current disks to be able to restore it later
    disk_files = $vm.disk_source_files
    base_disk_xmls = []
    $vm.disk_xml_elements.each do |xml|
      base_disk_xmls << xml.to_s
    end
    base_disk_xmls.each_with_index do |xml_s, index|
      basename = File.basename(disk_files[index], '.qcow2')
      File.open("#{dir}/#{basename}.xml", 'w') do |f|
        f.write(xml_s)
      end
    end

    # Create the external snapshot via libvirt. This will create a new
    # disk image for each disk, and a memory state file.
    # The old disk images are used as backing files for the new ones.
    create_external_snapshot(name, 'top')

    SNAPSHOTS[name] = Snapshot.new(name, base_disk_xmls)
  end

  def restore(name)
    debug_log("Restoring snapshot '#{name}'...")
    $vm.domain.destroy if $vm.running?
    $vm.display.stop if $vm.display&.active?

    snapshot = SNAPSHOTS[name]

    # Restore the disks from before the snapshot
    $vm.update do |xml|
      # Delete all current disk entries
      xml.elements.each("domain/devices/disk[@device='disk']") do |e|
        xml.elements['domain/devices'].delete_element(e)
      end

      # Now restore the disk entries from before the snapshot
      snapshot.base_disk_xmls.each do |disk|
        disk_rexml = REXML::Document.new(disk).root
        xml.elements['domain/devices'].add_element(disk_rexml)
      end
    end

    # Create a new disk-only snapshot to avoid that the base disk is
    # modified, which could still be used as backing storage for other
    # snapshots.
    # We append a random suffix to avoid name collisions when the
    # snapshot is restored multiple times.
    suffix = 'restored.' + SecureRandom.hex(8)
    create_external_snapshot(name, suffix, disk_only = true)

    # Restore the memory state
    Libvirt::Domain.restore($virt, snapshot.memstate)
    $vm.refresh_domain
    $vm.display.start
  end

  private def load_snapshot(name)
    # Load the XML of the base disks
    base_disk_xmls = []
    Dir.glob("#{snapshot_dir(name)}/*.base.xml") do |file|
      base_disk_xmls << File.read(file)
    end
    SNAPSHOTS[name] = Snapshot.new(name, base_disk_xmls)
  end

  private def create_external_snapshot(name, suffix, disk_only = false)
    info_log("XXX: Creating external snapshot '#{name}'...")
    disk_devs = $vm.disk_devs

    # Do nothing if there are no disks and we want to create a disk-only
    # snapshot.
    return if disk_devs.empty? and disk_only

    disk_files = $vm.disk_source_files
    disks_xml = "    <disks>\n"
    disk_devs.each_with_index do |dev, index|
      info_log("XXX: dev: #{dev}, file: #{disk_files[index]}")

      basename = File.basename(disk_files[index]).split('.')[0]
      # Set source file so that the new disk image is created in the
      # snapshot directory
      file = "#{snapshot_dir(name)}/#{basename}.#{suffix}.qcow2"
      disks_xml += "        <disk name='#{dev}' snapshot='external'>
          <source file='#{file}'/>
        </disk>\n"
    end
    disks_xml += '    </disks>'

    memory_xml = ''
    unless disk_only
      memory_xml = <<~XML
        <memory snapshot='external' file='#{snapshot_memstate_path(name)}'/>
      XML
    end

    xml = <<~XML
      <domainsnapshot>
        <name>#{name}.#{suffix}</name>
        #{memory_xml}
        #{disks_xml}
        </domainsnapshot>
    XML

    debug_log("XXX disks XML:\n#{disks_xml}")
    debug_log("XXX snapshot XML:\n#{xml}")

    # We don't want libvirt to create snapshot metadata because it can't
    # handle external snapshots anyway. We handle restoring and deleting
    # snapshots manually (see restore and delete).
    flags = Libvirt::Domain::Snapshot::CREATE_NO_METADATA
    if disk_only
      flags |= Libvirt::Domain::Snapshot::CREATE_DISK_ONLY
    end
    $vm.domain.snapshot_create_xml(xml, flags)
  end
end
