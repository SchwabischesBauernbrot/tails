# Helper class for manipulating VM storage *volumes*, i.e. it deals
# only with creation of images and their deletion.
# (plugging drives or getting info of plugged devices is done in
# the VM class). We'd like better coupling, but given the ridiculous
# disconnect between Libvirt::StoragePool and Libvirt::Domain (hint:
# they have nothing with each other to do whatsoever) it's what makes
# sense.

require 'libvirt'
require 'guestfs'
require 'rexml/document'
require 'etc'

class NoSpaceLeftError < StandardError
end

class VMStorage
  def initialize(virt, xml_path)
    @virt = virt
    @xml_path = xml_path
    pool_xml = REXML::Document.new(File.read("#{@xml_path}/storage_pool.xml"))
    pool_name = pool_xml.elements['pool/name'].text
    @pool_path = "#{$config['TMPDIR']}/#{pool_name}"
    begin
      @pool = @virt.lookup_storage_pool_by_name(pool_name)
    rescue Libvirt::RetrieveError
      @pool = nil
    end
    if @pool && (!KEEP_SNAPSHOTS ||
                  (KEEP_SNAPSHOTS && !Dir.exist?(@pool_path)))
      VMStorage.clear_storage_pool(@pool)
      @pool = nil
    end
    unless @pool
      pool_xml.elements['pool/target/path'].text = @pool_path
      @pool = @virt.define_storage_pool_xml(pool_xml.to_s)
      unless Dir.exist?(@pool_path)
        # We'd like to use @pool.build, which will just create the
        # @pool_path directory, but it does so with root:root as owner
        # (at least with libvirt 1.2.21-2). libvirt itself can handle
        # that situation, but guestfs (at least with <=
        # 1:1.28.12-1+b3) cannot when invoked by a non-root user,
        # which we want to support.
        FileUtils.mkdir(@pool_path)
        FileUtils.chown(nil, 'libvirt-qemu', @pool_path)
        FileUtils.chmod('ug+wrx', @pool_path)
      end
    end
    @pool.create unless @pool.active?
    @pool.refresh
  end

  def self.clear_storage_pool_volumes(pool)
    was_not_active = !pool.active?
    pool.create if was_not_active
    pool.list_volumes.each do |vol_name|
      vol = pool.lookup_volume_by_name(vol_name)
      vol.delete
    end
    pool.destroy if was_not_active
  rescue StandardError
    # Some of the above operations can fail if the pool's path was
    # deleted by external means; let's ignore that.
  end

  def self.clear_storage_pool(pool)
    VMStorage.clear_storage_pool_volumes(pool)
    pool.destroy if pool.active?
    pool.undefine
  end

  def clear_pool
    VMStorage.clear_storage_pool(@pool)
  end

  def clear_volumes
    VMStorage.clear_storage_pool_volumes(@pool)
  end

  def list_volumes
    @pool.list_volumes
  end

  def delete_volume(name)
    @pool.lookup_volume_by_name(name).delete
  end

  # XXX: giving up on a few worst offenders for now
  # rubocop:disable Metrics/AbcSize
  def create_new_volume(name, **options)
    options[:size] ||= 2
    options[:unit] ||= 'GiB'
    options[:type] ||= 'qcow2'
    # Require 'slightly' more space to be available to give a bit more leeway
    # with rounding, temp file creation, etc.
    reserved = 500
    needed = convert_to_MiB(options[:size].to_i, options[:unit])
    avail = convert_to_MiB(get_free_space('host', @pool_path), 'KiB')
    if avail - reserved < needed
      raise NoSpaceLeftError,
            "Error creating disk \"#{name}\" in \"#{@pool_path}\". " \
            "Need #{needed} MiB but only #{avail} MiB is available of " \
            "which #{reserved} MiB is reserved for other temporary files."
    end
    begin
      old_vol = @pool.lookup_volume_by_name(name)
    rescue Libvirt::RetrieveError
      # noop
    else
      old_vol.delete
    end
    uid = Etc.getpwnam('libvirt-qemu').uid
    gid = Etc.getgrnam('libvirt-qemu').gid
    vol_xml = REXML::Document.new(File.read("#{@xml_path}/volume.xml"))
    vol_xml.elements['volume/name'].text = name
    size_b = convert_to_bytes(options[:size].to_f, options[:unit])
    vol_xml.elements['volume/capacity'].text = size_b.to_s
    vol_xml.elements['volume/target/format'].attributes['type'] = options[:type]
    vol_xml.elements['volume/target/path'].text = "#{@pool_path}/#{name}"
    vol_xml.elements['volume/target/permissions/owner'].text = uid.to_s
    vol_xml.elements['volume/target/permissions/group'].text = gid.to_s
    @pool.create_volume_xml(vol_xml.to_s)
    @pool.refresh
  end
  # rubocop:enable Metrics/AbcSize

  def clone_to_new_disk(from, to)
    begin
      old_to_vol = @pool.lookup_volume_by_name(to)
    rescue Libvirt::RetrieveError
      # noop
    else
      old_to_vol.delete
    end
    from_vol = @pool.lookup_volume_by_name(from)
    xml = REXML::Document.new(from_vol.xml_desc)
    pool_path = REXML::Document.new(@pool.xml_desc)
                               .elements['pool/target/path'].text
    xml.elements['volume/name'].text = to
    xml.elements['volume/target/path'].text = "#{pool_path}/#{to}"
    @pool.create_volume_xml_from(xml.to_s, from_vol)
  end

  def volume_format(name)
    vol = @pool.lookup_volume_by_name(name)
    vol_xml = REXML::Document.new(vol.xml_desc)
    vol_xml.elements['volume/target/format'].attributes['type']
  end

  def volume_path(name)
    @pool.lookup_volume_by_name(name).path
  end
end
