Given /^I start the computer from DVD with network unplugged$/ do
  @wait_for_remote_shell = true
  step 'the computer is set to boot from the Tails DVD'
  step 'the network is unplugged'
  step 'I start the computer'
  step 'the computer boots'
end

When /^Tails detects disk read failures$/ do
  squashfs_failed = '/var/lib/live/tails.squashfs_failed'
  $vm.execute('systemctl --now disable tails-detect-squashfs-errors')
  $vm.execute_successfully("touch #{squashfs_failed}")
  RemoteShell::SignalReady.new($vm)
  try_for(60) { $vm.file_exist?(squashfs_failed) }
end

Then /^I see a Disk Failure Message$/ do
  @screen.wait('GnomeDiskFailureMessage.png', 10)
end

Then /^I see a Disk Failure Message on the splash screen$/ do
  @screen.wait('PlymouthDiskFailureMessage.png', 60)
end
