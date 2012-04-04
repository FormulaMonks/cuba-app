class Admins < Cuba
  # If we throw a 401, we get redirected to /admin/login.
  use Shield::Middleware, "/admin/login"

  # We choose a different layout file for all admin views.
  settings[:layout] = "admin/layout"

  # Syntax sugar.
  def current_admin
    authenticated(Admin)
  end

  # All `mote_vars` gets published to the views. We publish
  # `current_admin` by default as well.
  def mote_vars(content)
    super.merge(current_admin: current_admin)
  end

  # This is a very simple way to secure your return
  # URL and prevent a hijacking attack.
  def assert_return_path(path)
    return if path.nil? or not path =~ %r{\A/admin[a-z0-9\-/]*\z}i

    return path
  end

  # The admin handlers are divided into three different cases:
  #
  # CASE 1: You hit /admin/login
  # CASE 2: You're authenticated, and you hit any other /admin/* URL.
  # CASE 3: You're not authorized, hence you get a 401.
  #
  define do
    # CASE 1: You hit /admin/login
    on "login" do
      on get do
        res.write view("admin/login", title: "Admin Login", username: nil)
      end

      on post, param("username"), param("password") do |user, pass|
        if login(Admin, user, pass, req[:remember])
          session[:success] = "You have successfully logged in."
          res.redirect(assert_return_path(req[:return]) || "/admin/dashboard")
        else
          session[:error] = "Invalid username and/or password combination."
          res.write view("admin/login", title: "Login", username: user)
        end
      end

      on default do
        session[:error] = "No username and/or password supplied."
        res.redirect "/admin/login", 303
      end
    end

    # CASE 2: You're authenticated, and you hit any other /admin/* URL.
    on authenticated(Admin) do
      on "dashboard" do
        res.write view("admin/dashboard", title: "Dashboard")
      end

      on "logout" do
        session[:success] = "You have successfully logged out."

        logout(Admin)
        res.redirect "/admin/login", 303
      end

      on root do
        res.redirect "/admin/dashboard", 303
      end
    end

    # CASE 3: You're not authorized, hence you get a 401.
    on default do
      res.status = 401
      res.write "Forbidden"
    end
  end
end
