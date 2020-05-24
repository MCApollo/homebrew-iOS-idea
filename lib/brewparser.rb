require 'parser/current'

require_relative 'brewparser/processor'

module BrewParser
  def self.processfile(file)
    p = Processor.new(file)
    # json = JsonAPI.new.grab()
  begin
    exp = Parser::CurrentRuby.parse(File.read(file))
  rescue Parser::SyntaxError
      # "f---ing unicode" or bad user input
      # `process': literal contains escape sequences incompati(Parser::SyntaxError)
      exp = Parser::CurrentRuby.parse(File.read(file).gsub(/\\(?:\s*)/,'\&\&'))
    end
    # j = JsonAPI.new.grab()

    p.process(exp)

    return p.to_hash
  end

end
