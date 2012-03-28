require File.expand_path("shotgun", File.dirname(__FILE__))

Dir["./lib/**/*.rb"].each { |rb| require rb }

Cuba.use Rack::MethodOverride

Cuba.use Rack::Session::Cookie,
  key: "__insert app name__",
  secret: "__insert secret here__"

Cuba.use Rack::Static,
  root: "public",
  urls: ["/js", "/css", "/images"]

Cuba.plugin Cuba::Mote

Cuba.define do
  on "" do
    res.write view("home", title: "My Site Home")
  end

  on "about" do
    res.write partial("about")
  end
end
