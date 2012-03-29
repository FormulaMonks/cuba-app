require File.expand_path("helper", File.dirname(__FILE__))

scope do
  setup do
    Ohm.flush
    User.create(email: "foo@bar.com", password: "pass1234")
  end

  test "home" do
    visit "/"

    assert has_content?("Cuba")
  end
end
