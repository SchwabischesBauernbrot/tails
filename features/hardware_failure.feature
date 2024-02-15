@product
Feature: Hardware failures
  As a Tails user
  when the USB stick has hardware failures
  I want to to see a message.

  Scenario: Alerting about disk read failures in GNOME
    Given I have started Tails from DVD without network and logged in
    When Tails detects disk read failures
    Then I see a Disk Failure Message
    Then I can open the Hardware Failure documentation from the Disk Failure Message
