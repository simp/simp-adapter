require 'beaker-rspec'
require 'tmpdir'
require 'yaml'
require 'simp/beaker_helpers'
require_relative 'acceptance/helpers/gitutils'

include Simp::BeakerHelpers
include Acceptance::Helpers::GitUtils


# Repository helper methods stolen from simp-core/spec/acceptance/helpers/repo_helper.rb

# Install a yum repo
#
# +host+: Host object on which the yum repo will be installed
# +repo_filename+: Path of the repo file to be installed
#
# @fails if the specified repo file cannot be installed on host
def copy_repo(host, repo_filename, repo_name = 'simp_manual.repo')
  if File.exists?(repo_filename)
    puts('='*72)
    puts("Using repos defined in #{repo_filename}")
    puts('='*72)
    scp_to(hosts, repo_filename, "/etc/yum.repos.d/#{repo_name}")
  else
    fail("File #{repo_filename} could not be found")
  end
end

# Set up SIMP repos on the host
#
# By default, the SIMP '6_X' repos available from packagecloud
# will be configured.  This can be overidden with the BEAKER_repo
# environment variable as follows:
# - When set to a fully qualified path of a repo file, the file will
#   be installed as a repo on the host.  In this case set_up_simp_main
#   and set_up_simp_deps are both ignored, as the repo file is assumed
#   to be configured appropriately.
# - Otherwise, BEAKER_repo should take the form
# `<simprelease>[,<simpreleasetype>]`. For instance, if you want to use release
# 6 from the unsable repos, you would pass `BEAKER_repo="6,unstable"`.
#
# +host+: Host object on which SIMP repo(s) will be installed
# +set_up_simp_main+:  Whether to set up the main SIMP repo
# +set_up_simp_deps+:  Whether to set up the SIMP dependencies repo
#
# @fails if the specified repos cannot be installed on host
def set_up_simp_repos(host, set_up_simp_main = true, set_up_simp_deps = true )
  reponame = ENV['BEAKER_repo']
  if reponame && reponame[0] == '/'
    copy_repo(host, reponame)
  else

    disable_list = []
    unless set_up_simp_main
      disable_list << 'simp-community-simp'
    end

    unless set_up_simp_deps
      disable_list << 'simp-community-epel'
      disable_list << 'simp-community-puppet'
      disable_list << 'simp-community-postgresql'
    end

    install_simp_repos(host, disable_list)

    if reponame
      simp_release, simp_releasetype = reponame.split(',')
      create_remote_file(host, '/etc/yum/vars/simprelease', simp_release)
      create_remote_file(host, '/etc/yum/vars/simpreleasetype', simp_releasetype)
    end
  end
end

unless ENV['BEAKER_provision'] == 'no'
  hosts.each do |host|
    # Install Puppet
    if host.is_pe?
      install_pe
    else
      install_puppet
    end
  end
end


RSpec.configure do |c|
  # ensure that environment OS is ready on each host
  fix_errata_on hosts

  # Detect cases in which no examples are executed (e.g., nodeset does not
  # have hosts with required roles)
  c.fail_if_no_examples = true

  # Readable test descriptions
  c.formatter = :documentation

  # Configure all nodes in nodeset
  c.before :suite do
    begin
      # Install modules and dependencies from spec/fixtures/modules
      copy_fixture_modules_to( hosts )
      server = only_host_with_role(hosts, 'server')

      # Generate and install PKI certificates on each SUT
      Dir.mktmpdir do |cert_dir|
        run_fake_pki_ca_on(server, hosts, cert_dir )
        hosts.each{ |sut| copy_pki_to( sut, cert_dir, '/etc/pki/simp-testing' )}
      end

      # add PKI keys
      copy_keydist_to(server)
    rescue StandardError, ScriptError => e
      if ENV['PRY']
        require 'pry'; binding.pry
      else
        raise e
      end
    end
  end
end
