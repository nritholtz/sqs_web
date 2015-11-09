require 'bundler'
require 'rspec/core/rake_task'
require 'rdoc/task'

namespace :spec do
  desc "Run specs with in-memory database"
  RSpec::Core::RakeTask.new(:memory) do |t|
    ENV["SQS_DATABASE"] = ":memory:"
    t.pattern = "spec/integration/*"
  end
end

desc "Run spec suite with in-memory"
task :spec => ["spec:memory"]

task :default => :spec

Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "sqs_web #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

Bundler::GemHelper.install_tasks
