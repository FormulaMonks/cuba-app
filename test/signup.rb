require_relative "helper"

scope do
  test "signup" do
    visit "/signup"

    fill_in "user[email]", with: "bar@baz.com"
    fill_in "user[password]", with: "pass1234"
    click_button "Signup"

    assert has_content?("You have successfully signed up.")
  end
end
