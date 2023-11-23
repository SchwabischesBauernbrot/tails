@product @check_tor_leaks @slow

Feature: Snapshot tests

  Scenario: Create a snapshot
    Given I have started Tails without network from a USB drive without a persistent partition and stopped at Tails Greeter's login screen
    When I shutdown Tails and wait for the computer to power off
    And I start Tails from USB drive "__internal" with network unplugged

  Scenario: Restore a snapshot
    Given I have started Tails without network from a USB drive without a persistent partition and stopped at Tails Greeter's login screen
    When I shutdown Tails and wait for the computer to power off
