# encoding: UTF-8

$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/../lib"))

begin
  require "ruby-debug"
rescue LoadError
end

require "cutest"

def silence_warnings
  original_verbose, $VERBOSE = $VERBOSE, nil
  yield
ensure
  $VERBOSE = original_verbose
end

$VERBOSE = true

require "ohm"

prepare do
  Ohm.flush
end
