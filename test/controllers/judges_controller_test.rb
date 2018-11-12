require 'test_helper'

class JudgesControllerTest < ActionDispatch::IntegrationTest
  test "should get judge" do
    get judges_judge_url
    assert_response :success
  end

end
