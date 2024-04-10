@source
Feature: Interactive debugging with in the original failure's context

# These two are the only scenarios expected to pass

Scenario: pause() still works
  Given pause() still works

Scenario: the "I pause" step still works
  Given I pause

# All scenarios are expected to fail so we can see how
# --interactive-debugging works with different types of failures

Scenario: I fail by raising
  When I fail by raising

Scenario: I fail by raising inside a code block
  When I fail by raising inside a code block

Scenario: I fail by raising inside a dynamically defined method
  When I fail by raising inside a dynamically defined method

Scenario: I fail by asserting
  When I fail by asserting

Scenario: I fail by expecting
  When I fail by expecting

Scenario: I fail through division by zero
  When I fail through division by zero

Scenario: I fail through some module
  When I fail through some module

Scenario: I fail by timeout
  When I fail by timeout

Scenario: I fail through try_for
  When I fail through try_for

Scenario: I fail through retry_action
  When I fail through retry_action
