# Returns a hash that for each preset the running Tails is aware of
# maps the source to the destination.
def get_persistence_presets(skip_links = false)
  # Perl script that prints all persistence presets (one per line) on
  # the form: <mount_point>:<comma-separated-list-of-options>
  script = <<-EOF
  use strict;
  use warnings FATAL => "all";
  use Tails::Persistence::Configuration::Presets;
  foreach my $preset (Tails::Persistence::Configuration::Presets->new()->all) {
    say $preset->destination, ":", join(",", @{$preset->options});
  }
EOF
  # VMCommand:s cannot handle newlines, and they're irrelevant in the
  # above perl script any way
  script.delete!("\n")
  presets = $vm.execute_successfully("perl -E '#{script}'").stdout.chomp.split("\n")
  assert presets.size >= 10, "Got #{presets.size} persistence presets, " +
                             "which is too few"
  persistence_mapping = Hash.new
  for line in presets
    destination, options_str = line.split(":")
    options = options_str.split(",")
    is_link = options.include? "link"
    next if is_link and skip_links
    source_str = options.find { |option| /^source=/.match option }
    # If no source is given as an option, live-boot's persistence
    # feature defaults to the destination minus the initial "/".
    if source_str.nil?
      source = destination.partition("/").last
    else
      source = source_str.split("=")[1]
    end
    persistence_mapping[source] = destination
  end
  return persistence_mapping
end

def persistent_dirs
  get_persistence_presets
end

def persistent_mounts
  get_persistence_presets(true)
end

def persistent_volumes_mountpoints
  $vm.execute("ls -1 -d /live/persistence/*_unlocked/").stdout.chomp.split
end

Given /^I clone USB drive "([^"]+)" to a new USB drive "([^"]+)"$/ do |from, to|
  $vm.storage.clone_to_new_disk(from, to)
end

Given /^I unplug USB drive "([^"]+)"$/ do |name|
  $vm.unplug_drive(name)
end

Given /^the computer is set to boot from the old Tails DVD$/ do
  $vm.set_cdrom_boot(OLD_TAILS_ISO)
end

Given /^the computer is set to boot in UEFI mode$/ do
  $vm.set_os_loader('UEFI')
  @os_loader = 'UEFI'
end

class UpgradeNotSupported < StandardError
end

def usb_install_helper(name)
  @screen.wait('USBTailsLogo.png', 10)
  if @screen.exists("USBCannotUpgrade.png")
    raise UpgradeNotSupported
  end
  @screen.wait_and_click('USBCreateLiveUSB.png', 10)
  @screen.wait('USBCreateLiveUSBConfirmWindow.png', 10)
  @screen.wait_and_click('USBCreateLiveUSBConfirmYes.png', 10)
  @screen.wait('USBInstallationComplete.png', 30*60)
end

When /^I start Tails Installer$/ do
  step 'I start "Tails Installer" via the GNOME "Tails" applications menu'
  @screen.wait('USBCloneAndInstall.png', 30)
end

When /^I start Tails Installer in "([^"]+)" mode$/ do |mode|
  step 'I start Tails Installer'
  case mode
  when 'Clone & Install'
    @screen.wait_and_click('USBCloneAndInstall.png', 10)
  when 'Clone & Upgrade'
    @screen.wait_and_click('USBCloneAndUpgrade.png', 10)
  when 'Upgrade from ISO'
    @screen.wait_and_click('USBUpgradeFromISO.png', 10)
  else
    raise "Unsupported mode '#{mode}'"
  end
end

Then /^Tails Installer detects that a device is too small$/ do
  @screen.wait('TailsInstallerTooSmallDevice.png', 10)
end

When /^I "Clone & Install" Tails to USB drive "([^"]+)"$/ do |name|
  step 'I start Tails Installer in "Clone & Install" mode'
  usb_install_helper(name)
end

When /^I "Clone & Upgrade" Tails to USB drive "([^"]+)"$/ do |name|
  step 'I start Tails Installer in "Clone & Upgrade" mode'
  usb_install_helper(name)
end

When /^I try a "Clone & Upgrade" Tails to USB drive "([^"]+)"$/ do |name|
  begin
    step "I \"Clone & Upgrade\" Tails to USB drive \"#{name}\""
  rescue UpgradeNotSupported
    # this is what we expect
  else
    raise "The USB installer should not succeed"
  end
end

When /^I try to "Upgrade from ISO" USB drive "([^"]+)"$/ do |name|
  begin
    step "I do a \"Upgrade from ISO\" on USB drive \"#{name}\""
  rescue UpgradeNotSupported
    # this is what we expect
  else
    raise "The USB installer should not succeed"
  end
end

When /^I am suggested to do a "Clone & Install"$/ do
  @screen.find("USBCannotUpgrade.png")
end

When /^I am told that the destination device cannot be upgraded$/ do
  @screen.find("USBCannotUpgrade.png")
end

Given /^I setup a filesystem share containing the Tails ISO$/ do
  shared_iso_dir_on_host = "#{$config["TMPDIR"]}/shared_iso_dir"
  @shared_iso_dir_on_guest = "/tmp/shared_iso_dir"
  FileUtils.mkdir_p(shared_iso_dir_on_host)
  FileUtils.cp(TAILS_ISO, shared_iso_dir_on_host)
  add_after_scenario_hook { FileUtils.rm_r(shared_iso_dir_on_host) }
  $vm.add_share(shared_iso_dir_on_host, @shared_iso_dir_on_guest)
end

When /^I do a "Upgrade from ISO" on USB drive "([^"]+)"$/ do |name|
  step 'I start Tails Installer in "Upgrade from ISO" mode'
  @screen.wait('USBUseLiveSystemISO.png', 10)
  match = @screen.find('USBUseLiveSystemISO.png')
  @screen.click(match.getCenter.offset(0, match.h*2))
  @screen.wait('USBSelectISO.png', 10)
  @screen.wait_and_click('GnomeFileDiagHome.png', 10)
  @screen.type("l", Sikuli::KeyModifier.CTRL)
  @screen.wait('GnomeFileDiagTypeFilename.png', 10)
  iso = "#{@shared_iso_dir_on_guest}/#{File.basename(TAILS_ISO)}"
  @screen.type(iso)
  @screen.wait_and_click('GnomeFileDiagOpenButton.png', 10)
  usb_install_helper(name)
end

Given /^I enable all persistence presets$/ do
  @screen.wait('PersistenceWizardPresets.png', 20)
  # Select the "Persistent" folder preset, which is checked by default.
  @screen.type(Sikuli::Key.TAB)
  # Check all non-default persistence presets, i.e. all *after* the
  # "Persistent" folder, which are unchecked by default.
  (persistent_dirs.size - 1).times do
    @screen.type(Sikuli::Key.TAB + Sikuli::Key.SPACE)
  end
  @screen.wait_and_click('PersistenceWizardSave.png', 10)
  @screen.wait('PersistenceWizardDone.png', 30)
  @screen.type(Sikuli::Key.F4, Sikuli::KeyModifier.ALT)
end

When /^I disable the first persistence preset$/ do
  step 'I start "Configure persistent volume" via the GNOME "Tails" applications menu'
  @screen.wait('PersistenceWizardPresets.png', 300)
  @screen.type(Sikuli::Key.SPACE)
  @screen.wait_and_click('PersistenceWizardSave.png', 10)
  @screen.wait('PersistenceWizardDone.png', 30)
  @screen.type(Sikuli::Key.F4, Sikuli::KeyModifier.ALT)
end

Given /^I create a persistent partition$/ do
  step 'I start "Configure persistent volume" via the GNOME "Tails" applications menu'
  @screen.wait('PersistenceWizardStart.png', 20)
  @screen.type(@persistence_password + "\t" + @persistence_password + Sikuli::Key.ENTER)
  @screen.wait('PersistenceWizardPresets.png', 300)
  step "I enable all persistence presets"
end

def check_disk_integrity(name, dev, scheme)
  info = $vm.execute("udisksctl info --block-device '#{dev}'").stdout
  info_split = info.split("\n  org\.freedesktop\.UDisks2\.PartitionTable:\n")
  dev_info = info_split[0]
  part_table_info = info_split[1]
  assert(part_table_info.match("^    Type: +#{scheme}$"),
         "Unexpected partition scheme on USB drive '#{name}', '#{dev}'")
end

def check_part_integrity(name, dev, usage, fs_type, part_label, part_type = nil)
  info = $vm.execute("udisksctl info --block-device '#{dev}'").stdout
  info_split = info.split("\n  org\.freedesktop\.UDisks2\.Partition:\n")
  dev_info = info_split[0]
  part_info = info_split[1]
  assert(dev_info.match("^    IdUsage: +#{usage}$"),
         "Unexpected device field 'usage' on USB drive '#{name}', '#{dev}'")
  assert(dev_info.match("^    IdType: +#{fs_type}$"),
         "Unexpected device field 'IdType' on USB drive '#{name}', '#{dev}'")
  assert(part_info.match("^    Name: +#{part_label}$"),
         "Unexpected partition label on USB drive '#{name}', '#{dev}'")
  if part_type
    assert(part_info.match("^    Type: +#{part_type}$"),
           "Unexpected partition type on USB drive '#{name}', '#{dev}'")
  end
end

def tails_is_installed_helper(name, tails_root, loader)
  disk_dev = $vm.disk_dev(name)
  part_dev = disk_dev + "1"
  check_disk_integrity(name, disk_dev, "gpt")
  check_part_integrity(name, part_dev, "filesystem", "vfat", "Tails",
                       # EFI System Partition
                       'c12a7328-f81f-11d2-ba4b-00a0c93ec93b')

  target_root = "/mnt/new"
  $vm.execute("mkdir -p #{target_root}")
  $vm.execute("mount #{part_dev} #{target_root}")

  c = $vm.execute("diff -qr '#{tails_root}/live' '#{target_root}/live'")
  assert(c.success?,
         "USB drive '#{name}' has differences in /live:\n#{c.stdout}\n#{c.stderr}")

  syslinux_files = $vm.execute("ls -1 #{target_root}/syslinux").stdout.chomp.split
  # We deal with these files separately
  ignores = ["syslinux.cfg", "exithelp.cfg", "ldlinux.c32", "ldlinux.sys"]
  for f in syslinux_files - ignores do
    c = $vm.execute("diff -q '#{tails_root}/#{loader}/#{f}' " +
                    "'#{target_root}/syslinux/#{f}'")
    assert(c.success?, "USB drive '#{name}' has differences in " +
           "'/syslinux/#{f}'")
  end

  # The main .cfg is named differently vs isolinux
  c = $vm.execute("diff -q '#{tails_root}/#{loader}/#{loader}.cfg' " +
                  "'#{target_root}/syslinux/syslinux.cfg'")
  assert(c.success?, "USB drive '#{name}' has differences in " +
         "'/syslinux/syslinux.cfg'")

  $vm.execute("umount #{target_root}")
  $vm.execute("sync")
end

Then /^the running Tails is installed on USB drive "([^"]+)"$/ do |target_name|
  loader = boot_device_type == "usb" ? "syslinux" : "isolinux"
  tails_is_installed_helper(target_name, "/lib/live/mount/medium", loader)
end

Then /^the ISO's Tails is installed on USB drive "([^"]+)"$/ do |target_name|
  iso = "#{@shared_iso_dir_on_guest}/#{File.basename(TAILS_ISO)}"
  iso_root = "/mnt/iso"
  $vm.execute("mkdir -p #{iso_root}")
  $vm.execute("mount -o loop #{iso} #{iso_root}")
  tails_is_installed_helper(target_name, iso_root, "isolinux")
  $vm.execute("umount #{iso_root}")
end

Then /^there is no persistence partition on USB drive "([^"]+)"$/ do |name|
  data_part_dev = $vm.disk_dev(name) + "2"
  assert(!$vm.execute("test -b #{data_part_dev}").success?,
         "USB drive #{name} has a partition '#{data_part_dev}'")
end

Then /^a Tails persistence partition exists on USB drive "([^"]+)"$/ do |name|
  dev = $vm.disk_dev(name) + "2"
  check_part_integrity(name, dev, "crypto", "crypto_LUKS", "TailsData")

  # The LUKS container may already be opened, e.g. by udisks after
  # we've run tails-persistence-setup.
  c = $vm.execute("ls -1 /dev/mapper/")
  if c.success?
    for candidate in c.stdout.split("\n")
      luks_info = $vm.execute("cryptsetup status #{candidate}")
      if luks_info.success? and luks_info.stdout.match("^\s+device:\s+#{dev}$")
        luks_dev = "/dev/mapper/#{candidate}"
        break
      end
    end
  end
  if luks_dev.nil?
    c = $vm.execute("echo #{@persistence_password} | " +
                    "cryptsetup luksOpen #{dev} #{name}")
    assert(c.success?, "Couldn't open LUKS device '#{dev}' on  drive '#{name}'")
    luks_dev = "/dev/mapper/#{name}"
  end

  # Adapting check_part_integrity() seems like a bad idea so here goes
  info = $vm.execute("udisksctl info --block-device '#{luks_dev}'").stdout
  assert info.match("^    CryptoBackingDevice: +'/[a-zA-Z0-9_/]+'$")
  assert info.match("^    IdUsage: +filesystem$")
  assert info.match("^    IdType: +ext[34]$")
  assert info.match("^    IdLabel: +TailsData$")

  mount_dir = "/mnt/#{name}"
  $vm.execute("mkdir -p #{mount_dir}")
  c = $vm.execute("mount #{luks_dev} #{mount_dir}")
  assert(c.success?,
         "Couldn't mount opened LUKS device '#{dev}' on drive '#{name}'")

  $vm.execute("umount #{mount_dir}")
  $vm.execute("sync")
  $vm.execute("cryptsetup luksClose #{name}")
end

Given /^I enable persistence$/ do
  @screen.wait('TailsGreeterPersistence.png', 10)
  @screen.type(Sikuli::Key.SPACE)
  @screen.wait('TailsGreeterPersistencePassphrase.png', 10)
  match = @screen.find('TailsGreeterPersistencePassphrase.png')
  @screen.click(match.getCenter.offset(match.w*2, match.h/2))
  @screen.type(@persistence_password)
end

def tails_persistence_enabled?
  persistence_state_file = "/var/lib/live/config/tails.persistence"
  return $vm.execute("test -e '#{persistence_state_file}'").success? &&
         $vm.execute(". '#{persistence_state_file}' && " +
                     'test "$TAILS_PERSISTENCE_ENABLED" = true').success?
end

Given /^all persistence presets(| from the old Tails version)(| but the first one) are enabled$/ do |old_tails, except_first|
  assert(old_tails.empty? || except_first.empty?, "Unsupported case.")
  try_for(120, :msg => "Persistence is disabled") do
    tails_persistence_enabled?
  end
  unexpected_mounts = Array.new
  # Check that all persistent directories are mounted
  if old_tails.empty?
    expected_mounts = persistent_mounts
    if ! except_first.empty?
      first_expected_mount_source      = expected_mounts.keys[0]
      first_expected_mount_destination = expected_mounts[first_expected_mount_source]
      expected_mounts.delete(first_expected_mount_source)
      unexpected_mounts = [first_expected_mount_destination]
    end
  else
    assert_not_nil($remembered_persistence_mounts)
    expected_mounts = $remembered_persistence_mounts
  end
  mount = $vm.execute("mount").stdout.chomp
  for _, dir in expected_mounts do
    assert(mount.include?("on #{dir} "),
           "Persistent directory '#{dir}' is not mounted")
  end
  for dir in unexpected_mounts do
    assert(! mount.include?("on #{dir} "),
           "Persistent directory '#{dir}' is mounted")
  end
end

Given /^persistence is disabled$/ do
  assert(!tails_persistence_enabled?, "Persistence is enabled")
end

Given /^I enable read-only persistence$/ do
  step "I enable persistence"
  @screen.wait_and_click('TailsGreeterPersistenceReadOnly.png', 10)
end

def boot_device
  # Approach borrowed from
  # config/chroot_local_includes/lib/live/config/998-permissions
  boot_dev_id = $vm.execute("udevadm info --device-id-of-file=/lib/live/mount/medium").stdout.chomp
  boot_dev = $vm.execute("readlink -f /dev/block/'#{boot_dev_id}'").stdout.chomp
  return boot_dev
end

def device_info(dev)
  # Approach borrowed from
  # config/chroot_local_includes/lib/live/config/998-permissions
  info = $vm.execute("udevadm info --query=property --name='#{dev}'").stdout.chomp
  info.split("\n").map { |e| e.split('=') } .to_h
end

def boot_device_type
  device_info(boot_device)['ID_BUS']
end

Then /^Tails is running from (.*) drive "([^"]+)"$/ do |bus, name|
  bus = bus.downcase
  case bus
  when "ide"
    expected_bus = "ata"
  else
    expected_bus = bus
  end
  assert_equal(expected_bus, boot_device_type)
  actual_dev = boot_device
  # The boot partition differs between a "normal" install using the
  # USB installer and isohybrid installations
  expected_dev_normal = $vm.disk_dev(name) + "1"
  expected_dev_isohybrid = $vm.disk_dev(name) + "4"
  assert(actual_dev == expected_dev_normal ||
         actual_dev == expected_dev_isohybrid,
         "We are running from device #{actual_dev}, but for #{bus} drive " +
         "'#{name}' we expected to run from either device " +
         "#{expected_dev_normal} (when installed via the USB installer) " +
         "or #{expected_dev_isohybrid} (when installed from an isohybrid)")
end

Then /^the boot device has safe access rights$/ do

  super_boot_dev = boot_device.sub(/[[:digit:]]+$/, "")
  devs = $vm.execute("ls -1 #{super_boot_dev}*").stdout.chomp.split
  assert(devs.size > 0, "Could not determine boot device")
  all_users = $vm.execute("cut -d':' -f1 /etc/passwd").stdout.chomp.split
  all_users_with_groups = all_users.collect do |user|
    groups = $vm.execute("groups #{user}").stdout.chomp.sub(/^#{user} : /, "").split(" ")
    [user, groups]
  end
  for dev in devs do
    dev_owner = $vm.execute("stat -c %U #{dev}").stdout.chomp
    dev_group = $vm.execute("stat -c %G #{dev}").stdout.chomp
    dev_perms = $vm.execute("stat -c %a #{dev}").stdout.chomp
    assert_equal("root", dev_owner)
    assert(dev_group == "disk" || dev_group == "root",
           "Boot device '#{dev}' owned by group '#{dev_group}', expected " +
           "'disk' or 'root'.")
    assert_equal("660", dev_perms)
    for user, groups in all_users_with_groups do
      next if user == "root"
      assert(!(groups.include?(dev_group)),
             "Unprivileged user '#{user}' is in group '#{dev_group}' which " +
             "owns boot device '#{dev}'")
    end
  end

  info = $vm.execute("udisksctl info --block-device '#{super_boot_dev}'").stdout
  assert(info.match("^    HintSystem: +true$"),
         "Boot device '#{super_boot_dev}' is not system internal for udisks")
end

Then /^all persistent filesystems have safe access rights$/ do
  persistent_volumes_mountpoints.each do |mountpoint|
    fs_owner = $vm.execute("stat -c %U #{mountpoint}").stdout.chomp
    fs_group = $vm.execute("stat -c %G #{mountpoint}").stdout.chomp
    fs_perms = $vm.execute("stat -c %a #{mountpoint}").stdout.chomp
    assert_equal("root", fs_owner)
    assert_equal("root", fs_group)
    assert_equal('775', fs_perms)
  end
end

Then /^all persistence configuration files have safe access rights$/ do
  persistent_volumes_mountpoints.each do |mountpoint|
    assert($vm.execute("test -e #{mountpoint}/persistence.conf").success?,
           "#{mountpoint}/persistence.conf does not exist, while it should")
    assert($vm.execute("test ! -e #{mountpoint}/live-persistence.conf").success?,
           "#{mountpoint}/live-persistence.conf does exist, while it should not")
    $vm.execute(
      "ls -1 #{mountpoint}/persistence.conf #{mountpoint}/live-*.conf"
    ).stdout.chomp.split.each do |f|
      file_owner = $vm.execute("stat -c %U '#{f}'").stdout.chomp
      file_group = $vm.execute("stat -c %G '#{f}'").stdout.chomp
      file_perms = $vm.execute("stat -c %a '#{f}'").stdout.chomp
      assert_equal("tails-persistence-setup", file_owner)
      assert_equal("tails-persistence-setup", file_group)
      assert_equal("600", file_perms)
    end
  end
end

Then /^all persistent directories(| from the old Tails version) have safe access rights$/ do |old_tails|
  if old_tails.empty?
    expected_dirs = persistent_dirs
  else
    assert_not_nil($remembered_persistence_dirs)
    expected_dirs = $remembered_persistence_dirs
  end
  persistent_volumes_mountpoints.each do |mountpoint|
    expected_dirs.each do |src, dest|
      full_src = "#{mountpoint}/#{src}"
      assert_vmcommand_success $vm.execute("test -d #{full_src}")
      dir_perms = $vm.execute_successfully("stat -c %a '#{full_src}'").stdout.chomp
      dir_owner = $vm.execute_successfully("stat -c %U '#{full_src}'").stdout.chomp
      if dest.start_with?("/home/#{LIVE_USER}")
        expected_perms = "700"
        expected_owner = LIVE_USER
      else
        expected_perms = "755"
        expected_owner = "root"
      end
      assert_equal(expected_perms, dir_perms,
                   "Persistent source #{full_src} has permission " \
                   "#{dir_perms}, expected #{expected_perms}")
      assert_equal(expected_owner, dir_owner,
                   "Persistent source #{full_src} has owner " \
                   "#{dir_owner}, expected #{expected_owner}")
    end
  end
end

When /^I write some files expected to persist$/ do
  persistent_mounts.each do |_, dir|
    owner = $vm.execute("stat -c %U #{dir}").stdout.chomp
    assert($vm.execute("touch #{dir}/XXX_persist", :user => owner).success?,
           "Could not create file in persistent directory #{dir}")
  end
end

When /^I remove some files expected to persist$/ do
  persistent_mounts.each do |_, dir|
    owner = $vm.execute("stat -c %U #{dir}").stdout.chomp
    assert($vm.execute("rm #{dir}/XXX_persist", :user => owner).success?,
           "Could not remove file in persistent directory #{dir}")
  end
end

When /^I write some files not expected to persist$/ do
  persistent_mounts.each do |_, dir|
    owner = $vm.execute("stat -c %U #{dir}").stdout.chomp
    assert($vm.execute("touch #{dir}/XXX_gone", :user => owner).success?,
           "Could not create file in persistent directory #{dir}")
  end
end

When /^I take note of which persistence presets are available$/ do
  $remembered_persistence_mounts = persistent_mounts
  $remembered_persistence_dirs = persistent_dirs
end

Then /^the expected persistent files(| created with the old Tails version) are present in the filesystem$/ do |old_tails|
  if old_tails.empty?
    expected_mounts = persistent_mounts
  else
    assert_not_nil($remembered_persistence_mounts)
    expected_mounts = $remembered_persistence_mounts
  end
  expected_mounts.each do |_, dir|
    assert($vm.execute("test -e #{dir}/XXX_persist").success?,
           "Could not find expected file in persistent directory #{dir}")
    assert(!$vm.execute("test -e #{dir}/XXX_gone").success?,
           "Found file that should not have persisted in persistent directory #{dir}")
  end
end

Then /^only the expected files are present on the persistence partition on USB drive "([^"]+)"$/ do |name|
  assert(!$vm.is_running?)
  disk = {
    :path => $vm.storage.disk_path(name),
    :opts => {
      :format => $vm.storage.disk_format(name),
      :readonly => true
    }
  }
  $vm.storage.guestfs_disk_helper(disk) do |g, disk_handle|
    partitions = g.part_list(disk_handle).map do |part_desc|
      disk_handle + part_desc["part_num"].to_s
    end
    partition = partitions.find do |part|
      g.blkid(part)["PART_ENTRY_NAME"] == "TailsData"
    end
    assert_not_nil(partition, "Could not find the 'TailsData' partition " \
                              "on disk '#{disk_handle}'")
    luks_mapping = File.basename(partition) + "_unlocked"
    g.luks_open(partition, @persistence_password, luks_mapping)
    luks_dev = "/dev/mapper/#{luks_mapping}"
    mount_point = "/"
    g.mount(luks_dev, mount_point)
    assert_not_nil($remembered_persistence_mounts)
    $remembered_persistence_mounts.each do |dir, _|
      # Guestfs::exists may have a bug; if the file exists, 1 is
      # returned, but if it doesn't exist false is returned. It seems
      # the translation of C types into Ruby types is glitchy.
      assert(g.exists("/#{dir}/XXX_persist") == 1,
             "Could not find expected file in persistent directory #{dir}")
      assert(g.exists("/#{dir}/XXX_gone") != 1,
             "Found file that should not have persisted in persistent directory #{dir}")
    end
    g.umount(mount_point)
    g.luks_close(luks_dev)
  end
end

When /^I delete the persistent partition$/ do
  step 'I start "Delete persistent volume" via the GNOME "Tails" applications menu'
  @screen.wait("PersistenceWizardDeletionStart.png", 20)
  @screen.type(" ")
  @screen.wait("PersistenceWizardDone.png", 120)
end

Then /^Tails has started in UEFI mode$/ do
  assert($vm.execute("test -d /sys/firmware/efi").success?,
         "/sys/firmware/efi does not exist")
 end

Given /^I create a ([[:alpha:]]+) label on disk "([^"]+)"$/ do |type, name|
  $vm.storage.disk_mklabel(name, type)
end

Then /^a suitable USB device is (?:still )?not found$/ do
  @screen.wait("TailsInstallerNoQEMUHardDisk.png", 30)
end

Then /^the "(?:[^"]+)" USB drive is selected$/ do
  @screen.wait("TailsInstallerQEMUHardDisk.png", 30)
end

Then /^no USB drive is selected$/ do
  @screen.wait("TailsInstallerNoQEMUHardDisk.png", 30)
end
