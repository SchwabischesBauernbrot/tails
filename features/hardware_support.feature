@product
Feature: Hardware support
  In order to understand why Tails does not work
  As someone using a computer that is not supported by Tails
  I want to be informed that my hardware is not supported

  Scenario: Alerting about unsupported graphics card before reaching the Welcome Screen
    Given a computer
    And I start the computer from DVD with network unplugged and an unsupported graphics card
    Then I see a graphics card failure message on the splash screen
