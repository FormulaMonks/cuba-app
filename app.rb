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
Cuba.plugin Shield::Helpers

# We use the more secure PBKDF2 password strategy (iterations = 5000)
Shield::Password.strategy = Shield::Password::PBKDF2

Cuba.define do
  persist_session!

  on "" do
    res.write view("home", title: "My Site Home")
  end

  on "about" do
    res.write partial("about")
  end

  on "login" do
    on get do
      res.write view("login", title: "Login", username: nil)
    end

    on post, param("username"), param("password") do |user, pass|
      if login(User, user, pass, req[:remember])
        session[:success] = "You have successfully logged in."
        res.redirect(session.delete(:return_to) || "/")
      else
        session[:error] = "Invalid username and/or password combination."
        res.write view("login", title: "Login", username: user)
      end
    end

    on default do
      session[:error] = "No username and/or password supplied."
      res.redirect "/login", 303
    end
  end

  on "logout" do
    logout(User)
    res.redirect "/", 303
  end
end
