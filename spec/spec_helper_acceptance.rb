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

# Install a SIMP packagecloud yum repo
#
# - Each repo is modeled after what appears in simp-doc
# - See https://packagecloud.io/simp-project/ for the reponame key
#
# +host+: Host object on which SIMP repo(s) will be installed
# +reponame+: The base name of the repo, e.g. '6_X'
# +type+: Which repo to install:
#   :main for the main repo containing SIMP puppet modules
#   :deps for the SIMP dependency repo containing OS or application
#         RPMs not available from standard CentOS repos
#
# @fails if the specified repo cannot be installed on host
def install_internet_simp_repo(host, reponame, type)
  case type
  when :main
    full_reponame = reponame
    # FIXME: Use a gpgkey list appropriate for more than 6_X
    repo = <<~EOM
      [simp-project_#{reponame}]
      name=simp-project_#{reponame}
      baseurl=https://packagecloud.io/simp-project/#{reponame}/el/$releasever/$basearch
      gpgcheck=1
      enabled=1
      gpgkey=https://raw.githubusercontent.com/NationalSecurityAgency/SIMP/master/GPGKEYS/RPM-GPG-KEY-SIMP
             https://download.simp-project.com/simp/GPGKEYS/RPM-GPG-KEY-SIMP-6
      sslverify=1
      sslcacert=/etc/pki/tls/certs/ca-bundle.crt
      metadata_expire=300
    EOM
  when :deps
    full_reponame = "#{reponame}_Dependencies"
    # FIXME: Use a gpgkey list appropriate for more than 6_X
    repo = <<~EOM
      [simp-project_#{reponame}_dependencies]
      name=simp-project_#{reponame}_dependencies
      baseurl=https://packagecloud.io/simp-project/#{reponame}_Dependencies/el/$releasever/$basearch
      gpgcheck=1
      enabled=1
      gpgkey=https://raw.githubusercontent.com/NationalSecurityAgency/SIMP/master/GPGKEYS/RPM-GPG-KEY-SIMP
             https://download.simp-project.com/simp/GPGKEYS/RPM-GPG-KEY-SIMP-6
             https://yum.puppet.com/RPM-GPG-KEY-puppetlabs
             https://yum.puppet.com/RPM-GPG-KEY-puppet
             https://apt.postgresql.org/pub/repos/yum/RPM-GPG-KEY-PGDG-96
             https://artifacts.elastic.co/GPG-KEY-elasticsearch
             https://grafanarel.s3.amazonaws.com/RPM-GPG-KEY-grafana
             https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-$releasever
      sslverify=1
      sslcacert=/etc/pki/tls/certs/ca-bundle.crt
      metadata_expire=300
    EOM
    full_reponame = "#{reponame}_Dependencies"
  else
    fail("install_internet_simp_repo() Unknown repo type specified '#{type.to_s}'")
  end
  puts('='*72)
  puts("Using SIMP #{full_reponame} Internet repo from packagecloud")
  puts('='*72)

  create_remote_file(host, "/etc/yum.repos.d/simp-project_#{full_reponame.downcase}.repo", repo)
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
# - Otherwise, BEAKER_repo is assumed to be the base name of the SIMP
#   internet repos (e.g., '6_X_Alpha')
#
# +host+: Host object on which SIMP repo(s) will be installed
# +set_up_simp_main+:  Whether to set up the main SIMP repo
# +set_up_simp_deps+:  Whether to set up the SIMP dependencies repo
#
# @fails if the specified repos cannot be installed on host
def set_up_simp_repos(host, set_up_simp_main = true, set_up_simp_deps = true )
  reponame = ENV['BEAKER_repo']
  reponame ||= '6_X'
  if reponame[0] == '/'
    copy_repo(host, reponame)
  else
    install_internet_simp_repo(host, reponame, :main) if set_up_simp_main
    install_internet_simp_repo(host, reponame, :deps) if set_up_simp_deps
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
