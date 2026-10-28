# Coverage, first so it sees every file load. CI puts the totals and the
# least-covered files in the job summary (script/coverage_summary.rb);
# locally, open coverage/index.html after a run.
require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
  Kernel.srand config.seed
end
