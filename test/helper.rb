require File.expand_path("../app", File.dirname(__FILE__))
require "cuba/test"
require "malone/test"

prepare do
  Capybara.reset!
  Ohm.flush
end

class Cutest::Scope
  def session
    Capybara.current_session.driver.request.env["rack.session"]
  end
end
