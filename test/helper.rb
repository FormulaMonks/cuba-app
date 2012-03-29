# In order to sandbox the test and dev env, we declare a
# different value for REDIS_URL when doing tests.
ENV["REDIS_URL"]  ||= "redis://localhost:6379/13"

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
