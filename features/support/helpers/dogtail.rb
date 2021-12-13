module Dogtail
  LEFT_CLICK = 1
  MIDDLE_CLICK = 2
  RIGHT_CLICK = 3

  private_constant :LEFT_CLICK
  private_constant :MIDDLE_CLICK
  private_constant :RIGHT_CLICK

  TREE_API_NODE_SEARCHES = [
    :button,
    :child,
    :childLabelled,
    :childNamed,
    :dialog,
    :menu,
    :menuItem,
    :panel,
    :tab,
    :textentry,
  ].freeze
  private_constant :TREE_API_NODE_SEARCHES

  TREE_API_NODE_SEARCH_FIELDS = [
    :labelee,
    :parent,
  ].freeze
  private_constant :TREE_API_NODE_SEARCH_FIELDS

  TREE_API_NODE_ACTIONS = [
    :click,
    :doubleClick,
    :grabFocus,
    :keyCombo,
    :point,
    :typeText,
  ].freeze
  private_constant :TREE_API_NODE_ACTIONS

  TREE_API_APP_SEARCHES = TREE_API_NODE_SEARCHES + [
    :dialog,
    :window,
  ]
  private_constant :TREE_API_APP_SEARCHES

  class Failure < StandardError
  end

  # We want to keep this class immutable so that handles always are
  # left intact when doing new (proxied) method calls.  This way we
  # can support stuff like:
  #
  #     app = Dogtail::Application.new('gedit')
  #     menu = app.menu('Menu')
  #     menu.click()
  #     menu.something_else()
  #     menu.click()
  #
  # i.e. the object referenced by `menu` is never modified by method
  # calls and can be used as expected.

  class Application
    @@node_counter ||= 0

    def initialize(app_name, **opts)
      @var = "node#{@@node_counter += 1}"
      @app_name = translate(app_name, **opts)
      @opts = opts
      @opts[:user] ||= LIVE_USER
      @find_code = "dogtail.tree.root.application('#{@app_name}')"
      init = [
        'import dogtail.config',
        'import dogtail.tree',
        'import dogtail.predicate',
        'import dogtail.rawinput',
        'dogtail.config.logDebugToFile = False',
        'dogtail.config.logDebugToStdOut = False',
        'dogtail.config.blinkOnActions = True',
        'dogtail.config.searchShowingOnly = True',
      ]
      code = [
        "#{@var} = #{@find_code}",
      ]
      run(code, init: init)
    end

    def to_s
      @var
    end

    def run(code, init: nil)
      if init
        init = init.join("\n") if init.class == Array
        c = RemoteShell::PythonCommand.new($vm, init, user: @opts[:user], debug_log: false)
        raise Failure, "The Dogtail init script raised: #{c.exception}" if c.failure?
      end
      code = code.join("\n") if code.class == Array
      c = RemoteShell::PythonCommand.new($vm, code, user: @opts[:user])
      raise Failure, "The Dogtail script raised: #{c.exception}" if c.failure?
      c
    end

    def child?(*args)
      !child(*args).nil?
    rescue StandardError
      false
    end

    def exist?
      run('dogtail.config.searchCutoffCount = 0')
      run(@find_code)
      true
    rescue StandardError
      false
    ensure
      run('dogtail.config.searchCutoffCount = 20')
    end

    def self.value_to_s(value)
      if value.nil?
        'None'
      elsif value == true
        'True'
      elsif value == false
        'False'
      elsif value.class == String
        # Since we use single-quote the string we have to escape any
        # occurrences inside.
        "'#{value.gsub("'", "\\\\'")}'"
      elsif [Integer, Float].include?(value.class)
        v.to_s
      else
        raise "#{name} does not know how to handle argument type " \
              "'#{value.class}'"
      end
    end

    # Generates a Python-style parameter list from `args`. If the last
    # element of `args` is a Hash, it's used as Python's kwargs dict.
    # In the end, the resulting string should be possible to copy-paste
    # into the parentheses of a Python function call.
    # Example: [42, {:foo => 'bar'}] => "42, foo = 'bar'"
    def self.args_to_s(args)
      return '' if args.empty?

      args_list = args
      args_hash = nil
      if args_list.class == Array && args_list.last.class == Hash
        *args_list, args_hash = args_list
      end
      args_hash[:showingOnly] = true unless args_hash.key?(:showingOnly)
      (
        (if args_list.nil?
           []
         else
           args_list.map { |e| value_to_s(e) }
         end
        ) +
        (if args_hash.nil?
           []
         else
           args_hash.map { |k, v| "#{k}=#{value_to_s(v)}" }
         end
        )
      ).join(', ')
    end

    # Equivalent to the Tree API's Node.findChildren(), with the
    # arguments constructing a GenericPredicate to use as parameter.
    def children(*args)
      non_predicates = [:recursive, :showingOnly]
      findChildren_opts_hash = {}
      if args.last.class == Hash
        args_hash = args.last
        non_predicates.each do |opt|
          if args_hash.key?(opt)
            findChildren_opts_hash[opt] = args_hash[opt]
            args_hash.delete(opt)
          end
        end
      end
      findChildren_opts = ''
      unless findChildren_opts_hash.empty?
        findChildren_opts = ', ' + self.class.args_to_s([findChildren_opts_hash])
      end
      predicate_opts = self.class.args_to_s(args)
      nodes_var = "nodes#{@@node_counter += 1}"
      find_script_lines = [
        "#{nodes_var} = #{@var}.findChildren(" \
        'dogtail.predicate.GenericPredicate(' \
        "#{predicate_opts})#{findChildren_opts})",
        "print(len(#{nodes_var}))",
      ]
      size = run(find_script_lines).stdout.chomp.to_i
      size.times.map do |i|
        Node.new("#{nodes_var}[#{i}]", **@opts)
      end
    end

    def get_field(key)
      run("print(#{@var}.#{key})").stdout.chomp
    end

    def set_field(key, value)
      run("#{@var}.#{key} = #{self.class.value_to_s(value)}")
    end

    def combovalue
      get_field('combovalue')
    end

    def combovalue=(value)
      set_field('combovalue', value)
    end

    def checked
      get_field('checked') == 'True'
    end

    def text
      get_field('text')
    end

    def text=(value)
      set_field('text', value)
    end

    def name
      get_field('name')
    end

    def roleName
      get_field('roleName')
    end

    def showing
      get_field('showing') == 'True'
    end

    # Note: pressKey and typeText are global Dogtail actions,
    # which should probably live
    # elsewhere than in our Application class, but currently we lack
    # the infrastructure to do that: the Ruby plumbing that generates
    # and runs Python code lives in the Application class.
    def pressKey(key)
      # Dogtail will prefix the value of key with 'KEY_'
      # and the result must be a valid Gdk key symbol such as Gdk.KEY_Down
      run("dogtail.rawinput.pressKey('#{key}')")
    end

    def typeText(text)
      run("dogtail.rawinput.typeText('#{text}')")
    end

    TREE_API_APP_SEARCHES.each do |method|
      define_method(method) do |*args|
        args[0] = translate(args[0], **@opts) if args[0].class == String
        args_str = self.class.args_to_s(args)
        method_call = "#{method}(#{args_str})"
        Node.new("#{@var}.#{method_call}", **@opts)
      end
    end

    TREE_API_NODE_SEARCH_FIELDS.each do |field|
      define_method(field) do
        Node.new("#{@var}.#{field}", **@opts)
      end
    end

    # Override the `child` method to add support for regex matching of
    # node names, which offers much greater flexibility.
    def override_child(pattern, **opts)
      # Ruby < 2.7 handles arguments vs option hash differently, so we
      # need a workaround.
      # XXX:Bullseye: drop this workaround once we run on Ruby >=2.7.
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7')
        if pattern.class == Hash
          opts.merge!(pattern)
          pattern = nil
        end
      end
      if pattern.instance_of?(Regexp)
        retries = 20
        if opts.key?(:retry)
          retries = 1 unless opts[:retry]
          opts.delete(:retry)
        end
        child = nil
        retry_action(retries, delay: 1, exception: Failure, msg: "Found no child matching /#{pattern.source}/") do
          child = children(**opts).find do |c|
            pattern.match(c.name)
          end
          assert_not_nil(child)
        end
        child
      else
        original_child_method(pattern, **opts)
      end
    end

    alias original_child_method child
    alias child override_child
  end

  class Node < Application
    def initialize(expr, **opts)
      @expr = expr
      @opts = opts
      @opts[:user] ||= LIVE_USER
      @find_code = expr
      @var = "node#{@@node_counter += 1}"
      run("#{@var} = #{@find_code}")
    end

    TREE_API_NODE_ACTIONS.each do |method|
      define_method(method) do |*args|
        args_str = self.class.args_to_s(args)
        method_call = "#{method}(#{args_str})"
        run("#{@var}.#{method_call}")
      end
    end

    def right_click
      method_call = "click(button=#{RIGHT_CLICK})"
      run("#{@var}.#{method_call}")
    end
  end
end
