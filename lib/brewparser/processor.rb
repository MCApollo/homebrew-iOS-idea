require_relative 'helper'

$debug = false

module BrewParser
  class Processor < Parser::TreeRewriter
    # init
    include BrewHelper

    def initialize(file)
      @@data_hash = {}
      @@file = file

      data_add("file", File.basename(file))
    end
    # Returns
    def to_hash
      return @@data_hash
    end
    # Main logic

    def on_class(node)
      name = variable_const(node.children[0]) # Class Foo < Formula
      data_add("name", name)

      node.children.each { |x| process(x) }
    end

    def on_begin(node)
      # puts "on_begin: #{node}"
      node.children.each { |x| process(x) }
    end

    def on_send(node)
      # puts "on_send: #{node}"
      handle_send(node)
    end

    def on_block(node)
      # puts "on_block: #{node}"
      what = variable_send(variable_strip(node)).to_s rescue nil

      case what
      when "patch"
        handle_patch(node)
      when "stable"
        node.children.each { |x| process(x) }
      when "resource"
        handle_resource(node)
      when "test", "bottle"
      else
        puts "on_block: SKIPPED #{what} #{node}" if $debug
      end

    end

    def on_def(node)
      function = node.children[0].to_s rescue nil

      def_install(node) if function == "install"

    end

    def def_install(node)
      # return
      p = ProcessorInstall.new
      p.process(node)
      @@data_hash["install"] = p.to_a
    end

    def data_add(value, what)
      @@data_hash[value] = what
    end

    def data_append(value, what)
      @@data_hash[value] = "" if @@data_hash[value].nil?

      @@data_hash[value].merge!(what)
    end

    def handle_send(node)
      what = variable_send(node).to_s rescue nil
      value = handle(variable_last(node))
      puts "handle_send: #{what} #{value}" if $debug
      case what
      when "desc", "homepage", "revision", "sha256"
        data_add(what, value)
      when "url"
        # special case for git urls
        # default to value any time
        v     = variable_sstrip(node)               rescue nil
        url   = variable_str(v[0])                  rescue value
        args  = handle(variable_last(node)) if v[1] rescue nil
        if args
          data_add(what, { "url" => url, "args" => args })
        else
          data_add(what, value)
        end
      when "patch"
        handle_patch(node, true) # data = true
      when "depends_on", "uses_from_macos"
        handle_depends(what, value)
      when "conflicts_with"
        what = variable_str(variable_sstrip(node)[0])
        handle_conflicts(what, value)
      end
    end

    def handle_depends(what, value)
      puts "handle_depends: #{what} #{value}" if $debug
      # what = variable_send(node).to_s
      # value = handle(variable_last(node))
      build = value.class != String
      hash_append = nil
      @@data_hash["depends"] = [] if @@data_hash["depends"].nil?
      # if value.class = Array, assume :build
      if build
        value = value[0] rescue value
        w = value[0]  # word
        s = value[1]  # sym
        hash_append = { w => s }
      else
        hash_append = { value => "runtime" }
      end
      @@data_hash["depends"] << hash_append
    end

    def handle_conflicts(what, value)
      puts "handle_conflicts: #{what} | #{value}" if $debug
      # what = variable_str(variable_sstrip(node)[0])
      value = value[0][1] rescue value
      @@data_hash["conflicts"] = [] if @@data_hash["conflicts"].nil?

      @@data_hash["conflicts"] << { what => value }
    end

    def handle_resource(node)
      puts "handle_resource: #{node}" if $debug
      hash_append = nil
      url         = nil
      sha256      = nil
      args        = nil
      what        = variable_str(variable_last(variable_strip(node)))
      block       = variable_last(node)
      @@data_hash["resource"] = [] if @@data_hash["resource"].nil?

      block.children.each do |x|
        w = handle(x).to_s
        v = handle(variable_last(x)) rescue nil

        case w
        when "url"
          if v == nil
            # see above code for comments
            # tldr: url has a argument to it
            v     = variable_sstrip(block)              # rescue nil
            url   = variable_str(v[0])                  # rescue nil
            args  = handle(v[1])[0] if v[1]             # rescue nil
          else
            url = v
          end
        when "sha256"
          sha256 = v
        else
          puts "handle_resource: UNKNOWN #{w} #{v}" if $debug
        end
      end # block.children.each do |x|


      hash_append = if ! args
      {
        what => {
          "url" => url,
          "sha256" => sha256
        }
      }
      else
        {
          what => {
            "url" => url,
            "args" => args
          }
        }
      end

      @@data_hash["resource"] << hash_append
    end

    def handle_patch(node, data = false)
      # puts "handle_patch: #{node}"
      hash_append = nil
      patchlevel = ""
      @@data_hash["patch"] = [] if @@data_hash["patch"].nil?
      if data
        # EOF data patch
        # support :p0 for the like 5 formulas that use it
        begin
        p = variable_sym(node.to_a[-2])[-1];
        patchlevel = p
        rescue; end
        patchlevel = "1" if patchlevel.empty?

        eofdata = +""
        open(@@file) do |f|
          loop do
            line = f.gets
            break if line.nil? || line =~ /^__END__$/
          end
          while line = f.gets
            eofdata << line
          end
        end

        hash_append = [ "DATAPatch" => {
          "p" => patchlevel,
          "data" => eofdata
        }]
      else
        block = variable_last(node)
        patchlevel = variable_sym(variable_last(variable_strip(node)))[-1] rescue 0
        # strip -> remove block( )
        # last -> get sym :p* if it exists
        # sym -> get value of sym, [-1] gets p"*"
        url    = nil
        sha256 = nil
        apply  = nil

        block.children.each do |x|
          what = variable_send(x).to_s
          value = handle(variable_last(x))

          case what
          when "url"
            url = value
          when "sha256"
            sha256 = value
          when "apply"
            # reeval value
            value = variable_sstrip(x)
            apply = []
            value.each { |z| apply << handle(z) }
          else
            puts "handle_patch: UNKNOWN #{what} #{value}" if $debug
          end
        end # block.children.each do |x|

        if apply
          hash_append = [ "ExternalPatch" => {
            "p" => patchlevel,
            "url" => url,
            "apply" => apply
          }]
        else
          hash_append = [ "ExternalPatch" => {
            "p" => patchlevel,
            "url" => url
          }]
        end
      end # if data

      @@data_hash["patch"] << hash_append
    end

  end # class Processor

  #############################################

  class ProcessorInstall < Parser::TreeRewriter
    # => Parses `def install` in homebrew formulas
    include BrewHelper

    # ------ Writer
    @@install=[]
    def write(line)
      @@install << { "START" => line }
    end

    def to_a()
      return @@install
    end

    # ------ TreeRewriter
    def on_block(node)
      # puts "on_block:\n#{node}"
      r = handle_block(node, true)
      write(r)
      # cmd_block(node)
    end

    def on_if(node)
      # puts "on_if:\n#{node}"
      r = handle_if(node, true)
      write(r)
    end

    def on_send(node)
      # puts "on_send: #{node}"
      r = handle_send(node, true)
      write(r)
    end

    def on_lvasgn(node) # local variable assignment
      # puts "on_lvasgn:\n#{node}"
      r = handle_lvasgn(node, true)
      write(r)
    end

    def on_op_asgn(node) # binary op-assign (+=)
      # puts "on_op_asgn:\n#{node}"
      r = handle_op_asgn(node, true)
      write(r)
    end

    def on_lvar(node) # local variable update
      # puts "on_lvar:\n#{node}"
    end

    ######################

    def handle_block(node, returns = false)
      # => handle on_block
      # ex.
      # block     | (array [foo, bar].each)
      # (args)    | (args :var)
      # (child)   | (send nil cmd)
      what, args, *child = node.children
      puts "handle_block: #{what} | #{args} | #{child}" if $debug

      begin
        what_a  = what.to_a[0]
        # XXX: revert if needed to avoid abort(), though PIA to add opts
        what_a  = what if not %w(send array symbol const).include? what_a
        what_t  = what_a.type.to_s
      rescue NoMethodError
        # try to recover, is [0] a Symbol?
        what_a  = what.to_a[1]
        what_t  = if
          what_a.class == Symbol; "symbol"
          else; what_a.type.to_a
        end # keep symbol class if == Symbol, ex. (send nil :mkdir)
        abort("(install) handle_block: {what_a|what_t} == nil") \
          if what_a == nil || what_t == nil
      end # NoMethodError
      args_a  = args.to_a
      child_t = child[0].type.to_s
      # make sure child is a node and not a array
      child = child[0] if child.class == Array rescue child

      puts "|=> #{what_t} | #{args_a} | #{child_t}" if $debug

      result = nil
      case what_t
      when "send"
        send = what_a.to_a[1].to_s
        case send
        when "resource", "resources"
          # hint: resources mean we're in a .each loop
          block  = (send == "resources")
          result = handle_resource(what_a, child, block, true)
        else
          # => default to a for loop
          w = handle_child(what_a)
          a = handle_child(args)
          c = handle_child(child)
          result = { "for" => { ["#{w}", "#{a}"] => c  } }
          # puts "(install) (send) handle_block: UNKNOWN #{send}"
        end
      when "array"
        result = handle_array(what, child, true) # returns = true
      when "symbol", "const"
        result = handle_symbol(what, child, true)
#      when "const"
#        r = handle_const(what, child)
      else
        abort("handle_block: UNKNOWN #{what}")
      end

      # abort("handle_block: empty?") if not ( result and what_t == "result" )

      return result if returns
    end # def handle_block

    def handle_lvasgn(node, returns = false)
      # => handle lvasgn (args = %w["foo"])
      variable, *child = node.children
      child = child.to_a[0] if child.class == Array rescue child

      variable  = variable.to_s rescue variable
      child_a   = if child.to_a.length <= 1; [ handle_child(child, true) ]
                  else;                      handle_child(child)
                  end                        # handle_child(child, isSelf)

      puts "handle_lvasgn: #{variable} == #{child_a}" if $debug
      result = { "#{variable}".to_sym => child_a }
      return result
    end # def handle_lvasgn(node)

    def handle_op_asgn(node, returns = false)
      # => (op-asgn (lvasgn :a) :+ (int 1))
      variable, op, *child = node.children

      variable = handle_child(variable)
      child = child.to_a[0] if child.class == Array rescue child

      variable  = variable.to_s rescue variable
      child_a  = if child.to_a.length <= 1; [ handle_child(child, true) ]
                 else;                      handle_child(child)
                 end

      puts "handle_op_asgn: #{variable} | #{op} | #{child_a}" if $debug
      result = [variable, "#{op}=", child_a]
      return result if returns
    end

    def handle_if(node, returns = false)
      args, *child = node.children

      args  = handle_child(args)
      child = handle_child(child)

      result = { args => child }
      result = { "if" => result }

      puts "handle_if: #{args} | #{child}" if $debug
      return result
    end # def handle_if

    def handle_resource(what, child, block = false, returns = nil)
      puts "(install) handle_resource: #{what} | #{child} | #{block}" if $debug

      result = nil
      if not block
        # b = handle_block(child, true) # returns = true
        resource = variable_str(what.to_a[-1])
        result   = "$(PKG_resource_ #{resource})"
      end

      child_r = handle_child(child)
      result  = block ? child_r : { resource => child_r }

      return result if returns
    end # def handle_resource

    def handle_symbol(what, child = nil, returns = false)
      # => if RETURNS:
      # => if child; then {what => child}
      # => else, this might be a assignment
      puts "(install) handle_symbol: #{what} | #{child}" if $debug

      what_s = if
        what.class == Parser::AST::Node; handle_child(what, true)
        else; what
        end

      puts "handle_symbol => #{what_s.class} #{what_s} => #{child}" if $debug

      result  = nil
      what_r  = nil
      child_r = nil

      case what_s.to_s
      when "ENV"
        loop do
          what_r = child[0]
          child = child.drop(1)
          # XXX: handle: ENV["foobar"] == baz and friends
          break if not %w([]=).include? what_r.to_s rescue true
        end
        what_r = variable_str(what_r) if what_r.class == Parser::AST::Node \
            rescue what_r
      else
        what_r = what_s
      end

      child = nil if (child.empty? || child.nil?) rescue child
      child_r = if
        child.class == Parser::AST::Node; handle_child(child);
        else;                             handle_child(child)
        end                               # rescue nil

#      what_r = if
#        what_r.class == Array;             handle_child(what_r[0]);
#        what_r.class == Parser::AST::Node; handle_child(what_r);
#        else;                              what_r
#        end                                rescue what_r
        # XXX: undefined method `empty?' for #<Parser::AST::Node>
      result = if
        (child_r == nil || child_r.nil? || child_r.empty?); "#{what_r}".to_sym
      else;      { "#{what_r}".to_sym => child_r }
        end

      abort("handle_symbol: what_r is nil") if what_r == nil
      puts "handle_symbol: result => #{result}\n\t => #{child} / #{child_r}" if $debug
      return result if returns
    end # def handle_symbol

    def handle_array(what, child = nil, returns = false)
      # => Returns
      # => if returns; array of what
      # =>  process child
      puts "(install) handle_array: #{what} | #{child}" if $debug
      what_t = what.type.to_s
      what_a = if
        what_t == "send";  what.to_a[0];
        else;              what
        end
      result = []

      #
      # `what_a` should be a ast (array)
      raise("handle_array: what_a isn't a ast array? (#{what_a.class}) #{what_a}") \
        if what_a.type.to_s != "array"
      abort("handle_array: this is a each array with no child?") \
        if what_t == "send" && child == nil
      result = handle_child(what_a)

      process_child(child)

      return result if returns
    end

    def handle_send(node, returns = false)
      #
      what, *child = node.children
      if what == nil
        what  = child[0]
        child = child.drop(1)
      elsif child.empty? || child.nil?
        child = nil
      end

      type = if
        what.class == Symbol; "symbol"
        else;                 what.type.to_s
      end
      puts "(install) handle_send: #{what} | #{child}" if $debug

      result = nil
      puts "+++ (handle_send)" if $debug
      case type # (what)
      when "symbol"
        result = handle_symbol(what, child, true) # returns = true
      when "const"
        result = handle_symbol(what, child, true)
      when "lvar"
        result = handle_child(node)
      when "send", "begin"
        result = handle_child(node)
      # XXX: Ruby code is complex, log unknowns
      else
        result = handle_child(node)
        puts "(install) handle_send: UNKNOWN -> #{type} \n|#{node}"
        # abort("handle_send: UNKNOWN (look above)")
      end

      puts "(handle_send) result: #{result}" if $debug

      return result
    end

    def handle_child(node, isSelf = false)
      # XXX: replaceent for handle()
      # deal with *child and return a usable bash string
      puts "(install) handle_child: #{node}" if $debug

      if not isSelf # => put our-self into a loop
        child_a = if node.class == Array; node
                  else;                   node.to_a
                  end
        child_l = child_a.length
        result = []

        child_a.each { |e| result.append( handle_child(e, true) ) } # retuns = true
        return result
      end # if isSelf

      if node.class == NilClass
        # XXX: TODO: have compain() function to log
        begin; raise("handle_child: ignoring nil"); rescue => e; end
        puts e
        for i in 0..5
          puts e.backtrace[i]
        end
        return nil
      end

      type = if
        node.class == Symbol; "symbol"
        else;                 node.type.to_s
        end

      result = nil

      case type
      when "str", "string"
        result = variable_str(node)
      when "lvar", "sym"
        result = variable_str(node)
        result = "#{result}".to_sym
      when "xstr"
        # (xstr (str "foo") (lvar bar))
        result = handle_child(node)
      when "const"
        result = variable_const(node)
        result = "#{result}".to_sym
      when "dstr"
        result = handle_child(node) # isSelf = false
      when "symbol"
        result = handle_symbol(node, nil, true) # node, child, returns
        result = "#{result}".to_sym
    # ------
      when "splat"
        # (splat (lvar :foo))
        result = handle_child(node)
      when "lvasgn"
        result = handle_lvasgn(node, true) # return = true
      when "op_asgn"
        result = handle_op_asgn(node, true)
    # ------
      when "array"
        result = handle_array(node, nil, true)
    # HASH
    # ex:
    # (hash (pair (int 1) (int 2)) (pair (int 3) (int 4)))
    # => go into a rabbit hole
      when "hash", "pair"
        result = handle_child(node)
    # ARGS
    # (args (arg :foo))
      when "args"
        result = handle_child(node)
      when "arg"
        result = variable_arg(node)
    # REGEX
    # (regexp (str "foo") (lvar :bar) (regopt :i))
      when "regexp", "regopt"
        result = handle_child(node)
    # ------
      when "send"
        # raise("XXX: #{node.to_a}")
        result = handle_send(node)
      when "begin"
        # arg
        result = handle_child(node.to_a)
      when "block"
        result = handle_block(node, true) # returns = true
    # MISC
      when "if"
        result = handle_if(node, true) # returns = true
      when "int"
        result = variable_int(node)
      when "true", "false"
        result = node
      when "next"
        result = "continue"
      when "and"
        result = "&&"
      when "or"
        result = "||"
      when "irange"
        # irange: we can expect two ints
        result = handle_child(node)
        result = "{#{result[0]}..#{result[1]}}"
    # MISC - NIL
      # XXX: is this nil or parser screw up?
      when "nil"
        complain("handle_child: nil value?")
        result = "nil".to_sym
      else
        raise("fixme: #{type} => #{node}")
      end
      raise("empty? fixme: #{type} => #{result} \n\t+> #{node}") if not result
      puts "handle_child +++ #{result} | #{type} | #{node}" if $debug
      return result
    end # def handle_child

    def process_child(child)
      # => stub for process(node)
      # XXX: FIXME: undefined method `to_ast' for :install:Symbol (NoMethodError)
      return
      begin
        child.each { |c| process (c) }
      rescue NoMethodError
        msg = "#{child}"
        process(child) rescue raise("rescue process_child failed: #{msg}")
        # child.to_a.each { |c| process (c) } rescue raise("handle_resource failed")
      end
    end

    def complain(string)
      # XXX: Write me to a log or debug option
      if $debug
        begin; raise("!!! #{string} !!!"); rescue => e; end
        puts e
        for i in 0..6
          puts e.backtrace[i]
        end
      end
    end

  end # class ProcessorInstall
end # module BrewParser
