@product
Feature: GNOME is well-integrated into Tails

  @not_release_blocker
  Scenario: A screenshot is taken when the PRINTSCREEN key is pressed
    Given I have started Tails from DVD without network and logged in
    And I wait 10 seconds
    And there is no screenshot in the live user's Pictures directory
    When I press the "PRINTSCREEN" key
    And GNOME offers me various screenshot options
    And I press the "Return" key
    Then a screenshot is saved to the live user's Pictures directory

  Scenario: GNOME notifications are shown to the user
    Given I have started Tails from DVD without network and logged in
    When the "Dogtail rules!" notification is sent
    Then the "Dogtail rules!" notification is shown to the user

  Scenario: I can launch various apps via GNOME Activities Overview
    Given I have started Tails from DVD and logged in with an administration password and the network is connected
    When I start "Additional Software" via GNOME Activities Overview
    And I close the "tails-additional-software-config" window
    When I start "Disks" via GNOME Activities Overview
    # The close button of GNOME Disks is not accessible
    And I close the "gnome-disks" window via Alt+F4
    When I start "Electrum Bitcoin Wallet" via GNOME Activities Overview
    # TODO: Only starts with Persistent Storage
    # When I start "Electrum Bitcoin Wallet" via GNOME Activities Overview
    When I start "GNOME Terminal" via GNOME Activities Overview
    And I close the "gnome-terminal-server" window
    When I start "Files" via GNOME Activities Overview
    And I close the "org.gnome.Nautilus" window
    When I start "Persistent Storage" via GNOME Activities Overview
    And I close the "tps-frontend" window
    # TODO: Only with Persistent Storage(?)
    # When I start "Persistent Storage Backup" via GNOME Activities Overview
    When I start "Pidgin" via GNOME Activities Overview
    And I close the "Pidgin" window
    # TODO: Requires admin password and handling polkit
    # When I start "Synaptic Package Manager" via GNOME Activities Overview
    When I start "Thunderbird" via GNOME Activities Overview
    And I close the "Thunderbird" window
    When I start "Tor Browser" via GNOME Activities Overview
    And I close the "Firefox" window
    When I start "Unlock VeraCrypt Volumes" via GNOME Activities Overview
    And I close the "unlock-veracrypt-volumes" window
    When I start "Unsafe Browser" via GNOME Activities Overview
    And I close the "Firefox" window
