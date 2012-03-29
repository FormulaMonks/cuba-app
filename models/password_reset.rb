class PasswordReset < Scrivener
  attr_accessor :password
  attr_accessor :password_confirmation

  def validate
    assert_present :password

    assert password == password_confirmation,
      [:password_confirmation, :not_valid]
  end
end
