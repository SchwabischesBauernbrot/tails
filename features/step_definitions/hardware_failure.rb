def click_gnome_shell_notification_button(title)
  # copied from additional_software_packages.rb
  # The notification buttons do not expose any actions through AT-SPI,
  # so Dogtail is unable to click it directly. We let it grab focus
  # and activate it via the keyboard instead.
  Dogtail::Application.new('gnome-shell')
                      .child(title, roleName: 'push button')
                      .grabFocus
  @screen.press('Return')
end

Given /^I start the computer from DVD with network unplugged( and an unsupported Graphic card)?$/ do |graphic_card|
  if graphic_card
    @boot_options = "autotest_broken_gnome_shell"
  else
    @wait_for_remote_shell = true
  end
  step 'the computer is set to boot from the Tails DVD'
  step 'the network is unplugged'
  step 'I start the computer'
  the_computer_boots
end

When /^Tails detects disk read failures$/ do
  squashfs_failed = '/var/lib/live/tails.squashfs_failed'
  $vm.execute('systemctl --now disable tails-detect-squashfs-errors')
  $vm.execute_successfully("touch #{squashfs_failed}")
  try_for(60) { $vm.file_exist?(squashfs_failed) }
  RemoteShell::SignalReady.new($vm)
end

Then /^I see a Disk Failure Message$/ do
  @screen.wait('GnomeDiskFailureMessage.png', 10)
end

Then /^I see a Disk Failure Message on the splash screen$/ do
  @screen.wait('PlymouthDiskFailureMessage.png', 60)
end

Then /^I can open the Hardware Failure documentation from the Disk Failure Message$/ do
  click_gnome_shell_notification_button('Learn More')
  try_for(60) { @torbrowser = Dogtail::Application.new('Firefox') }
  step '"Tails - Error Reading Data from Tails USB Stick" has loaded in the Tor Browser'
end

Then /^I see a Graphic card Failure Message on the splash screen$/ do
  @screen.wait('PlymouthGraphicCardFailureMessage.png', 60)
end
