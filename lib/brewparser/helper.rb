module BrewHelper
  # Helper functions for main loop
  #  Mainly for `ProcessorInstall` (def install)
  #

  # XXX: Move me to ProcessorInstall
  @@install=[]

  @@cmd_hash={
    "install_symlink" => "ln -srf",
    "install"         => "install -m 577"
  }.freeze

  @@var_hash={
    "man"   => "prefix/man",
    "man1"  => "prefix/man1",
    "man2"  => "prefix/man2",
    "man3"  => "prefix/man3",
    "man4"  => "prefix/man4",
    "man5"  => "prefix/man5",
    "man6"  => "prefix/man6",
    "man7"  => "prefix/man7",
    "man8"  => "prefix/man8",

    "opt_libexec" => "opt_prefix/libexec"
  }.freeze

  # ----- Variables
  # => TreeRewriter variables
  #    grab the data (string) part from whatever TreeRewriter function
  def variable_send(node)
    return node.to_a[1]
  end

  alias variable_begin variable_send
  alias variable_const variable_send

  def variable_str(node)
    # => (str nil "foo") return foo
    return node.to_a[0]
  end

  alias variable_arg    variable_str
  alias variable_lvasgn variable_str
  alias variable_int    variable_str
  alias variable_sym    variable_str
  alias variable_regexp variable_str

  def variable_lvar(node)
    # => handle foo = bar
    return variable_str(node.to_a[0])
  end

  def variable_splat(node)
    # => handle *foobar
    # be fault friendly by seeing if we got splat(lvar :foo) or just [lvar :foo]
    type = node.type if defined? node.type
    return variable_lvar(node.children) if type == "splat"
    # else
    return variable_lvar(node)
  end

  def variable_const_formula(node)
    # parse Formula const
    # puts "variable_const:\n|#{node}"
    s = node
    i = 0 # timeout our spaghetti code
    z = ""
    until not defined? s.children
      s = variable_strip(s)
      z = s.children[0].type.to_s rescue nil
      break if %w(const).include? z
      i = i+1; break if i == 5
    end
    return environment(s, true) if z == "const"
    # else
    return nil
  end

  def variable_multi(node)
    # => handle each children of a node, return nil on failure
    # puts "variable_multi:\n|#{node}"
    begin
      loop do
        s = node.children.to_a if defined? node.children.to_a
        # default: return nil if single/null
        if s.count > 2
          x = []
          node.children.each { |z| x << handle(z) }
          return x.join()
        end
        node = variable_strip(node)
      end
    rescue
      # bail on error
      return nil
    end
    # default:
    return nil
  end

  def variable_strip(node)
    # (send nil :foo (str "bar")) return "bar"
    return node.to_a[0]
  end

  def variable_last(node)
    # (send nil :foo (str "bar") (str "baz")) return "baz"
    return node.to_a[-1]
  end

  def variable_sstrip(node)
    # remove >>(send nil :foo<< (str "blah") (str "ex") [...])
    return node.to_a.drop(2)
  end

  # => handle str/dstr/var/whatever and return a string
  def handle(node)
    # XXX: FIXME, return if a bad string is passed
    return node unless defined? node.type.to_s
    # if Symbol, hack function a :symbol.to_s
    node.to_a.each do |c|
      return "#{c}" if c.class == Symbol && node.type.to_s == "send" # != "sym"
    end

    case node.type.to_s
    when "str"
      return variable_str(node.children)
    when "dstr"
      words = ""
      node.children.each do |dstr|
        if dstr.children[0] != "str"
          words << handle(dstr)
        else
          words << variable_str(dstr)
        end
      end
      return words
    when "array"
      array = []
      node.children.each { |item| array << handle(item) }
      return array
    when "arg"
      return variable_arg(node)
    when "args"
      array = []
      node.children.each { |item| array << handle(item) }
      # XXX: FIXME figure how to handle multi-for loops
      # like 10 formulas use them
      return array
    when "lvasgn"
      return variable_lvasgn(node)
    when "lvar"
      x = variable_str(node)
      return bash_variable(x)
    when "splat"
      x = variable_splat(node)
      return bash_variable(x)
    when "const"
      return variable_const(node)
    when "begin"
      # the start of a command ex. system
      type = variable_strip(node).type.to_s
      x = case type
      when "lvar"
        variable_str(variable_strip(node))
      else # "send", "begin"
        variable_send(variable_strip(node))
      end
      # catch const, here
      # XXX: Waste of cycles doing this, but eh
      if type == "send"
        z = variable_const_formula(node)
        return z if z
        z = variable_multi(node)
        return z if z
      end
      # else
      return bash_variable(x)
    when "send"
      z = variable_multi(node)
      return z if z

      x = variable_const(node)
      return variable_send(node)
    when "hash"
      array = []
      node.children.each { |item| array << handle(item) }
      return array
    when "pair"
      array = []
      node.children.each { |item| array << handle(item) }
      return array
    when "int"
      return variable_int(node)
    when "sym"
      return variable_sym(node)
    else
      # XXX: error out here
      puts "handle UNKNOWN: #{node.type}"
      return nil
    end
  end

  # => handle environment (const)
  def environment(node, returns = false)
    # puts "environment: #{node}"
    const, _, var, *what = node.children
    # => const  | const nil: :FOO
    # => _      | :[]=
    # => var    | (str "variable")
    # => what   | (str "foobar")
    const = handle(const)
    var   = handle(var)

    # puts "environment: #{const}, #{var}, #{what}"

    case const.to_s
    when "ENV"
      return environ_env(var, what, returns)
    when "Formula"
      return environ_formula(var, what, returns)
    end
    #what = handle(node.children[0])
    #puts "environment: #{what}"
  end

  # ---- env_* functions
  # handle all const (ex. Formula)

  def environ_env(var, what, returns = false)
    # => get env from ENV.foo
    puts "environ_env: #{var}, #{what}, #{returns}"
    asgn = ""
    what.each { |x| asgn << handle(x) }

    return if returns
    puts "environ_env: export #{var} = #{asgn}" if var
    # XXX: FIXME check for []_ ('_' in environment); it reveals if this is a
    # assginment or calling
    @@install << "export #{var}=\"#{asgn}\""
  end

  def environ_formula(var, what, returns = false)

    return bash_function(var) if returns
    puts "environ_formula: Formula[#{var}]"
  end


  # ---- var_* functions
  # handle variable assginments
  # * if var != nil, assume the caller wants their data

  # => strings
  def var_string(asgn, var = nil)
    asgn = handle(asgn)
    return asgn unless var
    puts "var_string: #{var} = #{asgn}"
    @@install << "export #{var}=\"#{asgn}\""
  end

  # => arrays
  def var_array(asgn, var = nil)
    args = []
    asgn.children.each do |child|
      args << handle(child)
    end
    return asgn unless var
    puts "var_array: #{var} = #{args}"
    @@install << "export #{var}=(#{args.join(" ")}"
  end

  # => op_asgn (+=)
  def var_op_asgn(asgn, op, var)
    asgn, var = handle(asgn), handle(var)
    op = "+" if op.to_s == "<<"
    puts "var_op_asgn: #{var} #{op}= #{asgn}"
  end

  # => brew vars

  # ----- Commands
  def cmd_parse(node, returns = false)
    # => this is a ruby command, solve which one
    what = node.children[1]
    case what.to_s
    when "system"
      return cmd_system(node.children)
    when -> (x) { @@cmd_hash[x]}
      return cmd_brew(node, returns)
    when -> (x) { @@var_hash[x]}
      return var_brew(node, returns)
    else
      puts "cmd_parse UNKNOWN >>> #{what}"
    end
  end

  def cmd_understand(node)
    # => this node isn't a command, figure out what to do
    what = node.children[0].type
    puts "cmd_understand: #{what}"
    case what.to_s
    when "lvar"
      var, op, asgn = node.children
      var_op_asgn(asgn, op, var)
    when "const"
      environment(node)
    when "send"
      cmd_parse(node)
    end
  end

  def cmd_block(node)
    # => handle on_block
    cmd, var, *what = node.children
    # cmd   | %W["a", "b", "c"].each  | (send nil :resource): stage
    # var   | do |foo|                | (args)
    # what  | puts #{foo}             | (send nil system blah blah)
    # type  | (send (foobar) :__type__)
    type  = variable_send(cmd)
    var   = handle(var)
    cmd   = variable_strip(cmd)   # already know the type, strip send

    puts "cmd_block:\n| #{cmd} \n| #{type} \n| #{var} \n| #{what}"
    case type.to_s
    # when "stage"
    when "each"
      cmd_each(cmd, var, *what)
    when "resource"
      cmd_resource(cmd, var, *what)
    else
      # XXX: error out here
      puts "cmd_block: UNKNOWN #{cmd}"
    end
  end

  # | cmd sub functions

  def cmd_resource(cmd, var = nil, what)
    puts "HIT THE PPPPPPPPPPPPPPPPPP"
    puts "cmd_resource: #{cmd} | #{var} | #{what}"
  end

  def cmd_each(cmd, var = nil, what)
    # => handle word lists and attempt to pass it as a bash for loop
    # XXX: fixme, variable_sym will skip any more args than 1
    var = variable_sym(var) rescue var
    cmd = handle(cmd)
    parse = cmd_parse(what, true) # returns = true

    puts "cmd_each: #{cmd} -> #{var}"
    @@install << "for #{var} in #{cmd.join(" ")}; do"
    @@install << "#{parse}"
    @@install << "done"
  end

  def cmd_system(node)
    # => solve most common & easy command: system
    node = node.to_a
    # XXX: error out here
    puts "cmd_system ERROR bad array?: #{node}" if node[1].to_s != "system"
    node = node.drop(2) # assume first 2 in the array are [nil, system] then

    args = []
    node.each do |a|
      args << handle(a)
    end

    puts "system: #{args}"
    @@install << args.join(" ")
  end

  def cmd_brew(node, returns = false)
    # => from cmd_hash, solve methods to bash commands
    what, cmd, *action = node.children
    what  = handle(what) if what
    # cmd   = node.children[1]
    value = @@cmd_hash[cmd.to_s]
    action = handle(*action) rescue handle(*action[0])
    puts "cmd_brew: | #{what} | #{cmd} | #{value} | #{action}}"

    return "#{value} #{action}" if returns

  end

  def var_brew(node, returns = false)
    # => from var_hash, solve vars to bash vars
    _, cmd, *action = node.children
    # what  = handle(what)
    # cmd   = node.children[1]
    value = @@var_hash[cmd.to_s]

    puts "var_brew: | #{cmd} | #{value}"
  end

  # misc

  # => ruby var to bash var
  def bash_variable(var)
    return "\"${#{var}}\""
    # return \"${foobar}\"
  end

  def bash_function(var)
    return "\"$(PKG_DEST_ #{var})\""
    # return \"$(PKG_DEST_ foobar)\"
  end

end # module BrewHelper
