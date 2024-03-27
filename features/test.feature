@source
Feature: test

Scenario: Redefining steps during a run
  Given I restore the "I do something" step
  When I do something
  Then the previous step ran the original code
  Given I modify the "I do something" step
  And I reload step definitions
  When I manually invoke step "I do something" using step()
  Then the previous step ran the reloaded code
  When I do something
  Then the previous step ran the reloaded code
  And I restore the "I do something" step
