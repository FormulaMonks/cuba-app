require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "home" do
    visit "/"

    assert has_content?("Cuba")
  end
end
