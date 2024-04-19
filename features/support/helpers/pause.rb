require 'debug_inspector'
require 'pry'

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
      breakpoint_binding = nil
      unless exception.nil?
        assert(config_bool('INTERACTIVE_DEBUGGING'))
        # Exceptions that were created/raise()ed with "magic" that
        # avoided our monkeypatches for the exception machinery might
        # not have @raise_binding and @initialize_binding defined.
        if defined?(exception.raise_binding) && \
           !exception.raise_binding.nil?
          breakpoint_binding = exception.raise_binding
        elsif defined?(exception.initialize_binding) && \
              !exception.initialize_binding.nil?
          breakpoint_binding = exception.initialize_binding
        else
          warn "Warning: could not restore the failure's context"
          $stderr.puts
          quiet = true
        end
      end
      breakpoint_binding ||= RubyVM::DebugInspector.find_our_caller_binding
      breakpoint_binding.pry(quiet:)
    end
  end
end

alias breakpoint pause
