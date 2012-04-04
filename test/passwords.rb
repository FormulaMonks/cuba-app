require_relative "helper"

scope do
  setup do
    User.create(email: "foo@bar.com", password: "pass1234")
  end

  test "proper password recovery" do |u|
    visit "/password/recovery"

    fill_in "email", with: "foo@bar.com"
    click_button "Next"

    assert has_content?("We've sent you password reset instructions.")

    assert_equal 1, Malone.deliveries.size

    mail = Malone.deliveries.last

    assert_equal "Password Reset Instructions", mail.subject
    assert_equal "foo@bar.com", mail.to

    u.reload

    secret_path = "/password/reset/#{u.id}/#{u.password_reset_token}"

    assert mail.text.include?(secret_path)

    visit secret_path

    fill_in "user[password]", with: "foobarbaz"
    fill_in "user[password_confirmation]", with: "foobarbaz"
    click_button "Reset Password"

    assert has_content?("Password has been reset successfully.")
  end
end
