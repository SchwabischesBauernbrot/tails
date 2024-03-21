Given /^I reload the code so the step below is modified$/ do
  modified_code = <<-RUBY
When /^I do something$/ do
  @something = 2
  puts "@something ← \#{@something}"
  nil
end
RUBY
  Tempfile.create(['test', '.rb']) do |f|
    puts "Loading file with step redefinition: #{f.path}"
    File.write(f.path, modified_code)
    # @__cucumber_runtime.support_code.load_file(f.path)
    load f.path
  end
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
