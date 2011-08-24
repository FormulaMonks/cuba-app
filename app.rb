require File.expand_path("shotgun", File.dirname(__FILE__))

Dir["./lib/**/*.rb"].each { |rb| require rb }

Cuba.use Rack::MethodOverride

Cuba.use Rack::Session::Cookie,
  key: "__insert app name__",
  secret: "__insert secret here__"

Cuba.use Rack::Static,
  root: "public",
  urls: ["/js", "/css", "/images"]

class Cuba
  include Mote::Helpers

  def partial(template, locals = {})
    mote("views/#{template}.mote", locals)
  end

  def view(template, locals = {})
    partial("layout", locals.merge(content: partial(template, locals),
                                   session: session))
  end

  def session
    env["rack.session"]
  end
end

Cuba.define do
  on "" do
    res.write view("home", title: "My Site Home")
  end
end