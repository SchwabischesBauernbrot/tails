Given /^I (modify|restore) the "I do something" step$/ do |action|
  value = action == 'modify' ? 2 : 1
  path = "#{GIT_DIR}/features/step_definitions/test.rb"
  File.write(
    path,
    File.read(path).gsub(/^  @something = .*$/, "  @something = #{value}")
  )
end

When /^I do something$/ do
  @something = 1
  puts "@something ← #{@something}"
  nil
end

When /^I manually invoke step "([^"]*)" using step\(\)$/ do |step_pattern|
  puts "Invoking step: #{step_pattern}"
  step step_pattern
end

Then /^the previous step ran the (original|reloaded) code$/ do |code|
  expected_something = (code == 'original' ? 1 : 2)
  message = "@something is #{@something}, expected #{expected_something}"
  if expected_something != @something
    raise message
  end
  puts message
end
