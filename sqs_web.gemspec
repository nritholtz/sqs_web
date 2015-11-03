Gem::Specification.new do |gem|
  gem.name        = "sqs_web"
  gem.version     = "0.0.1"
  gem.author      = "Nathaniel Ritholtz"
  gem.email       = "nritholtz@gmail.com"
  gem.homepage    = "https://github.com/nritholtz/sqs_web"
  gem.summary     = "Web interface for sqs inspired by resque"
  gem.description = gem.summary
  gem.license     = "MIT"

  gem.executables = ["sqs_web"]

  gem.files = [
    "Gemfile",
    "README.markdown",
    "Rakefile",
    "sqs_web.gemspec"
  ] + %x{ git ls-files }.split("\n").select { |d| d =~ %r{^(lib|test|bin)} }

  gem.extra_rdoc_files = [
    "README.markdown"
  ]

  gem.add_runtime_dependency "sinatra",      [">= 1.4.4"]
  gem.add_dependency 'aws-sdk', '~> 2.1.33'


  gem.add_development_dependency "minitest",  ["~> 4.2"]
  gem.add_development_dependency "rack-test", ["~> 0.6"]
  gem.add_development_dependency "rails",     ["~> 3.0"]
end
