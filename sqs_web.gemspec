Gem::Specification.new do |gem|
  gem.name        = "sqs_web"
  gem.version     = "0.0.3"
  gem.author      = "Nathaniel Ritholtz"
  gem.email       = "nritholtz@gmail.com"
  gem.homepage    = "https://github.com/nritholtz/sqs_web"
  gem.summary     = "Web interface for SQS inspired by delayed_job_web"
  gem.description = gem.summary
  gem.license     = "MIT"

  gem.executables = ["sqs_web"]

  gem.files = [
    "Gemfile",
    "README.markdown",
    "Rakefile",
    "sqs_web.gemspec"
  ] + %x{ git ls-files }.split("\n").select { |d| d =~ %r{^(lib|spec|bin)} }

  gem.extra_rdoc_files = [
    "README.markdown"
  ]

  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})

  gem.add_runtime_dependency "sinatra",      [">= 1.4.4"]
  gem.add_dependency 'aws-sdk', '~> 2'


  gem.add_development_dependency "rspec"
  gem.add_development_dependency "rails",     ["~> 3.0"]
  gem.add_development_dependency "capybara"
  gem.add_development_dependency "codeclimate-test-reporter"
  gem.add_development_dependency "byebug"
  gem.add_development_dependency "selenium-webdriver"
  #gem.add_development_dependency "fake_sqs",  ["~> 0.3.1"]
end
