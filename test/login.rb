require_relative "helper"

scope do
  setup do
    User.create(email: "foo@bar.com", password: "pass1234")
  end

  test "proper login" do
    visit "/login"

    fill_in "username", with: "foo@bar.com"
    fill_in "password", with: "pass1234"
    click_button "Login"

    assert has_content?("You have successfully logged in.")
  end

  test "blank login" do
    visit "/login"
    click_button "Login"

    assert has_content?("No username and/or password supplied.")
  end

  test "invalid login" do
    visit "/login"

    fill_in "username", with: "foo@bar.com"
    fill_in "password", with: "blabber"
    click_button "Login"

    assert has_content?("Invalid username and/or password combination.")
  end

  test "remember the login" do
    visit "/login"

    fill_in "username", with: "foo@bar.com"
    fill_in "password", with: "pass1234"
    check "remember"
    click_button "Login"

    assert_equal 14 * 86400, session["remember_for"]

    visit "/logout"
    assert_equal nil, session["remember_for"]
  end
end
