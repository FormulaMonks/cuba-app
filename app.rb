require File.expand_path("shotgun",  File.dirname(__FILE__))
require File.expand_path("settings", File.dirname(__FILE__))

Cuba.plugin Cuba::Mote
Cuba.plugin Shield::Helpers

Cuba.use Rack::MethodOverride

Cuba.use Rack::Session::Cookie,
  key: "__insert app name__",
  secret: "__insert secret here__"

Cuba.use Rack::Static,
  root: "public",
  urls: ["/js", "/css", "/less", "/img"]

Cuba.use Rack::Protection
Cuba.use Rack::Protection::RemoteReferrer

# Configure your default setting in env.sh by overriding MALONE_URL.
Malone.connect(url: Settings::MALONE_URL)

# Configure your redis settings in env.sh. We're connecting to DB 15.
Ohm.connect(url: Settings::REDIS_URL)

Dir["./lib/**/*.rb"].each     { |rb| require rb }
Dir["./models/**/*.rb"].each  { |rb| require rb }
Dir["./routes/**/*.rb"].each  { |rb| require rb }

# we mix in lib/helpers.rb into Cuba.
Cuba.plugin Helpers

Cuba.define do
  persist_session!

  on root do
    res.write view("home", title: "My Site Home")
  end

  on authenticated(User) do
    run Users
  end

  on "admin" do
    run Admins
  end

  on default do
    run Guests
  end
end
