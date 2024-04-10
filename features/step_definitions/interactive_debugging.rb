Given /^pause\(\) still works$/ do
  foo = 42
  pause
end

When /^I fail by raising$/ do
  e = RuntimeError.new("foo")
  foo = 42  # would be inaccessible if the creation binding is used
  raise e
end

When /^I fail by raising inside a code block$/ do
  foo = 42
  p = Proc.new do |x|
    e = RuntimeError.new("foo")
    bar = "this variable will be in scope"
    raise e
  end
  baz = "this variable will also be in scope"
  p.call(foo)
end

When /^I fail by raising inside a dynamically defined method$/ do
  foo = 42
  define_singleton_method(:bar) do |x|
    e = RuntimeError.new("foo")
    bar = "this variable will be in scope"
    raise e
  end
  baz = "this variable will also be in scope"
  bar(foo)
end

When /^I fail by asserting$/ do
  foo = 42
  assert_equal(0, foo)
end

When /^I fail by expecting$/ do
  foo = 42
  foo.should == 0
end

When /^I fail through division by zero$/ do
  foo = 42
  bar = foo/0
end

When /^I fail through some module$/ do
  foo = 42
  bar = IPAddr.new(foo)
end

When /^I fail by timeout$/ do
  foo = 42
  Timeout.timeout(0.1) do
    bar = "this variable will not be in scope"
    sleep foo
  end
end

When /^I fail through try_for$/ do
  foo = 42
  try_for(1, delay: 0.1) do
    bar = "this variable will not be in scope"
    assert_equal(0, foo)
  end
end

When /^I fail through retry_action$/ do
  foo = 42
  retry_action(10, delay: 0.1) do
    bar = "this variable will not be in scope"
    assert_equal(0, foo)
  end
end
