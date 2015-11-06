require 'bundler'
require 'rspec/core/rake_task'
require "tempfile"
require 'rdoc/task'

namespace :spec do
  desc "Run only unit specs"
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = "spec/unit/*"
  end

  desc "Run specs with in-memory database"
  RSpec::Core::RakeTask.new(:memory) do |t|
    ENV["SQS_DATABASE"] = ":memory:"
    t.pattern = "spec/integration/*"
  end

  desc "Run specs with file database"
  RSpec::Core::RakeTask.new(:file) do |t|
    file = Tempfile.new(["rspec-sqs", ".yml"], encoding: "utf-8")
    ENV["SQS_DATABASE"] = file.path
    t.pattern = "spec/integration/*"
  end
end

desc "Run spec suite with both in-memory and file"
task :spec => ["spec:memory", "spec:file"]
#task :spec => ["spec:unit", "spec:memory", "spec:file"]

task :default => :spec

Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "sqs_web #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

Bundler::GemHelper.install_tasks
