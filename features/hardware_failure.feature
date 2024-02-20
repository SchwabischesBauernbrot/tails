@product
Feature: Hardware failures
  As a Tails user
  when hardware failures are detected
  I want to to see a message.

  Scenario: Alerting about disk read failures in GNOME
    Given a computer
    And I have started Tails from DVD without network and logged in
    When Tails detects disk read failures
    Then I see a disk failure message
    Then I can open the hardware failure documentation from the disk failure message

  Scenario: Alerting about disk read failures before reaching the Welcome Screen
    Given a computer
    And I start the computer from DVD with network unplugged
    When Tails detects disk read failures
    Then I see a disk failure message on the splash screen

  Scenario: Alerting about graphics card failure before reaching the Welcome Screen
    Given a computer
    And I start the computer from DVD with network unplugged and an unsupported graphics card
    Then I see a graphics card failure message on the splash screen
