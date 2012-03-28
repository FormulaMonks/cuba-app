require "securerandom"

module PasswordRecovery
  def self.init(user)
    token = SecureRandom.hex(10)

    user.key[:password_reset_token].setex(86400 * 2, token)

    deliver(user, token)
  end

  def self.deliver(user, token)
    Malone.deliver(from: Prelude::MAIL_FROM,
                   to: user.email,
                   subject: "Password Reset Instructions",
                   text: MESSAGE % [user.id, token])
  end

  MESSAGE = <<-EOT
    Greetings,

    You've recently requested to reset your password.

    To continue follow this link:

    http://#{Prelude::HOST}/password/reset/%s/%s
  EOT
end
