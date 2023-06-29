Then /^the Unsafe Browser has no add-ons installed$/ do
  step 'I open the address "about:addons" in the Unsafe Browser'
  step 'I see "UnsafeBrowserNoAddons.png" after at most 30 seconds'
end

Then /^the Unsafe Browser has no bookmarks$/ do
  info = xul_application_info('Unsafe Browser')
  # "Show all bookmarks"
  @screen.press('shift', 'ctrl', 'o')
  @screen.wait('UnsafeBrowserExportBookmarksButton.png', 20).click
  @screen.wait('UnsafeBrowserExportBookmarksButtonSelected.png', 20)
  @screen.wait('UnsafeBrowserExportBookmarksMenuEntry.png', 20).click
  @screen.wait('UnsafeBrowserExportBookmarksSavePrompt.png', 20)
  # This prompt defaults to $HOME/Desktop which is inaccessible due to
  # AppArmor confinement, so there is a permission error message that
  # we have to close.
  @screen.press('Escape')
  sleep 1
  path = "/home/#{info[:user]}/Tor Browser/bookmarks.json"
  # The .json extension is automatically added in this prompt so we
  # avoid adding it again.
  @screen.paste(path.sub(/[.]json$/, ''))
  @screen.press('Return')
  try_for(10) { $vm.file_exist?(path) }
  dump = JSON.parse($vm.file_content(path))

  def check_bookmarks_helper(bookmarks_children)
    bookmarks_children.each do |h|
      h.each_pair do |k, v|
        if k == 'children'
          check_bookmarks_helper(v)
        elsif k == 'uri'
          uri = v
          raise "Unexpected Unsafe Browser bookmark for '#{uri}'"
        end
      end
    end
  end

  check_bookmarks_helper(dump['children'])
  @screen.press('alt', 'F4')
end

Then /^the Unsafe Browser has a red theme$/ do
  @screen.wait('UnsafeBrowserRedTheme.png', 10)
end

Then /^the Unsafe Browser Browser displays the LAN web server hello message$/ do
  msg = LAN_WEB_SERVER_HELLO_MSG.dup
  try_for(60, delay: 3) do
    page_has_heading(@unsafe_browser, "#{msg} — Unsafe Browser", msg)
  end
end

Then /^the Unsafe Browser shows a warning as its start page(?: in "([^"]+)")?$/ do |lang_code|
  if lang_code
    # Use localized image for languages that have a translated version
    # of the Unsafe Browser homepage.
    localized_image = "UnsafeBrowserStartPage.#{lang_code}.png"
    start_page_image = if File.exist?("#{OPENCV_IMAGE_PATH}/#{localized_image}")
                         localized_image
                       else
                         start_page_image = 'UnsafeBrowserStartPage.png'
                       end
  else
    start_page_image = 'UnsafeBrowserStartPage.png'
  end
  @screen.wait(start_page_image, 60)
end

Then /^the Unsafe Browser has started(?: in "([^"]+)")?$/ do |lang_code|
  try_for(60) do
    @unsafe_browser = Dogtail::Application.new('Firefox')
    @unsafe_browser.child?(roleName: 'frame', recursive: false)
  end
  if lang_code
    step 'the Unsafe Browser shows a warning as its start page in ' \
         "\"#{lang_code}\""
  else
    step 'the Unsafe Browser shows a warning as its start page'
  end
end

Then /^I see a warning about another instance already running$/ do
  assert_not_nil(
    Dogtail::Application.new('zenity')
    .child(roleName: 'label')
    .text['Another Unsafe Browser is currently running']
  )
end

Then /^I can start the Unsafe Browser again$/ do
  step 'I start the Unsafe Browser'
end

When /^I configure the Unsafe Browser to use a local proxy$/ do
  socksports =
    $vm.execute_successfully('grep -w "^SocksPort" /etc/tor/torrc').stdout
  assert(socksports.lines.size >= 3, 'We got too few Tor SocksPorts')
  proxy = socksports.scan(/^SocksPort\s([^:]+):(\d+)/).sample
  proxy_host = proxy[0]
  proxy_port = proxy[1]

  debug_log('Configuring the Unsafe Browser to use a Tor SOCKS proxy ' \
            "(host=#{proxy_host}, port=#{proxy_port})")

  prefs = '/usr/share/tails/chroot-browsers/unsafe-browser/prefs.js'
  $vm.file_append(prefs, 'user_pref("network.proxy.type", 1);' + "\n")
  $vm.file_append(prefs,
                  "user_pref(\"network.proxy.socks\", \"#{proxy_host}\");\n")
  $vm.file_append(prefs,
                  "user_pref(\"network.proxy.socks_port\", #{proxy_port});\n")
  $vm.execute_successfully("sed -i -E '/^\s*export TOR_TRANSPROXY=1/d' " \
                           "'/usr/local/lib/unsafe-browser'")
end

Then /^I am told I cannot start the Unsafe Browser when I am offline$/ do
  try_for(30) do
    Dogtail::Application.new('zenity')
      .child(roleName: 'label')
      .text['You are not connected to a local network']
  end
end

Then /^the Unsafe Browser complains that it is disabled$/ do
  try_for(30) do
    Dogtail::Application.new('zenity')
    .child(roleName: 'label')
    .text['The Unsafe Browser was disabled in the Welcome Screen']
  end
end

Then /^I configure the Unsafe Browser to check for updates more frequently$/ do
  prefs = '/usr/share/tails/chroot-browsers/unsafe-browser/prefs.js'
  $vm.file_append(prefs, 'pref("app.update.idletime", 1);')
  $vm.file_append(prefs, 'pref("app.update.promptWaitTime", 1);')
  $vm.file_append(prefs, 'pref("app.update.interval", 5);')
end

But /^checking for updates is disabled in the Unsafe Browser's configuration$/ do
  prefs = '/usr/share/tails/chroot-browsers/common/prefs.js'
  assert($vm.file_content(prefs).include?('pref("app.update.enabled", false)'))
end

Then /^the Unsafe Browser has (|not )sent packets out to the Internet$/ do |sent|
  pkts = ip4tables_packet_counter_sum('FORWARD', 'veth-clearnet')
  case sent
  when ''
    assert(pkts.positive?, 'Packets have not gone out to the internet.')
  when 'not'
    assert_equal(0, pkts, 'Packets have gone out to the internet.')
  end
end
