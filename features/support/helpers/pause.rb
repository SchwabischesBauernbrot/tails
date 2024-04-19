require 'binding_of_caller'
require 'pry'

# rubocop:disable Metrics/CyclomaticComplexity
def our_caller_binding?(binding)
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
  # When interactively debugging we rarely are trying to debug
  # various helper methods but rather the context they are called
  # from, so we exempt them below.
  case source_location
  when __FILE__
    # Everything in this file is ignored, otherwise we would always
    # return the binding in this method, find_our_caller_binding() or
    # pause().
    false
  when "#{GIT_DIR}/features/step_definitions/snapshots.rb"
    # We ignore the snapshot machinery, otherwise when an error occurs
    # during reach_checkpoint() or one of the generated snapshot steps
    # we end up with those not very interesting contexts.
    false
  when "#{GIT_DIR}/features/support/helpers/dogtail.rb"
    false
  when "#{GIT_DIR}/features/support/helpers/firewall_helper.rb"
    false
  when "#{GIT_DIR}/features/support/helpers/misc_helpers.rb"
    method != :assert_vmcommand_success && \
      method != :cmd_helper && \
      method != :retry_action && \
      method != :retry_tor && \
      method != :try_for
  when "#{GIT_DIR}/features/support/helpers/screen.rb"
    false
  when "#{GIT_DIR}/features/support/helpers/vm_helper.rb"
    method != :execute_successfully
  else
    true
  end
end
# rubocop:enable Metrics/CyclomaticComplexity

def find_our_caller_binding(bindings)
  bindings.find { |b| our_caller_binding?(b) }
end

def pause(message = 'Paused', exception: nil, quiet: false)
  notify_user(message)
  $stderr.puts
  warn message
  # Ring the ASCII bell for a helpful notification in most terminal
  # emulators.
  $stdout.write "\a"
  $stderr.puts
  loop do
    warn 'Return/q: Continue; d: Debugging REPL'
    c = $stdin.getch
    case c
    when 'q', "\r", 3.chr # Ctrl+C => 3
      return
    when 'd'
      if exception.nil?
        # pause() was manually called so our caller is in the current
        # binding's stack of caller bindings, provided by the
        # binding_of_caller module.
        caller_bindings = binding.callers
      else
        # pause() was called for an exception caught by cucumber so
        # our caller is in the binding stack in the exception provided
        # by the bindex module.
        assert(config_bool('INTERACTIVE_DEBUGGING'))
        caller_bindings = exception.bindings
      end
      our_caller_binding = find_our_caller_binding(caller_bindings)
      if our_caller_binding.nil?
        warn "Warning: could not restore the failure's context"
        $stderr.puts
        quiet = true
        our_caller_binding = binding
      end
      our_caller_binding.pry(quiet:)
    end
  end
end

alias breakpoint pause
