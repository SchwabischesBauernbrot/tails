@product @check_tor_leaks
Feature: Time syncing
  As a Tails user
  I want Tor to work properly
  And for that I need a reasonably accurate system clock

  Scenario: Clock with host's time
    Given I have started Tails from DVD without network and logged in
    When the network is plugged
    And Tor is ready
    Then Tails clock is less than 5 minutes incorrect

  Scenario: Clock with host's time while using bridges
    Given I have started Tails from DVD without network and logged in
    When the network is plugged
    And the Tor Connection Assistant autostarts
    And I configure some normal bridges in the Tor Connection Assistant
    And Tor is ready
    Then Tails clock is less than 5 minutes incorrect

  Scenario: Clock is one day in the future while using bridges
    Given I have started Tails from DVD without network and logged in
    When I bump the system time with "+1 day"
    And the network is plugged
    And the Tor Connection Assistant autostarts
    And I configure some normal bridges in the Tor Connection Assistant
    And Tor is ready
    Then Tails clock is less than 5 minutes incorrect

  @not_release_blocker
  Scenario: The system time is not synced to the hardware clock
    Given I have started Tails from DVD without network and logged in
    When I bump the system time with "-15 days"
    And I warm reboot the computer
    And the computer reboots Tails
    Then Tails' hardware clock is close to the host system's time

  @not_release_blocker
  Scenario: Anti-test: Changes to the hardware clock are kept when rebooting
    Given I have started Tails from DVD without network and logged in
    When I bump the hardware clock's time with "-15 days"
    And I warm reboot the computer
    And the computer reboots Tails
    Then the hardware clock is still off by "-15 days"

  Scenario: The clock is set to the source date when the hardware clock is way in the past
    Given a computer
    And the network is unplugged
    And the hardware clock is set to "01 Jan 2000 12:34:56"
    And I start the computer
    And the computer boots Tails
    Then the system clock is just past Tails' source date

  Scenario: I can connect to obfs4 bridges having a clock East of UTC
    Given I have started Tails from DVD without network and logged in
    When I bump the system time with "+8 hours +15 minutes"
    And all notifications have disappeared
    And I capture all network traffic
    And the network is plugged
    And the Tor Connection Assistant autostarts
    # Anti-test: Users east of UTC can't connect to obfs4 bridges
    When I unsuccessfully configure some obfs4 bridges in the Tor Connection Assistant
    Then the Tor Connection Assistant reports that it failed to connect
    # The "Fix Clock" button allows users to recover from this bug
    When I set the time zone in Tor Connection to "Asia/Shanghai"
    Then Tails clock is less than 20 minutes incorrect
    # XXX: this fails if tor is too fast to recover after the restart implied by setting the time
    #      TCA will notice this and switch to the success window
    #      so the button "Connect to Tor" cannot be clicked
    #      Implementing #18470 will solve this (see
    #      https://gitlab.tails.boum.org/tails/tails/-/issues/18470#note_174465 )
    When I click "Connect to Tor"
    Then Tor is ready
    And all Internet traffic has only flowed through the configured bridges
    # check that htpdate has done its job
    And Tails clock is less than 5 minutes incorrect
