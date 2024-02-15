@product
Feature: Hardware failures
  As a Tails user
  when hardware failures are detected
  I want to to see a message.

  Scenario: Alerting about disk read failures in GNOME
    Given I have started Tails from DVD without network and logged in
    When Tails detects disk read failures
    Then I see a Disk Failure Message
    Then I can open the Hardware Failure documentation from the Disk Failure Message

  Scenario: Alerting about disk read failures before reaching the Welcome Screen
    Given I start the computer from DVD with network unplugged
    When Tails detects disk read failures
    Then I see a Disk Failure Message on the splash screen

  Scenario: Alerting about Graphic card Failure before reaching the Welcome Screen
    Given I start the computer from DVD with network unplugged and an unsupported Graphic card
    Then I see a Graphic card Failure Message on the splash screen
