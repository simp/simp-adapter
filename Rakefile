require 'rspec/core/rake_task'
require 'rake/clean'
require 'rake/packagetask'
require 'simp/rake'
require 'simp/rake/beaker'
require 'simp/rake/ci'

# coverage/ contains SimpleCov results
CLEAN.include 'coverage'

desc "Run spec tests"
RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = ['--color']
  t.pattern = 'spec/src/**/*_spec.rb'
end

# Package Tasks
Simp::Rake::Pkg.new(File.dirname(__FILE__))

# Acceptance Tests
Simp::Rake::Beaker.new(File.dirname(__FILE__))

# simp:ci_* Rake tasks
Simp::Rake::Ci.new(File.dirname(__FILE__))
