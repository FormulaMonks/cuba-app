require File.expand_path("../app", File.dirname(__FILE__))
require "cuba/test"

prepare do
  Capybara.reset!
end
