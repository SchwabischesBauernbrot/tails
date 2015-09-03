def shipped_openpgp_keys
  shipped_gpg_keys = @vm.execute_successfully('gpg --batch --with-colons --fingerprint --list-key', LIVE_USER).stdout
  openpgp_fingerprints = shipped_gpg_keys.scan(/^fpr:::::::::([A-Z0-9]+):$/).flatten
  return openpgp_fingerprints
end

Then /^the OpenPGP keys shipped with Tails will be valid for the next (\d+) months$/ do |months|
  next if @skip_steps_while_restoring_background
  invalid = Array.new
  shipped_openpgp_keys.each do |key|
    begin
      step "the shipped OpenPGP key #{key} will be valid for the next #{months} months"
    rescue Test::Unit::AssertionFailedError
      invalid << key
      next
    end
  end
  assert(invalid.empty?, "The following key(s) will not be valid in #{months} months: #{invalid.join(', ')}")
end

Then /^the shipped (?:Debian repository key|OpenPGP key ([A-Z0-9]+)) will be valid for the next (\d+) months$/ do |fingerprint, max_months|
  next if @skip_steps_while_restoring_background
  if fingerprint
    cmd = 'gpg'
    user = LIVE_USER
  else
    fingerprint = TAILS_DEBIAN_REPO_KEY
    cmd = 'apt-key adv'
    user = 'root'
  end
  shipped_sig_key_info = @vm.execute_successfully("#{cmd} --batch --list-key #{fingerprint}", user).stdout
  m = /\[expire[ds]: ([0-9-]*)\]/.match(shipped_sig_key_info)
  if m
    expiration_date = Date.parse(m[1])
    assert((expiration_date << max_months.to_i) > DateTime.now,
           "The shipped key #{fingerprint} will not be valid #{max_months} months from now.")
  end
end

Then /^I double-click the Report an Error launcher on the desktop$/ do
  next if @skip_steps_while_restoring_background
  @screen.wait_and_double_click('DesktopReportAnError.png', 30)
end

Then /^the live user has been setup by live\-boot$/ do
  next if @skip_steps_while_restoring_background
  assert(@vm.execute("test -e /var/lib/live/config/user-setup").success?,
         "live-boot failed its user-setup")
  actual_username = @vm.execute(". /etc/live/config/username.conf; " +
                                "echo $LIVE_USERNAME").stdout.chomp
  assert_equal(LIVE_USER, actual_username)
end

Then /^the live user is a member of only its own group and "(.*?)"$/ do |groups|
  next if @skip_steps_while_restoring_background
  expected_groups = groups.split(" ") << LIVE_USER
  actual_groups = @vm.execute("groups #{LIVE_USER}").stdout.chomp.sub(/^#{LIVE_USER} : /, "").split(" ")
  unexpected = actual_groups - expected_groups
  missing = expected_groups - actual_groups
  assert_equal(0, unexpected.size,
         "live user in unexpected groups #{unexpected}")
  assert_equal(0, missing.size,
         "live user not in expected groups #{missing}")
end

Then /^the live user owns its home dir and it has normal permissions$/ do
  next if @skip_steps_while_restoring_background
  home = "/home/#{LIVE_USER}"
  assert(@vm.execute("test -d #{home}").success?,
         "The live user's home doesn't exist or is not a directory")
  owner = @vm.execute("stat -c %U:%G #{home}").stdout.chomp
  perms = @vm.execute("stat -c %a #{home}").stdout.chomp
  assert_equal("#{LIVE_USER}:#{LIVE_USER}", owner)
  assert_equal("700", perms)
end

Then /^no unexpected services are listening for network connections$/ do
  next if @skip_steps_while_restoring_background
  netstat_cmd = @vm.execute("netstat -ltupn")
  assert netstat_cmd.success?
  for line in netstat_cmd.stdout.chomp.split("\n") do
    splitted = line.split(/[[:blank:]]+/)
    proto = splitted[0]
    if proto == "tcp"
      proc_index = 6
    elsif proto == "udp"
      proc_index = 5
    else
      next
    end
    laddr, lport = splitted[3].split(":")
    proc = splitted[proc_index].split("/")[1]
    # Services listening on loopback is not a threat
    if /127(\.[[:digit:]]{1,3}){3}/.match(laddr).nil?
      if SERVICES_EXPECTED_ON_ALL_IFACES.include? [proc, laddr, lport] or
         SERVICES_EXPECTED_ON_ALL_IFACES.include? [proc, laddr, "*"]
        puts "Service '#{proc}' is listening on #{laddr}:#{lport} " +
             "but has an exception"
      else
        raise "Unexpected service '#{proc}' listening on #{laddr}:#{lport}"
      end
    end
  end
end

When /^Tails has booted a 64-bit kernel$/ do
  next if @skip_steps_while_restoring_background
  assert(@vm.execute("uname -r | grep -qs 'amd64$'").success?,
         "Tails has not booted a 64-bit kernel.")
end

Then /^GNOME Screenshot is configured to save files to the live user's home directory$/ do
  next if @skip_steps_while_restoring_background
  home = "/home/#{LIVE_USER}"
  save_path = @vm.execute_successfully(
    "gsettings get org.gnome.gnome-screenshot auto-save-directory",
    LIVE_USER).stdout.chomp.tr("'","")
  assert_equal("file://#{home}", save_path,
               "The GNOME screenshot auto-save-directory is not set correctly.")
end

Then /^there is no screenshot in the live user's home directory$/ do
  next if @skip_steps_while_restoring_background
  home = "/home/#{LIVE_USER}"
  assert(@vm.execute("find '#{home}' -name 'Screenshot*.png' -maxdepth 1").stdout.empty?,
         "Existing screenshots were found in the live user's home directory.")
end

Then /^a screenshot is saved to the live user's home directory$/ do
  next if @skip_steps_while_restoring_background
  home = "/home/#{LIVE_USER}"
  try_for(10, :msg=> "No screenshot was created in #{home}") {
    !@vm.execute("find '#{home}' -name 'Screenshot*.png' -maxdepth 1").stdout.empty?
  }
end

Then /^the VirtualBox guest modules are available$/ do
  next if @skip_steps_while_restoring_background
  assert(@vm.execute("modinfo vboxguest").success?,
         "The vboxguest module is not available.")
end

Given /^I setup a filesystem share containing a sample PDF$/ do
  next if @skip_steps_while_restoring_background
  shared_pdf_dir_on_host = "#{$config["TMPDIR"]}/shared_pdf_dir"
  @shared_pdf_dir_on_guest = "/tmp/shared_pdf_dir"
  FileUtils.mkdir_p(shared_pdf_dir_on_host)
  Dir.glob("#{MISC_FILES_DIR}/*.pdf") do |pdf_file|
    FileUtils.cp(pdf_file, shared_pdf_dir_on_host)
  end
  add_after_scenario_hook { FileUtils.rm_r(shared_pdf_dir_on_host) }
  @vm.add_share(shared_pdf_dir_on_host, @shared_pdf_dir_on_guest)
end

Then /^the support documentation page opens in Tor Browser$/ do
  next if @skip_steps_while_restoring_background
  @screen.wait("SupportDocumentation#{@language}.png", 120)
end

Then /^MAT can clean some sample PDF file$/ do
  next if @skip_steps_while_restoring_background
  for pdf_on_host in Dir.glob("#{MISC_FILES_DIR}/*.pdf") do
    pdf_name = File.basename(pdf_on_host)
    pdf_on_guest = "/home/#{LIVE_USER}/#{pdf_name}"
    step "I copy \"#{@shared_pdf_dir_on_guest}/#{pdf_name}\" to \"#{pdf_on_guest}\" as user \"#{LIVE_USER}\""
    check_before = @vm.execute_successfully("mat --check '#{pdf_on_guest}'",
                                            LIVE_USER).stdout
    assert(check_before.include?("#{pdf_on_guest} is not clean"),
           "MAT failed to see that '#{pdf_on_host}' is dirty")
    @vm.execute_successfully("mat '#{pdf_on_guest}'", LIVE_USER)
    check_after = @vm.execute_successfully("mat --check '#{pdf_on_guest}'",
                                           LIVE_USER).stdout
    assert(check_after.include?("#{pdf_on_guest} is clean"),
           "MAT failed to clean '#{pdf_on_host}'")
    @vm.execute_successfully("rm '#{pdf_on_guest}'")
  end
end

Then /^AppArmor is enabled$/ do
  assert(@vm.execute("aa-status").success?, "AppArmor is not enabled")
end

Then /^some AppArmor profiles are enforced$/ do
  assert(@vm.execute("aa-status --enforced").stdout.chomp.to_i > 0,
         "No AppArmor profile is enforced")
end

def get_seccomp_status(process)
  assert(@vm.has_process?(process), "Process #{process} not running.")
  pid = @vm.pidof(process)[0]
  status = @vm.file_content("/proc/#{pid}/status")
  return status.match(/^Seccomp:\s+([0-9])/)[1].chomp.to_i
end

Then /^the running process "(.+)" is confined with Seccomp in (filter|strict) mode$/ do |process,mode|
  next if @skip_steps_while_restoring_background
  status = get_seccomp_status(process)
  if mode == 'strict'
    assert_equal(1, status, "#{process} not confined with Seccomp in strict mode")
  elsif mode == 'filter'
    assert_equal(2, status, "#{process} not confined with Seccomp in filter mode")
  else
    raise "Unsupported mode #{mode} passed"
  end
end
