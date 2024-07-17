require 'spec_helper_acceptance'

# This test ASSUMES the latest simp-adapter RPM is in a yum database
# (i.e., the setup in 00_basic_test_spec has happened)

test_name 'simp-adapter upgrade operations'

# This test requires an old version of the simp-adapter which is only
# available in a legacy repo that supports EL < 8.
upgrade_hosts = hosts.select do |host|
  fact_on(host, 'os.release.major').to_s < '8'
end

unless upgrade_hosts.empty?
  describe 'simp-adapter upgrade operations' do
    let(:old_adapter_config_file) { '/etc/simp/adapter_config.yaml' }
    let(:new_adapter_config_file) { '/etc/simp/adapter_conf.yaml' }

    specify do
      step '[prep] Configure the legacy SIMP 6 repo'
      legacy_repo = <<~REPO
      [simp_legacy]
      baseurl=https://download.simp-project.com/simp/yum/simp6/el/$releasever/$basearch
      enabled=1
      gpgcheck=0
      sslverify=0
      REPO

      upgrade_hosts.each do |host|
        create_remote_file(host, '/etc/yum.repos.d/simp_legacy.repo', legacy_repo)
      end

      step '[prep] Configure yum for upstream SIMP repos'
      upgrade_hosts.each do |host|
        set_up_simp_repos(host)
        on(host, 'yum clean all; yum makecache')
      end
    end

    upgrade_hosts.each do |host|
      context "Upgrading simp-adapter from version <= 0.1.1 on #{host.hostname}" do
        before :each do
          step '[prep] Revert to old version of simp-adapter'
          host.uninstall_package('simp-adapter')
          host.uninstall_package('puppet-agent')
          host.install_package('simp-adapter-0.1.1')
        end

        context 'When old adapter config has local modifications' do
          it 'removes old, modified adapter config' do
            old_config = {
              'target_directory' => '/usr/share/simp/modules',
              'copy_rpm_data'    => true
            }
            create_remote_file(host, old_adapter_config_file, old_config.to_yaml)

            # upgrade to latest simp-adapter
            host.install_package('simp-adapter')

            # verify old config has been removed, but new config remains
            on(host, "ls -l #{File.dirname(old_adapter_config_file)}")
            on(host, "ls #{new_adapter_config_file}")
            on(host, "ls #{old_adapter_config_file}*", acceptable_exit_codes: [2])
          end
        end
      end
    end
  end
end
