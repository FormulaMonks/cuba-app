class Users < Cuba
  define do
    on "dashboard" do
      res.write view("dashboard", title: "Dashboard")
    end

    on "logout" do
      logout(User)
      res.redirect "/", 303
    end
  end
end
