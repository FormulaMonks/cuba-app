$:.unshift(*Dir[File.expand_path("vendor/*/lib", File.dirname(__FILE__))])

require "cuba"
require "mote"