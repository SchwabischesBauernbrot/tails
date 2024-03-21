@source
Feature: test

Scenario: Redefining steps during a run
  When I do something
  Then the previous step ran the original code
  Given I reload the code so the step below is modified
  When I manually invoke step "I do something" using step()
  Then the previous step ran the reloaded code
  When I do something
  Then the previous step ran the reloaded code
