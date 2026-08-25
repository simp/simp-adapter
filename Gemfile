gem_sources = ENV.fetch('GEM_SERVERS', 'https://rubygems.org').split(%r{[, ]+})

gem_sources.each { |gem_source| source gem_source }

group :test do
  puppet_version = ENV.fetch('PUPPET_VERSION', ['>= 8', '< 9'])
  openvox_version = ENV.fetch('OPENVOX_VERSION', puppet_version)
  gem 'openvox', openvox_version
  # simp_rpm_helper requires ostruct, which is a bundled gem in Ruby >= 3.5
  gem 'ostruct'
  gem 'rake'
  gem 'rspec'
  # renovate: datasource=rubygems versioning=ruby
  gem 'simp-rake-helpers', ENV.fetch('SIMP_RAKE_HELPERS_VERSION', '~> 6.0')
  gem 'simplecov'
end

group :development do
  gem 'pry'
  gem 'pry-byebug'
  gem 'pry-doc'
end

group :syntax do
  # rubocop, rubocop-rake, and rubocop-rspec are pulled in and version-pinned by
  # voxpupuli-test (via simp-rake-helpers); pinning them here conflicts with its
  # constraints. rubocop-performance is not a voxpupuli-test dependency, so it
  # stays explicit.
  gem 'rubocop-performance', '~> 1.26.0', require: false
end

group :system_tests do
  gem 'bcrypt_pbkdf'
  gem 'beaker'
  gem 'beaker-rspec'
  # renovate: datasource=rubygems versioning=ruby
  gem 'simp-beaker-helpers', ENV.fetch('SIMP_BEAKER_HELPERS_VERSION', '~> 3.1')
end

# Evaluate extra gemfiles if they exist
extra_gemfiles = [
  ENV.fetch('EXTRA_GEMFILE', ''),
  "#{__FILE__}.project",
  "#{__FILE__}.local",
  File.join(Dir.home, '.gemfile'),
]
extra_gemfiles.each do |gemfile|
  if File.file?(gemfile) && File.readable?(gemfile)
    eval(File.read(gemfile), binding) # rubocop:disable Security/Eval
  end
end
