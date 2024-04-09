# rubocop:disable Style/Documentation

# These methods don't have to be monkeypatched into this class, but
# they fit the theme so why not?
class RubyVM::DebugInspector
  # Returns true iff exception is raised by frame_binding(i) when i
  # doesn't refer to an existing frame.
  def self.invalid_frame_binding?(exception)
    ret = exception.instance_of?(ArgumentError) && \
          exception.message == 'no such frame'
    # Some exceptions don't define .backtrace, and some leave it as
    # nil.
    if defined?(exception.backtrace) && \
       exception.backtrace.instance_of?(Array) && \
       exception.backtrace.size.positive?
      ret &&= exception.backtrace.first.end_with?(":in `frame_binding'")
    end
    ret
  end

  # Checks if a binding is in "our" code, which means actual test
  # suite code so definitely step definitions and also _most_ support
  # code, but excluding the exception machinery code we monkeypatch,
  # and our helpers like try_for() or pause() where we are interested
  # in their callers.
  # rubocop:disable Metrics/CyclomaticComplexity
  def self.our_caller_binding?(binding)
    return false if binding.nil?

    source_location = binding.source_location&.first
    # There are "weird" bindings that do not have source locations,
    # probably some internal implementation detail of Ruby. We are
    # only interested in our code, not code living in modules we
    # import, or code we `include` (like Test::Unit::Assertions).
    if source_location.nil? || !source_location&.start_with?(GIT_DIR)
      return false
    end

    method = binding.eval('__method__')

    # We determine which bindings to return by matching against the
    # calling method's name, which could lead to false positives if we
    # ever define methods with the same name in other contexts
    # (e.g. in some class). Therefore we also guard by which file they
    # are defined in.
    case source_location
    when __FILE__ # this file
      # It's not this class method (or the methods in this module that
      # are implemented using this method) since we are interested in
      # the callers beyond those bindings.
      method != __method__.inspect && \
        method != :find_our_caller_binding && \
        # It's not in our monkeypatched raise() (below), otherwise
        # @raise_binding would always be the binding inside raise().
        method != :raise && \
        # It's not in our monkeypatched Exception constructor (below),
        # otherwise and @initialize_binding would always be the
        # binding inside that constructor.
        method != :initialize
    when "#{GIT_DIR}/features/support/helpers/misc_helpers.rb"
      # It's not in helpers like try_for(). When interactively
      # debugging we rarely are trying to debug those methods, but
      # rather the context they are called from, so we exempt them.
      method != :pause && \
        method != :try_for && \
        method != :retry_action
    when "#{GIT_DIR}/features/step_definitions/snapshots.rb"
      # It's not in the snapshot machinery, otherwise when an error
      # occurs during reach_checkpoint() or one of the generated
      # snapshot steps we end up with those not very interesting
      # contexts.
      false
    else
      true
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  # Iterates through the stack of bindings/contexts until our code is
  # found and returns that binding.
  def self.find_our_caller_binding
    RubyVM::DebugInspector.open do |inspector|
      (1..).each do |i|
        binding = inspector.frame_binding(i)
        return binding if our_caller_binding?(binding)
      end
    end
  rescue ArgumentError => e
    return if invalid_frame_binding?(e)

    raise e
  end
end

# In order for --interactive-debugging to be able to start pry in the
# context of the failure of the scenario we need we need to solve this
# problem: cucumber catches the exception causing the test to fail and
# continues running, so the binding where it was raised is
# inaccessible when the interactive debugging is triggered in the
# scenario's After hook. We solve that by saving the binding into the
# exception (which we have access to in the After hook) through
# monkeypatching the exception machinery.
#
# However, there is a lot of magic going on behind the scenes which
# makes this difficult to do in a way so all kinds of exceptions are
# affected: some exceptions are raised without calling the
# monkeypatched `raise()`, e.g. when FFI is used to raise and
# exception; also, cucumber evaluates step definitions in a way so the
# Exception constructor monkeypatch doesn't do what it's supposed to
# constructor. Luckily it seems no exception has both these issues, so
# we do both.
#
# Let's note that there can be a difference between bindings when an
# exception is created vs when it is raised, e.g.:
#
#   e = RuntimeError.new("foo")
#   foo = 42
#   raise e
#
# In the binding at the exception creation `foo` is out of scope, and
# the error technically hasn't occurred yet, so we will always prefer
# the raise() binding. BTW, our monkeypatching handles the above case
# just fine, and in practice it actually seems like the "magic" cases
# when a raise() binding cannot be found are situation when this
# distinction is irrelevant, because we also ignore bindings outside
# of our code (so we don't end up where the exception is raised inside
# some module we import).
if config_bool('INTERACTIVE_DEBUGGING')
  class Exception
    attr_reader :initialize_binding
    attr_accessor :raise_binding

    alias __original_initialize initialize
    def initialize(*args, **opts)
      __original_initialize(*args, **opts)
      @raise_binding = nil
      @initialize_binding = nil
      # We must carefully exclude any exception that is thrown (even
      # if caught/rescued) below, otherwise we end up in an infinite
      # loop.
      return if RubyVM::DebugInspector.invalid_frame_binding?(self)

      @initialize_binding = RubyVM::DebugInspector.find_our_caller_binding
    end
  end

  alias __original_raise raise
  def raise(*args, **opts)
    exception = args.first
    if defined?(exception.raise_binding)
      # Cucumber re-raises during step evaluation, and we want the
      # original binding.
      if exception.raise_binding.nil?
        exception.raise_binding = RubyVM::DebugInspector.find_our_caller_binding
      end
    else
      # Let's patch the _instance_ for Exceptions that were created
      # with "magic" that avoided the monkeypatched Exception
      # constructor that defined @raise_binding.
      raise_binding = RubyVM::DebugInspector.find_our_caller_binding
      exception.define_singleton_method(:raise_binding) do
        raise_binding
      end
    end
    __original_raise(*args, **opts)
  end
end

# rubocop:enable Style/Documentation
