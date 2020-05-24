# Handle BrewParser's output to bash-ism
module Installer

  def self.to_bash(infile)
    main(infile)
  end # def self.to_bash

  private
  # => c => command
  # => h => handle

  @@prefix = "${PKG_TAPF}"

  @@variables = {
    :HOMEBREW_PREFIX => "#{@@prefix}",
    :prefix => "#{@@prefix}",
    :bin => "#{@@prefix}/bin",
    :doc => "#{@@prefix}/share/doc",
    :include => "#{@@prefix}/include",
    :info => "#{@@prefix}/share/info",
    :lib => "#{@@prefix}/lib",
    :libexec => "#{@@prefix}/libexec",
    :man => "#{@@prefix}/share/man",
    :man1 => "#{@@prefix}/share/man1",
    :man2 => "#{@@prefix}/share/man2",
    :man3 => "#{@@prefix}/share/man3",
    :man4 => "#{@@prefix}/share/man4",
    :man5 => "#{@@prefix}/share/man5",
    :man6 => "#{@@prefix}/share/man6",
    :man7 => "#{@@prefix}/share/man7",
    :man8 => "#{@@prefix}/share/man8",
    :sbin => "#{@@prefix}/sbin",
    :share => "#{@@prefix}/share",
    :pkgshare => "#{@@prefix}/share",
    :elisp => "#{@@prefix}/share/emacs/site-lisp",
    :frameworks => "#{@@prefix}/Frameworks",
    :kext_prefix => "#{@@prefix}/Library/Extensions",
    :etc => "#{@@prefix}/etc",
    :pkgetc => "#{@@prefix}/etc",
    :var => "#{@@prefix}/var",
    :zsh_functions => "#{@@prefix}/zsh/site-functions",
    :fish_function => "#{@@prefix}/fish/vendor_functions.d",
    :bash_completion => "#{@@prefix}/etc/bash_completion.d",
    :zsh_completion => "#{@@prefix}/zsh/site-functions",
    :fish_completion => "#{@@prefix}/fish/vendor_completion.d",
    :plist_name => "io.mc.FIXME",
    # Formula
    :opt_prefix => "#{@@prefix}/bin",
    :opt_include => "#{@@prefix}/lib",
    :opt_libexec => "#{@@prefix}/libexec",
    :opt_sbin => "#{@@prefix}/sbin",
    :opt_share => "#{@@prefix}/share",
    :opt_pkgshare => "#{@@prefix}/share",
    :opt_elisp => "#{@@prefix}/share/emacs/site-lisp",
    :opt_frameworks => "#{@@prefix}/Frameworks"
  }

  @@output = []

  def self.main(infile)
    delim = "START"
    infile.each do |line|
      line = line[delim]
      puts "ORIGINAL> #{line}\n"

      if line.class == Hash
        h_hash(line)
      elsif line.class == Array
        h_array(line)
      end

    end
  end

  def self.parser(line, isself = false)
    # => return array
    array = []
    line.each do |word|
      if word.class == Array
        result = parser(word, true)
      elsif word.class == Symbol
        result = @@variables[word]
        result = "${#{word}[@]}" if not result
      else
        result = word
      end
      array << result
    end
    return array.join() if isself
    # else
    return array.join(" ")
  end

  # define it once:
  @@cmd_wrappers = {
    "\./configure" => "pkg:configure",
    "make install" => "pkg:install"
  }
  # https://stackoverflow.com/a/8132729
  @@cmd_re = \
    Regexp.new(@@cmd_wrappers.keys.join('|'))
    # Regexp.new(@@cmd_wrappers.keys.map { |x| Regexp.escape(x) }.join('|'))

  def self.c_system(line)
    l = parser(line)
    l = l.gsub(@@cmd_re, @@cmd_wrappers)
    return l
  end

  def self.c_inreplace(line)
    return line
  end

  def self.c_install(line)
    return 
    line = line.del
    l = parser(line)
    puts l
    abort()
  end

  def self.h_symbol(line)
    type = line.class
    cmd  = if
      line.include?(:install); c_install(line)
    end
    puts cmd


    return line
  end

  def self.h_hash(line)
    what = line.keys[0]
    result = case what.to_s
    when "system"
      c_system(line[what])
    when "inreplace"
      c_inreplace(line)
  # ELSE
    when what.class == Symbol
      puts "LLLLLLLLLLLLLLLLLLORD"
    else
      puts "FIXME: #{what}"
    end
    puts ">>> #{result}"
    # c_system(line) rescue nil
  end

  def self.h_array(line)
    what = line[0]
    result = if c = what.class
      c == Symbol; h_symbol(line)
      end
    puts ">>> #{result}"
  end
end # module Installer
