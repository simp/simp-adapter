#!/usr/bin/rake -T

require 'rspec/core/rake_task'
require 'rake/clean'
require 'rake/packagetask'
require 'simp/rake'
require 'simp/rake/beaker'

# coverage/ contains SimpleCov results
CLEAN.include 'coverage'

# 'src' is not one of the standard directories specified by
# the :spec_standlone task in puppetlabs_spec_helper/rake_tasks.rb.
# Since we can't override Rake task, need to remove that task and
# then create a new one with the same name.
Rake.application.instance_variable_get('@tasks').delete('spec_standalone')
desc "Run spec tests"
RSpec::Core::RakeTask.new(:spec_standalone) do |t|
  t.rspec_opts = ['--color']
  t.pattern = 'spec/src/**/*_spec.rb'
end

# Package Tasks
Simp::Rake::Pkg.new(File.dirname(__FILE__))

# Acceptance Tests
Simp::Rake::Beaker.new(File.dirname(__FILE__))

# make sure pkg:rpm is a prerequisite for beaker:suites and tell
# user that is what is happening during the loooooong pause before
# the test spins up
task :log_pkg_rpm do
  puts 'Custom test prep: Building simp-adapter RPM...'
end

Rake::Task['beaker:suites'].enhance [:log_pkg_rpm, 'pkg:rpm']

