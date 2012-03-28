$:.unshift(*Dir[File.expand_path("vendor/*/lib", File.dirname(__FILE__))])

require "cuba"
require "cuba/contrib"
require "mote"
require "ohm"
require "pbkdf2"
require "shield"
