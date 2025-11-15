gem_sources = ENV.fetch('GEM_SERVERS','https://rubygems.org').split(%r{[, ]+})

gem_sources.each { |gem_source| source gem_source }

group :test do
  gem 'hiera-puppet-helper'
  gem 'pathspec', '~> 0.2' if Gem::Requirement.create('< 2.6').satisfied_by?(Gem::Version.new(RUBY_VERSION.dup))
  # renovate: datasource=rubygems versioning=ruby
  gem 'puppet', ENV.fetch('PUPPET_VERSION',  ['>= 7', '< 9'])
  gem 'puppetlabs_spec_helper', '~> 8.0.0'
  gem 'rake'
  gem 'rspec'
  gem 'rspec-puppet'
  # renovate: datasource=rubygems versioning=ruby
  gem 'simp-rake-helpers', ENV.fetch('SIMP_RAKE_HELPERS_VERSION', '~> 5.24.0')
  gem 'simplecov'
end

group :development do
  gem 'pry'
  gem 'pry-byebug'
  gem 'pry-doc'
end

group :syntax do
  gem 'rubocop', '~> 1.81.0', require: false
  gem 'rubocop-performance', '~> 1.26.0', require: false
  gem 'rubocop-rake', '~> 0.7.0', require: false
  gem 'rubocop-rspec', '~> 3.8.0', require: false
end

group :system_tests do
  gem 'bcrypt_pbkdf'
  gem 'beaker'
  gem 'beaker-rspec'
  # renovate: datasource=rubygems versioning=ruby
  gem 'simp-beaker-helpers', ENV.fetch('SIMP_BEAKER_HELPERS_VERSION', '~> 2.0.0')
end
