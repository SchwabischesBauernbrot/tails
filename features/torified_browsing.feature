@product
Feature: Browsing the web using the Tor Browser
  As a Tails user
  when I browse the web using the Tor Browser
  all Internet traffic should flow only through Tor

  Background:
    Given a computer
    And I start the computer
    And the computer boots Tails
    And I log in to a new session
    And the Tails desktop is ready
    And Tor is ready
    And available upgrades have been checked
    And all notifications have disappeared
    And I save the state so the background can be restored next scenario

  Scenario: The Tor Browser cannot access the LAN
    Given a web server is running on the LAN
    And I capture all network traffic
    When I start the Tor Browser
    And the Tor Browser has started and loaded the startup page
    And I open a page on the LAN web server in the Tor Browser
    Then I see "TorBrowserUnableToConnect.png" after at most 20 seconds
    And no traffic has flowed to the LAN

  @check_tor_leaks
  Scenario: The Tor Browser directory is usable
    Then the amnesiac Tor Browser directory exists
    And there is a GNOME bookmark for the amnesiac Tor Browser directory
    And the persistent Tor Browser directory does not exist
    When I start the Tor Browser
    And the Tor Browser has started and loaded the startup page
    Then I can save the current page as "index.html" to the default downloads directory
    And I can print the current page as "output.pdf" to the default downloads directory

  @check_tor_leaks
  Scenario: Importing an OpenPGP key from a website
    When I start the Tor Browser
    And the Tor Browser has started and loaded the startup page
    And I open the address "https://tails.boum.org/tails-signing.key" in the Tor Browser
    Then I see "OpenWithImportKey.png" after at most 20 seconds
    When I accept to import the key with Seahorse
    Then I see "KeyImportedNotification.png" after at most 10 seconds

  @check_tor_leaks
  Scenario: Playing HTML5 audio
    When I start the Tor Browser
    And the Tor Browser has started and loaded the startup page
    And no application is playing audio
    And I open the address "http://www.terrillthompson.com/tests/html5-audio.html" in the Tor Browser
    And I click the HTML5 play button
    And 1 application is playing audio after 10 seconds

  @check_tor_leaks
  Scenario: Watching a WebM video
    When I start the Tor Browser
    And the Tor Browser has started and loaded the startup page
    And I open the address "https://webm.html5.org/test.webm" in the Tor Browser
    And I click the blocked video icon
    And I see "TorBrowserNoScriptTemporarilyAllowDialog.png" after at most 30 seconds
    And I accept to temporarily allow playing this video
    Then I see "TorBrowserSampleRemoteWebMVideoFrame.png" after at most 180 seconds

  Scenario: I can view a file stored in "~/Tor Browser" but not in ~/.gnupg
    Given I copy "/usr/share/synaptic/html/index.html" to "/home/amnesia/Tor Browser/synaptic.html" as user "amnesia"
    And I copy "/usr/share/synaptic/html/index.html" to "/home/amnesia/.gnupg/synaptic.html" as user "amnesia"
    And I copy "/usr/share/synaptic/html/index.html" to "/tmp/synaptic.html" as user "amnesia"
    Then the file "/home/amnesia/.gnupg/synaptic.html" exists
    And the file "/lib/live/mount/overlay/home/amnesia/.gnupg/synaptic.html" exists
    And the file "/live/overlay/home/amnesia/.gnupg/synaptic.html" exists
    And the file "/tmp/synaptic.html" exists
    Given I start monitoring the AppArmor log of "/usr/local/lib/tor-browser/firefox"
    When I start the Tor Browser
    And the Tor Browser has started and loaded the startup page
    And I open the address "file:///home/amnesia/Tor Browser/synaptic.html" in the Tor Browser
    Then I see "TorBrowserSynapticManual.png" after at most 5 seconds
    And AppArmor has not denied "/usr/local/lib/tor-browser/firefox" from opening "/home/amnesia/Tor Browser/synaptic.html"
    Given I restart monitoring the AppArmor log of "/usr/local/lib/tor-browser/firefox"
    When I open the address "file:///home/amnesia/.gnupg/synaptic.html" in the Tor Browser
    Then I do not see "TorBrowserSynapticManual.png" after at most 5 seconds
    And AppArmor has denied "/usr/local/lib/tor-browser/firefox" from opening "/home/amnesia/.gnupg/synaptic.html"
    Given I restart monitoring the AppArmor log of "/usr/local/lib/tor-browser/firefox"
    When I open the address "file:///lib/live/mount/overlay/home/amnesia/.gnupg/synaptic.html" in the Tor Browser
    Then I do not see "TorBrowserSynapticManual.png" after at most 5 seconds
    And AppArmor has denied "/usr/local/lib/tor-browser/firefox" from opening "/lib/live/mount/overlay/home/amnesia/.gnupg/synaptic.html"
    Given I restart monitoring the AppArmor log of "/usr/local/lib/tor-browser/firefox"
    When I open the address "file:///live/overlay/home/amnesia/.gnupg/synaptic.html" in the Tor Browser
    Then I do not see "TorBrowserSynapticManual.png" after at most 5 seconds
    # Due to our AppArmor aliases, /live/overlay will be treated
    # as /lib/live/mount/overlay.
    And AppArmor has denied "/usr/local/lib/tor-browser/firefox" from opening "/lib/live/mount/overlay/home/amnesia/.gnupg/synaptic.html"
    # We do not get any AppArmor log for when access to files in /tmp is denied
    # since we explictly override (commit 51c0060) the rules (from the user-tmp
    # abstration) that would otherwise allow it, and we do so with "deny", which
    # also specifies "noaudit". We could explicitly specify "audit deny" and
    # then have logs, but it could be a problem when we set up desktop
    # notifications for AppArmor denials (#9337).
    When I open the address "file:///tmp/synaptic.html" in the Tor Browser
    Then I do not see "TorBrowserSynapticManual.png" after at most 5 seconds

  Scenario: The "Tails documentation" link on the Desktop works
    When I double-click on the "Tails documentation" link on the Desktop
    Then the Tor Browser has started
    And I see "TailsOfflineDocHomepage.png" after at most 10 seconds

  Scenario: The Tor Browser uses TBB's shared libraries
    When I start the Tor Browser
    And the Tor Browser has started
    Then the Tor Browser uses all expected TBB shared libraries

  @check_tor_leaks
  Scenario: Opening check.torproject.org in the Tor Browser shows the green onion and the congratulations message
    When I start the Tor Browser
    And the Tor Browser has started and loaded the startup page
    And I open the address "https://check.torproject.org" in the Tor Browser
    Then I see "TorBrowserTorCheck.png" after at most 180 seconds

  @check_tor_leaks
  Scenario: The Tor Browser's "New identity" feature works as expected
    When I start the Tor Browser
    And the Tor Browser has started and loaded the startup page
    And I open the address "https://check.torproject.org" in the Tor Browser
    Then I see "TorBrowserTorCheck.png" after at most 180 seconds
    When I request a new identity using Torbutton
    And I acknowledge Torbutton's New Identity confirmation prompt
    Then the Tor Browser loads the startup page

  Scenario: The Tor Browser should not have any plugins enabled
    When I start the Tor Browser
    And the Tor Browser has started and loaded the startup page
    Then the Tor Browser has no plugins installed
