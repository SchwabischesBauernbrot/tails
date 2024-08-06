Given /^I start the computer from DVD with network unplugged( and an unsupported graphics card)?$/ do |graphics_card|
  if graphics_card
    @boot_options = 'autotest_broken_gnome_shell'
  else
    @wait_for_remote_shell = true
  end
  step 'the computer is set to boot from the Tails DVD'
  step 'the network is unplugged'
  step 'I start the computer'
  the_computer_boots
end

When /^Tails detects disk read failures on the (.+)$/ do |device|
  disk_ioerrors = '/var/lib/live/tails.disk.ioerrors'
  fake_ioerror_script_path = '/tmp/fake_ioerror.py'

  case device
  when 'SquashFS'
    fake_error = 'SQUASHFS error: A fake error.'
  when 'boot device'
    b_d = boot_device.delete_prefix('/dev/').delete_suffix('1')
    fake_error = "I/O error, dev #{b_d}, sector - a fake boot device one."
  when 'boot device with a target error'
    b_d = boot_device.delete_prefix('/dev/').delete_suffix('1')
    fake_error = "critical target error, dev #{b_d}, sector - a fake boot device one."
  end

  fake_ioerror_script = <<~FAKEIOERROR
    from systemd import journal
    journal.send("#{fake_error}", SYSLOG_IDENTIFIER="kernel", PRIORITY=3)
  FAKEIOERROR
  $vm.file_overwrite(fake_ioerror_script_path, fake_ioerror_script)
  $vm.execute_successfully(
    'systemctl --quiet is-active tails-detect-disk-ioerrors'
  )
  $vm.execute_successfully("python3 #{fake_ioerror_script_path}")
  try_for(60) { $vm.file_exist?(disk_ioerrors) }
  RemoteShell::SignalReady.new($vm)
end

Then /^I see a disk failure message$/ do
  @screen.wait('GnomeDiskFailureMessage.png', 10)
end

Then /^I see an error about (disk partitioning|GPT header|system partition resizing)$/ do |reason|
  error_message_prefix = 'Something went wrong when starting your Tails USB stick' \
    ' for the first time: '
  reason_to_message = {
    'disk partitioning'         => '',
    'GPT header'                => 'the GPT header is corrupted',
    'system partition resizing' => 'resizing the system partition failed',
  }
  error_message = error_message_prefix + reason_to_message[reason]
  try_for(30) do
    Dogtail::Application.new('zenity')
                        .children(roleName: 'label')
                        .any? { |n| n.text.include?(error_message) }
  end
end

Then /^I see a disk failure message on the splash screen$/ do
  @screen.wait('PlymouthDiskFailureMessage.png', 60)
end

Then /^I can open the hardware failure documentation from the disk failure message$/ do
  click_gnome_shell_notification_button('Learn More')
  try_for(60) { @torbrowser = Dogtail::Application.new('Firefox') }
  step '"Tails - Error Reading Data from Tails USB Stick" has loaded in the Tor Browser'
end

Then /^I see a graphics card failure message on the splash screen$/ do
  @screen.wait('PlymouthGraphicsCardFailureMessage.png', 60)
end
