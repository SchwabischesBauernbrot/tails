@product
Feature: I can report a bug with WhisperBack
  As a Tails user
  When I experience a bug in Tails
  I want to send a complete bug report to the Tails team

  # Anti-test: tails-debugging-info is not available to amnesia
  Scenario: The amnesia user cannot run tails-debugging-info as root
    Given I have started Tails from DVD without network and logged in
    Then running "sudo /usr/local/sbin/tails-debugging-info" as user "amnesia" fails

  Scenario: The Report an Error launcher opens WhisperBack
    Given I have started Tails from DVD without network and logged in
    When I open the Report an Error launcher on the desktop
    Then WhisperBack starts

  Scenario: WhisperBack has access to debugging information
    Given I have started Tails from DVD without network and logged in
    When I start "WhisperBack" via GNOME Activities Overview
    Then WhisperBack has debugging information
