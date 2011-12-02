class Slop
  include Enumerable

  # Current version String
  VERSION = '2.4.0'

  # Slops standard Error class. All exception classes should
  # inherit from this class
  class Error < StandardError; end

  # Raised when an option expects an argument and none is given
  class MissingArgumentError < Error; end

  # Raised when an option is required but not given
  class MissingOptionError < Error; end

  # Raised when an option specifies the `:match` attribute and this
  # options argument does not match this regexp
  class InvalidArgumentError < Error; end

  # Raised when the `:strict` option is enabled and an unknown
  # or unspecified option is used
  class InvalidOptionError < Error; end

  # Each option specified in `Slop#opt` creates an instance of this class
  class Option < Struct.new(:short_flag, :long_flag, :description, :tail, :match, :help, :required, :forced, :count)

    # slop        - The Slop object this option belongs to.
    # short       - The short flag String or Symbol representing this option.
    # long        - The long flag String or Symbol representing this option.
    # description - A description String.
    # argument    - True if this option takes an argument, false otherwise.
    #
    # options - Hash configuration options:
    #           :optional  - True if this option takes an optional argument.
    #           :argument  - True if this option takes an madatory argument.
    #           :default   - The default value for this option when none is given.
    #           :callback  - An callback object which responds to call.
    #           :delimiter - A delimiter String when processing argument as a list.
    #           :limit     - An Integer limit when processing argument as a list.
    #           :tail      - True to group this option at the bottom of the help.
    #           :match     - A Regexp this options argument should match.
    #           :unless    - Omit execution of this options callback if the supplied
    #                        String or Symbol exists as another option.
    #           :help      - True if you want to display this option in the help
    #                        text. If a String it will be appended to the help.
    #           :required  - When true this option is considered mandatory. That is,
    #                        when not supplied, Slop will raise an exception.
    def initialize(slop, short, long, description, argument, options, &blk)
      @slop = slop

      self.short_flag = short
      self.long_flag = long
      self.description = description

      @argument = argument
      @options = options

      self.tail = @options[:tail]
      self.match = @options[:match]
      self.help = @options.fetch(:help, true)
      self.required = @options[:required]

      @delimiter = @options.fetch(:delimiter, ',')
      @limit = @options.fetch(:limit, 0)
      @argument_type = @options[:as].to_s.downcase
      @argument_value = nil

      self.forced = false
      self.count = 0

      @callback = block_given? ? blk : @options[:callback]

      if long_flag && long_flag.size > @slop.longest_flag
        @slop.longest_flag = long_flag.size
        @slop.longest_flag += help.size if help.respond_to?(:to_str)
      end
    end

    # Returns true if this option expects an argument.
    def expects_argument?
      @argument || @options[:argument] || @options[:optional] == false
    end

    # Returns true if this option accepts an optional argument.
    def accepts_optional_argument?
      @options[:optional] || @options[:optional_argument]
    end

    # Returns either the long or short flag String for this option.
    def key
      long_flag || short_flag
    end

    # Set this options argument value. If this options argument type is expected
    # to be an Array, this method will split the value and concat elements into
    # the original argument value.
    #
    # value - The value to set this options argument to.
    def argument_value=(value)
      if @argument_type == 'array'
        @argument_value ||= []

        if value.respond_to?(:to_str)
          @argument_value.concat value.split(@delimiter, @limit)
        end
      else
        @argument_value = value
      end
    end

    # Returns the argument value Object after it's been cast according to
    #   the :as option.
    def argument_value
      return @argument_value if forced
      # Check for count first to prefer 0 over nil
      return count if @argument_type == 'count'

      value = @argument_value || @options[:default]
      return if value.nil?

      case @argument_type
      when 'array'; @argument_value unless !expects_argument?
      when 'range'; value_to_range value unless !expects_argument?
      when 'float'; value.to_s.to_f unless !expects_argument?
      when 'string', 'str';  value.to_s unless !expects_argument?
      when 'symbol', 'sym';  value.to_s.to_sym unless !expects_argument?
      when 'integer', 'int'; value.to_s.to_i unless !expects_argument?
      else
        value
      end
    end

    # Force an argument value, used when the desired argument value
    # is negative (false or nil).
    #
    # value - The Object to force this argument value with.
    def force_argument_value(value)
      @argument_value = value
      self.forced = true
    end

    # Execute the block or callback object associated with this Option.
    #
    # obj - The Object to be sent to the call() method.
    def call(obj=nil)
      @callback.call(obj) if @callback.respond_to?(:call)
    end

    # items - The original Array of objects passed to Slop.new().
    #
    # Returns true if this options :unless argument exists inside items
    def omit_exec?(items)
      items.any? do |item|
        item.to_s.sub(/\A--?/, '') == @options[:unless].to_s.sub(/\A--?/, '')
      end
    end

    # This option in a nice pretty string, including a short flag, long
    # flag, and description (if they exist).
    #
    # Returns the String help text for this option.
    def to_s
      out = "    "
      out += short_flag ? "-#{short_flag}, " : ' ' * 4

      if long_flag
        out += "--#{long_flag}"
        if help.respond_to? :to_str
          out += " #{help}"
          size = long_flag.size + help.size + 1
        else
          size = long_flag.size
        end
        diff = @slop.longest_flag - size
        out += " " * (diff + 6)
      else
        out += " " * (@slop.longest_flag + 8)
      end

      "#{out}#{description}"
    end

    # Returns the String inspection text.
    def inspect
      "#<Slop::Option short_flag=#{short_flag.inspect} " +
      "long_flag=#{long_flag.inspect} argument=#{@argument.inspect} " +
      "description=#{description.inspect}>"
    end

    private

    # Extracts a range from a String.
    #
    # value - The String to be extracted.
    #
    # Returns a Range object if one could be extracted.
    def value_to_range(value)
      case value.to_s
      when /\A(-?\d+?)(\.\.\.?|-|,)(-?\d+)\z/
        Range.new($1.to_i, $3.to_i, $2 == '...')
      when /\A-?\d+\z/
        value.to_i
      else
        value
      end
    end

  end

  # Used to hold a list of Option objects. This class inherits from Array
  # and overwrites `Array#[]` so we can fetch Option objects via their
  # short or long flags
  class Options < Array

    # Fetch an Option object. This method overrides Array#[] to provide
    # a nicer interface for fetching options via their short or long flag.
    # The reason we don't use a Hash here is because an option cannot be
    # identified by a single label. Instead this method tests against
    # a short flag first, followed by a long flag. When passing this
    # method an Integer, it will work as an Array usually would, fetching
    # the Slop::Option at this index.
    #
    # flag - The short/long flag Object representing this option.
    #
    # Examples
    #
    #   opts = Slop.parse { on :v, "Verbose mode" }
    #   opts.options[:v] #=> Option
    #   opts.options[:v].description #=> "Verbose mode"
    #
    # Returns The Option associated with this flag.
    def [](flag)
      if flag.is_a? Integer
        super
      else
        find do |option|
          [option.short_flag, option.long_flag].include? flag.to_s
        end
      end
    end
  end

  # Parses the items from a CLI format into a friendly object.
  #
  # items   - The Array of items to parse.
  # options - The Hash of configuration options.
  #
  # Example
  #
  #  opts = Slops.parse do
  #    on :v, :verbose, 'Enable verbose mode'
  #    on :n, :name,    'Your name'
  #    on :a, :age,     'Your age'
  #  end
  #
  # Returns a new instance of Slop.
  def self.parse(items=ARGV, options={}, &block)
    initialize_and_parse items, false, options, &block
  end

  # Identical to Slop.parse, but removes parsed options from the
  # original Array.
  #
  # Returns a new instance of Slop.
  def self.parse!(items=ARGV, options={}, &block)
    initialize_and_parse items, true, options, &block
  end

  # Build options from an optspec string.
  #
  # optspec - The option spec String to parse.
  # options - An Array of options to forward to Slop.new().
  #
  # Returns A new instance of Slop.
  def self.optspec(optspec, *options)
    if optspec[/^--+$/]
      banner, optspec = optspec.split(/^--+$/, 2)
    end

    lines = optspec.split("\n").reject(&:empty?)
    opts  = Slop.new(banner, *options)

    lines.each do |line|
      opt, description = line.split(' ', 2)
      short, long = opt.split(',').map { |s| s.sub(/\A--?/, '') }
      argument = long && long[-1] == ?$
      long.sub!(/\=$/, '') if argument
      opts.on short, long, description, argument
    end

    opts
  end

  # Returns a Hash of configuration options.
  attr_reader :options

  # Returns a Hash of commands and Slop instances.
  attr_reader :commands

  # Set the banner String.
  attr_writer :banner

  # Set the summary text String.
  attr_writer :summary

  # Set the description text String.
  attr_writer :description

  # Returns The Integer length of the longest flag slop knows of.
  attr_accessor :longest_flag

  # Returns An Array of aliases this command uses.
  attr_accessor :aliases

  # opts - An Array or Hash of configuration options:
  #        :help                 - Automatically add the help Option.
  #        :strict               - Force exception raising when an option is not
  #                                found (default: false).
  #        :multiple_switches    - When true, allow -abc to be processed as
  #                                individual options (default: true)
  #        :banner               - The banner String
  #        :on_empty             - An Object responding to call() for callback when
  #                                there are no arguments or options to parse.
  #        :io                   - The IO object to use for output (default: $stderr).
  #        :exit_on_help         - When false and partnered with the :help option
  #                                Slop will not exit after help (default: true).
  #        :ignore_case          - Ignore options case (default: false).
  #        :on_noopts            - Callback trigger when no options are found.
  #        :autocreate           - Autocreate options based on parsed items.
  #        :arguments            - When true, all options will accept arguments (default: false)
  #        :aliases              - An Array of aliases when using commands (default: []).
  #        :completion           - When true, commands will be auto completed.
  def initialize(*opts, &block)
    sloptions = opts.last.is_a?(Hash) ? opts.pop : {}
    sloptions[:banner] = opts.shift if opts[0].respond_to?(:to_str)
    opts.each { |o| sloptions[o] = true }

    @options = Options.new
    @commands = {}
    @execution_block = nil

    @longest_flag = 0
    @invalid_options = []

    @banner = sloptions[:banner]
    @strict = sloptions[:strict]
    @ignore_case = sloptions[:ignore_case]
    @multiple_switches = sloptions.fetch(:multiple_switches, true)
    @autocreate = sloptions[:autocreate]
    @completion = sloptions.fetch(:completion, true)
    @arguments = sloptions[:arguments]
    @on_empty = sloptions[:on_empty]
    @io = sloptions.fetch(:io, $stderr)
    @on_noopts = sloptions[:on_noopts] || sloptions[:on_optionless]
    @sloptions = sloptions

    if block_given?
      block.arity == 1 ? yield(self) : instance_eval(&block)
    end

    if sloptions[:help]
      on :h, :help, 'Print this help message', :tail => true do
        @io.puts help
        exit unless sloptions[:exit_on_help] == false
      end
    end
  end

  # Set or return banner text.
  #
  # text - The String to set the banner text.
  #
  # Example
  #
  #   opts = Slop.parse do
  #     banner "Usage - ruby foo.rb [arguments]"
  #   end
  #
  # Returns The current banner String.
  def banner(text=nil)
    @banner = text if text
    @banner
  end

  # Set or return the summary.
  #
  # text - The String to set the summary text.
  #
  # Example
  #
  #   opts = Slop.parse do
  #     summary "do stuff with more stuff"
  #   end
  #
  # Returns The current summary String.
  def summary(text=nil)
    @summary = text if text
    @summary
  end

  # Set or return the description.
  #
  # text - The String to set the description text.
  #
  # Example
  #
  #   opts = Slop.parse do
  #     description "This command does a lot of stuff with other stuff."
  #   end
  #
  # Returns The current description String.
  def description(text=nil)
    @description = text if text
    @description
  end

  # Parse a list of options, leaving the original Array unchanged.
  #
  # items - An Array of items to parse.
  def parse(items=ARGV, &block)
    parse_items items, &block
  end

  # Parse a list of options, removing parsed options from the original Array.
  #
  # items - An Array of items to parse.
  def parse!(items=ARGV, &block)
    parse_items items, true, &block
  end

  # Enumerable interface.
  def each(&block)
    @options.each(&block)
  end

  # key - Option Symbol.
  #
  # Example
  #
  #   opts[:name] #=> "Emily"
  #   opts.get(:name) #=> "Emily"
  #
  # Returns the Object associated with that option. If an
  #   option doesn't exist, a command will instead be searched for.
  def [](key)
    option = @options[key]
    option ? option.argument_value : @commands[key]
  end
  alias get []

  # Specify an option with a short or long version, description and type.
  #
  # args - An Array of Objects to send to Option.new():
  #   short_flag  - Short flag for this option.
  #   long_flag   - Long flag for this option.
  #   description - Description text String.
  #   argument    - True if this option takes an argument.
  #   options     - Any extra configuration options (optional).
  #
  # Example
  #
  #   opts = Slop.parse do
  #     on :n, :name, 'Your username', true # Required argument
  #     on :a, :age,  'Your age (optional)', :optional => true
  #     on :g, :gender, 'Your gender', :optional => false
  #     on :V, :verbose, 'Run in verbose mode', :default => true
  #     on :P, :people, 'Your friends', true, :as => Array
  #     on :h, :help, 'Print this help screen' do
  #       puts help
  #     end
  #   end
  #
  # Returns a new Slop::Option instance.
  def option(*args, &block)
    options = args.last.is_a?(Hash) ? args.pop : {}
    short, long, desc, arg, extras = clean_options(args)

    options.merge!(extras)
    options[:argument] = true if @sloptions[:all_accept_arguments]

    option = Option.new(self, short, long, desc, arg, options, &block)
    @options << option

    option
  end
  alias opt option
  alias on option

  # Namespace options depending on what command is executed.
  #
  # label   - The Symbol or String label representing this command.
  # options - A Hash of options to pass to Slop.new().
  #
  # Example
  #
  #   opts = Slop.new do
  #     command :create do
  #       on :v, :verbose
  #     end
  #   end
  #
  #   # ARGV is `create -v`
  #   opts.commands[:create].verbose? #=> true
  #
  # Returns a new instance of Slop namespaced to this label.
  # Raises ArgumentError if this command already exists.
  def command(label, options={}, &block)
    if @commands.key?(label)
      raise ArgumentError, "command `#{label}` already exists"
    end

    slop = Slop.new @sloptions.merge(options)
    slop.aliases = Array(options.delete(:aliases) || options.delete(:alias))
    @commands[label] = slop

    slop.aliases.each { |a| @commands[a] = @commands[label] }

    if block_given?
      block.arity == 1 ? yield(slop) : slop.instance_eval(&block)
    end

    slop
  end

  # Trigger an event when Slop has no values to parse.
  #
  # obj - An option object which responds to call() to be triggered when there are
  #       no options or arguments to parse.
  #
  # Example
  #
  #   Slop.parse do
  #     on_empty { puts 'No argument given!' }
  #   end
  def on_empty(obj=nil, &block)
    @on_empty ||= (obj || block)
  end
  alias on_empty= on_empty

  # Trigger an event when the arguments contain no options.
  #
  # obj - An option object which responds to call() to be triggered when there are
  #       no options to parse.
  #
  # Example
  #
  #   Slop.parse do
  #     on_noopts { puts 'No options here!' }
  #   end
  def on_noopts(obj=nil, &block)
    @on_noopts ||= (obj || block)
  end
  alias on_optionless on_noopts

  # Add an execution block (for commands).
  #
  # Example
  #
  #   opts = Slop.new do
  #     command :foo do
  #       on :v, :verbose
  #
  #       execute { |o| p o.verbose? }
  #     end
  #   end
  #   opts.parse %w[foo --verbose] #=> true
  #
  # args - The Array of arguments to send to this command.
  def execute(args=[], &block)
    if block_given?
      @execution_block = block
    elsif @execution_block.respond_to?(:call)
      @execution_block.call(self, args)
    end
  end

  # Fetch the parsed list as a hash.
  #
  # symbols - When true, keys will be symbols. Strings otherwise.
  #
  # Example
  #
  #   opts.to_hash #=> { :name => 'Emily' }
  #
  #   # strings!
  #   opts.to_hash(false) #=> { 'name' => 'Emily' }
  #
  # Returns a new Hash with parsed items.
  def to_hash(symbols=true)
    @options.reduce({}) do |hsh, option|
      key = option.key
      key = key.to_sym if symbols
      hsh[key] = option.argument_value
      hsh
    end
  end
  alias to_h to_hash

  # Turn this options keys and values into a struct.
  #
  # name - The String or Symbol name of this class.
  #
  # Examples
  #
  #   opts = Slop.new do
  #     on :n, :name, 'Persons name', true
  #     on :a, :age, 'Persons age', true, :as => :int
  #     on :s, :sex, 'Persons sex m/f', true, :match => /^[mf]$/
  #     on :A, :admin, 'Enable admin mode'
  #   end
  #
  #   opts.parse %w[ --name Lee --age 22 -s m --admin ]
  #
  #   person = opts.to_struct("Person")
  #   person.class  #=> Struct::Person
  #   person.name   #=> 'Lee'
  #   person.age    #=> 22
  #   person.sex    #=> m
  #   person.admin  #=> true
  #
  # Returns The new class, or nil if there are no options.
  def to_struct(name=nil)
    hash = to_hash
    Struct.new(name, *hash.keys).new(*hash.values) unless hash.empty?
  end

  # Fetch a list of options which were missing from the parsed list.
  #
  # Examples
  #
  #   opts = Slop.new do
  #     on :n, :name, 'Your name', true
  #     on :p, :password, 'Your password', true
  #     on :A, 'Use auth?'
  #   end
  #
  #   opts.parse %w[ --name Lee ]
  #   opts.missing #=> ['password', 'a']
  #
  # Returns An Array of options missing from the parsed string.
  def missing
    @options.select { |opt| not present?(opt.key) }.map(&:key)
  end

  # Allows you to check whether an option was specified in the parsed list.
  #
  # Examples
  #
  #   #== ruby foo.rb -v
  #   opts.verbose? #=> true
  #   opts.name?    #=> false
  #
  # Returns true if this option is present, false otherwise.
  def method_missing(meth, *args, &block)
    meth = meth.to_s
    if meth[-1] == ??
      present?(meth.chop)
    else
      super
    end
  end

  # Override this method so we can check if an option? method exists.
  def respond_to?(method)
    method = method.to_s
    if method[-1] == ?? and @options.any? { |o| o.key == method.chop }
      true
    else
      super
    end
  end

  # Check if an option is specified in the parsed list. Does the same as option?()
  # but a convenience method for unacceptable method names.
  #
  # option_names - A variable number of String or Symbol options to check.
  #
  # Returns true if these options are present, false otherwise.
  def present?(*option_names)
    option_names.all? { |opt| @options[opt] && @options[opt].count > 0 }
  end

  # Fetch the banner followed by available options listed on the next line.
  #
  # Examples
  #
  #  opts = Slop.parse do
  #    banner "Usage - ruby foo.rb [arguments]"
  #    on :v, :verbose, "Enable verbose mode"
  #  end
  #  puts opts
  #
  # Returns the String help text.
  def to_s
    parts = []

    parts << banner if banner
    parts << summary if summary
    parts << wrap_and_indent(description, 80, 4) if description

    if options.size > 0
      parts << "options:"

      heads = @options.reject(&:tail)
      tails = @options.select(&:tail)
      all = (heads + tails).select(&:help)

      parts << all.map(&:to_s).join("\n")
    end

    parts.join("\n\n")
  end
  alias help to_s

  # Returns a String with options and configuration settings revealed.
  def inspect
    "#<Slop config_options=#{@sloptions.inspect}\n  " +
    options.map(&:inspect).join("\n  ") + "\n>"
  end

  private

  class << self
    private

    def initialize_and_parse(items, delete, options, &block)
      if items.is_a?(Hash) && options.empty?
        options = items
        items = ARGV
      end

      slop = new(options, &block)
      delete ? slop.parse!(items) : slop.parse(items)
      slop
    end
  end

  # Internal: traverse through the list of items sent to parse() or parse!() and
  # attempt to do the following:
  #
  # * Find an option object
  # * Assign an argument to this option
  # * Validate an option and/or argument depending on configuration options
  # * Remove non-parsed items if `delete` is true
  # * Yield any non-options to the block (if one is given)
  def parse_items(items, delete=false, &block)
    if items.empty? and @on_empty.respond_to?(:call)
      @on_empty.call self
      return items
    elsif not items.any? {|i| i.to_s[/\A--?/] } and @on_noopts.respond_to?(:call)
      @on_noopts.call self
      return items
    elsif execute_command(items, delete)
      return items
    end

    trash = []
    ignore_all = false

    items.each_with_index do |item, index|
      item = item.to_s
      flag = item.sub(/\A--?/, '')

      if item == '--'
        trash << index
        ignore_all = true
      end

      next if ignore_all
      autocreate(flag, index, items) if @autocreate
      option, argument = extract_option(item, flag)

      if @multiple_switches and item[/\A-[^-]/] and not option
        trash << index
        next
      end

      if option
        option.count += 1 unless item[/\A--no-/]
        trash << index
        next if option.forced
        option.argument_value = true

        if option.expects_argument? or option.accepts_optional_argument?
          argument ||= items.at(index + 1)
          trash << index + 1

          if not option.accepts_optional_argument? and argument =~ /\A--?[a-zA-Z][a-zA-Z0-9_-]*\z/
            raise MissingArgumentError, "'#{option.key}' expects an argument, none given"
          end

          if argument
            if option.match and not argument.match(option.match)
              raise InvalidArgumentError, "'#{argument}' does not match #{option.match.inspect}"
            end

            option.argument_value = argument
            option.call option.argument_value unless option.omit_exec?(items)
          else
            option.argument_value = nil
            check_optional_argument!(option, flag)
          end
        else
          option.call unless option.omit_exec?(items)
        end
      else
        @invalid_options << flag if item[/\A--?/] and @strict
        block.call(item) if block_given? and not trash.include?(index)
      end
    end

    items.reject!.with_index { |o, i| trash.include?(i) } if delete
    raise_if_invalid_options!
    raise_if_missing_required_options!(items)
    items
  end

  def check_optional_argument!(option, flag)
    if option.accepts_optional_argument?
      option.call
    else
      raise MissingArgumentError, "'#{flag}' expects an argument, none given"
    end
  end

  def raise_if_invalid_options!
    return if not @strict or @invalid_options.empty?
    message = "Unknown option#{'s' if @invalid_options.size > 1}"
    message << ' -- ' << @invalid_options.map { |o| "'#{o}'" }.join(', ')
    raise InvalidOptionError, message
  end

  def raise_if_missing_required_options!(items)
    @options.select(&:required).each do |o|
      unless items.select {|i| i[/\A--?/] }.any? {|i| i.to_s.sub(/\A--?/, '') == o.key }
        raise MissingOptionError, "Expected option `#{o.key}` is required"
      end
    end
  end

  # if multiple_switches is enabled, this method filters through an items
  # characters and attempts to find an Option object for each flag.
  #
  # Raises if a flag expects an argument or strict mode is enabled and a
  # flag was not found
  def enable_multiple_switches(item)
    item[1..-1].each_char do |switch|
      option = @options[switch]

      if option
        if option.expects_argument?
          raise MissingArgumentError, "'-#{switch}' expects an argument, used in multiple_switch context"
        end

        option.argument_value = true
        option.count += 1
      else
        raise InvalidOptionError, "Unknown option '-#{switch}'" if @strict
      end
    end
  end

  def wrap_and_indent(string, width, indentation)
    string.lines.map do |paragraph|
      lines = []
      line = ''

      paragraph.split(/\s/).each do |word|
        if (line + ' ' + word).length >= width
          lines << line
          line = ''
        end

        line << (line == '' ? '' : ' ' ) + word
      end
      lines << line

      lines.map { |l| ' ' * indentation + l }.join("\n")
    end.join("\n")
  end

  # attempt to extract an option from an argument, this method allows us
  # to parse things like 'foo=bar' and '--no-value' for negative values
  # returns an array of the Option object and an argument if one was found
  def extract_option(item, flag)
    if item[0, 1] == '-'
      option = @options[flag]
      option ||= @options[flag.downcase] if @ignore_case
    end

    unless option
      case item
      when /\A-[^-]/
        if @multiple_switches
          enable_multiple_switches(item)
        else
          flag, argument = flag.split('', 2)
          option = @options[flag]
        end
      when /\A--([^=]+)=(.+)\z/
        option, argument = @options[$1], $2
      when /\A--no-(.+)\z/
        option = @options[$1]
        option.force_argument_value(false) if option
      end
    end

    [option, argument]
  end

  # attempt to execute a command if one exists, returns a positive (tru-ish)
  # result if the command was found and executed. If completion is enabled
  # and a flag is found to be ambiguous, this method prints an error message
  # to the @io object informing the user
  def execute_command(items, delete)
    str = items[0]

    if str
      command = @commands.keys.find { |c| c.to_s == str.to_s }

      if @completion and not command
        cmds = @commands.keys.select { |c| c.to_s[0, str.length] == str }

        if cmds.size > 1
          @io.puts "Command '#{str}' is ambiguous:"
          @io.puts "  " + cmds.map(&:to_s).sort.join(', ')
        else
          command = cmds.shift
        end
      end
    end

    if command
      items.shift
      opts = @commands[command]
      delete ? opts.parse!(items) : opts.parse(items)
      opts.execute(items.reject { |i| i == '--' })
    end
  end

  # If autocreation is enabled this method simply generates an option
  # and add's it to the existing list of options
  def autocreate(flag, index, items)
    return if present? flag
    short, long = clean_options Array(flag)
    arg = (items[index + 1] && items[index + 1] !~ /\A--?/)
    option = Option.new(self, short, long, nil, arg, {})
    option.count = 1
    @options << option
  end

  # Clean up arguments sent to `on` and return a list of 5 elements:
  # * short flag (or nil)
  # * long flag (or nil)
  # * description (or nil)
  # * true/false if this option takes an argument or not
  # * extra options (ie: :as, :optional, and :help)
  def clean_options(args)
    options = []
    extras = {}

    if klass = args.find { |a| a.is_a?(Class) }
      extras[:as] = klass
      args.delete klass
    end

    short = args.first.to_s.sub(/\A--?/, '')
    if short.size == 2 && short[-1, 1] == '='
      extras[:argument] = true
      short.chop!
    end

    if short.size == 1
      options.push short
      args.shift
    else
      options.push nil
    end

    long = args.first
    if long.is_a?(TrueClass) || long.is_a?(FalseClass)
      options.push nil
    else
      case long.to_s
      when /\A(?:--?)?[a-z_-]+\s[A-Z\s\[\]]+\z/
        arg, help = args.shift.split(/ /, 2)
        extras[:optional] = help[0, 1] == '[' && help[-1, 1] == ']'
        extras[:help] = help
        options.push arg.sub(/\A--?/, '')
      when /\A(?:--?)?[a-zA-Z][a-zA-Z0-9_-]+\=?\z/
        extras[:argument] = true if long.to_s[-1, 1] == '='
        options.push args.shift.to_s.sub(/\A--?/, '').sub(/\=\z/, '')
      else
        options.push nil
      end
    end

    options.push args.first.respond_to?(:to_sym) ? args.shift : nil
    options.push((@arguments || extras[:argument]) ? true : (args.shift ? true : false))
    options.push extras
  end
end