require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "home" do
    visit "/"

    assert has_content?("Cuba")
  end

  test "about" do
    visit "/about"

    assert_equal "<h1>About</h1>\n", page.source
  end
end
