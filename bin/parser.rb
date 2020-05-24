#!/usr/bin/env ruby

require_relative '../lib/brewparser.rb'
require_relative '../lib/installer.rb'
require 'json'

Signal.trap("INT"){ abort() }
file  = ARGV.first
file  = '/home/cade/homebrew-iOS-idea/example/man-db.rb' if not file
result = BrewParser::processfile(file)

install = Installer::to_bash(result["install"])

puts "#########\n"
puts JSON.pretty_generate(result).gsub(": ", " => ")
