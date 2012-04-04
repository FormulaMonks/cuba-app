class Guests < Cuba
  define do
    on "login" do
      on get do
        res.write view("login", title: "Login", username: nil)
      end

      on post, param("username"), param("password") do |user, pass|
        if login(User, user, pass, req[:remember])
          session[:success] = "You have successfully logged in."
          res.redirect("/dashboard")
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

    on "signup" do
      on get do
        res.write view("signup", title: "Signup", user: User.new)
      end

      on post, param("user") do |params|
        user = User.new(params)

        begin
          if user.save
            authenticate(user)

            session[:success] = "You have successfully signed up."
            res.redirect "/dashboard", 303
          else
            res.write view("signup", title: "Signup", user: user)
          end
        rescue Ohm::UniqueIndexViolation
          session[:error] = "That email has been taken."
          res.write view("signup", title: "Signup", user: user)
        end
      end
    end

    on "password/recovery" do
      on post, param("email") do |email|
        user = User.fetch(email)

        if user
          PasswordRecovery.init(user)
          res.redirect "/password/instructions", 303
        else
          session[:error] = "No account found matching that email."
          res.redirect "/password/recovery", 303
        end
      end

      on default do
        if req.post?
          session[:error] = "Please enter an email address."
        end

        res.write view("password/recovery", title: "Password Recovery")
      end
    end

    on "password/instructions" do
      res.write view("password/instructions", title: "Password Recovery")
    end

    on "password/reset/:id/:token" do |id, token|
      user = PasswordRecovery.authenticate(id, token)

      on user.nil? do
        notfound("The URL you specified might have expired.")
      end

      on post, param("user") do |params|
        reset = PasswordReset.new(params)

        if reset.valid?
          user.update(password: reset.password) && authenticate(user)

          session[:success] = "Password has been reset successfully."
          res.redirect "/dashboard"
        else
          res.write view("password/reset", id: id, token: token,
                         title: "Password Reset", reset: reset)
        end
      end

      on default do
        reset = PasswordReset.new({})

        res.write view("password/reset", id: id, token: token,
                       title: "Password Reset", reset: reset)
      end
    end
  end
end
