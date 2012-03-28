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

    assert mail.text.include?("/#{u.id}/#{u.key[:password_reset_token].get}")
  end
end
