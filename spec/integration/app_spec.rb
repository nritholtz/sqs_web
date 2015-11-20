RSpec.describe "General Application features", :sqs do

  # basic smoke test all the tabs
  %w(overview dlq_console).each do |tab|
    specify "test_#{tab}" do
      visit "/sqs/#{tab}"
      expect(page.status_code).to eq 200
    end
  end
end
