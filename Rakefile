#!/usr/bin/rake -T

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

# make sure pkg:rpm is a prerequisite for beaker:suites and tell
# user that is what is happening during the loooooong pause before
# the test spins up
task :log_pkg_rpm => :clean do
  puts 'Custom test prep: Building simp-adapter RPM...'
end

Rake::Task['beaker:suites'].enhance [:log_pkg_rpm, 'pkg:rpm']

