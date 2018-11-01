require 'spec_helper_acceptance'

# This test ASSUMES the latest simp-adapter RPM is in a yum database
# (i.e., the setup in 00_basic_test_spec has happened)

test_name 'simp-adapter hiera.yaml ops'

describe 'simp-adapter hiera.yaml ops' do
  let(:global_hiera)         { '/etc/puppetlabs/puppet/hiera.yaml' }
  let(:global_hiera_simp)    { '/etc/puppetlabs/puppet/hiera.yaml.simp' }
  let(:global_hiera_simpbak) { '/etc/puppetlabs/puppet/hiera.yaml.simpbak' }

  specify do
    step '[prep] Configure yum for SIMP PackageCloud repos'
    hosts.each { |host| set_up_simp_repos(host) }
    on(hosts, "yum clean all; yum makecache")
  end

  hosts.each do |host|
    context "Upgrading simp-adapter from version <= 0.6.0 on #{host.hostname}" do
      before :each do
         step '[prep] Revert to old verson of simp-adapter'
         host.uninstall_package('simp-adapter')
         host.uninstall_package('puppet-agent')
         host.install_package('simp-adapter-0.0.6')
         on(host, 'ls -l /etc/puppetlabs/puppet')
         # saving this off for later use
         on(host, 'cp /etc/puppetlabs/puppet/hiera.yaml.simp /tmp/hiera.yaml.simp')
      end

      context 'When global hiera.yaml is linked to hiera.yaml.simp' do
        it 'should retain hiera.yaml and hiera.yaml.simp' do
          # upgrade to latest simp-adapter, bringing in any dependency upgrades
          # (e.g., puppet-agent upgrade when upgrading to simp-adapter-0.1.0)
          host.install_package('simp-adapter')

          # verify config has been preserved
          on(host, 'ls -l /etc/puppetlabs/puppet')
          on(host, "ls #{global_hiera_simp}")
          result = on(host, "readlink #{global_hiera}")
          expect(result.stdout.strip).to eq File.basename(global_hiera_simp)
        end
      end

      context 'When global hiera.yaml is not linked to hiera.yaml.simp' do
        it 'should remove hiera.yaml.simp but not remove hiera.yaml' do
          # replace hiera.yaml link with a file that is different from hiera.yaml.simp
          on(host, "rm #{global_hiera}")
          on(host, "echo '# This is a copy' >> #{global_hiera}")
          on(host, "cat #{global_hiera_simp}  >> #{global_hiera}")

          # upgrade to latest simp-adapter, bringing in any dependency upgrades
          # (e.g., puppet-agent upgrade when upgrading to simp-adapter-0.1.0)
          host.install_package('simp-adapter')

          on(host, 'ls -l /etc/puppetlabs/puppet')
          on(host, "ls #{global_hiera_simp}", :acceptable_exit_codes => 2)
          on(host, "ls #{global_hiera}")
          on(host, "grep 'This is a copy' #{global_hiera}")
        end
      end
    end

    context "Uninstalling simp-adapter and legacy global Hiera 3 config exists on #{host.hostname}" do
      context 'When global hiera.yaml is linked to hiera.yaml.simp' do
        it 'should remove hiera.yaml and hiera.yaml.simp, but keep hiera.yaml.simpbak' do
          on(host, "cp -f /tmp/hiera.yaml.simp #{global_hiera_simp}")
          on(host, "cd #{File.dirname(global_hiera_simp)}; ln -fs #{File.basename(global_hiera_simp)} #{File.basename(global_hiera)}")
          on(host, "echo '# This is a backup (first)' >> #{global_hiera_simpbak}")
          host.install_package('simp-adapter')
          on(host, 'ls -l /etc/puppetlabs/puppet')

          host.uninstall_package('simp-adapter')
          on(host, 'ls -l /etc/puppetlabs/puppet')
          on(host, "ls #{global_hiera}",  :acceptable_exit_codes => 2)
          on(host, "ls #{global_hiera_simp}", :acceptable_exit_codes => 2)
          on(host, "ls #{global_hiera_simpbak}")
        end
      end

      context 'When global hiera.yaml is not a link to hiera.yaml.simp' do
        it 'should remove hiera.yaml.simp, but keep hiera.yaml and hiera.yaml.simpbak' do
          on(host, "cp -f /tmp/hiera.yaml.simp #{global_hiera_simp}")
          on(host, "rm -f #{global_hiera}")
          on(host, "echo '# This is a different copy' >> #{global_hiera}")
          on(host, "cat #{global_hiera_simp}  >> #{global_hiera}")
          on(host, "echo '# This is a backup (second)' >> #{global_hiera_simpbak}")
          host.install_package('simp-adapter')
          on(host, 'ls -l /etc/puppetlabs/puppet')

          host.uninstall_package('simp-adapter')
          on(host, 'ls -l /etc/puppetlabs/puppet')
          on(host, "ls #{global_hiera_simp}", :acceptable_exit_codes => 2)
          on(host, "ls #{global_hiera}")
          on(host, "grep 'This is a different copy' #{global_hiera}")
          on(host, "ls #{global_hiera_simpbak}")
        end
      end
    end
  end
end
