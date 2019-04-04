require 'spec_helper_acceptance'

test_name 'simp-adapter in RPM upgrade/downgrade'

# This test uses 2 of the 3 test module RPMs:
# - pupmod-simp-beakertest-0.0.2-0.noarch.rpm
# - pupmod-simp-beakertest-0.0.3-0.noarch.rpm
#   - Has directory difference from pupmod-simp-beakertest-0.0.2
#
# Both RPMs have simp_rpm_helper in %posttrans and empty spec/fixtures/simp_rspec/
# directories.
#
version1 = '0.0.2'
version2 = '0.0.3'
package1 = "pupmod-simp-beakertest-#{version1}"
package2 = "pupmod-simp-beakertest-#{version2}"

describe 'simp-adapter in RPM upgrade/downgrade' do

  hosts.each do |host|
    context "on host #{host.hostname}" do
      let(:mod_install_dir) { '/usr/share/simp/modules/beakertest' }
      let(:mod_repo_dir) { '/usr/share/simp/git/puppet_modules/simp-beakertest.git' }
      let(:mod_repo_url) { "file://#{mod_repo_dir}" }

      context 'Test prep' do
        it 'should start clean' do
          # make sure any remnants for earlier tests are not hanging around
          on(host,'yum erase pupmod-simp-beakertest -y', :accept_all_exit_codes => true)
          on(host, "rm -rf #{mod_repo_dir}")
          on(host, 'rm -rf /root/simp-beakertest*')
        end
      end

      context 'Module RPM upgrade when module repo exists' do
        it 'should install the first version' do
          on(host, "yum install #{package1} -y")
        end

        it 'should create a central repo with the first version on the master branch' do
          on(host, "test -d #{mod_repo_dir}")
          # Need to exclude empty fixtures directories included in the test RPMs,
          # as they will not be checked into git
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, 'master', ['fixtures'])
        end

        it 'should create a tag for the first version' do
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, version1, ['fixtures'])

          # save off a checkout of the repo after the first install for comparison
          on(host, "git clone #{mod_repo_url} simp-beakertest-save1")
        end

        it 'should upgrade to the second version' do
          on(host, "yum upgrade #{package2} -y")
        end

        it "should update the repo's master branch with the second version" do
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, 'master', ['fixtures'])
        end

        it 'should create a tag for the second version' do
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, version2, ['fixtures'])

          # save off a checkout of the repo after the upgrade for comparison
          on(host, "git clone #{mod_repo_url} simp-beakertest-save2")
        end

        it 'should still have a tag for the first version' do
          on(host, "cd simp-beakertest-save1; git checkout tags/#{version1}")
          compare_to_repo_branch(host, '/root/simp-beakertest-save1', mod_repo_url, version1)
        end
      end

      context 'Module RPM downgrade' do
        it 'should downgrade cleanly' do
          on(host, "yum downgrade #{package1} -y")
        end

        it "should update the repo's master branch with the older version" do
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, 'master', ['fixtures'])
        end

        it 'should have a tag for the older version' do
          on(host, "cd simp-beakertest-save1; git checkout tags/#{version1}")
          compare_to_repo_branch(host, '/root/simp-beakertest-save1', mod_repo_url, version1)
        end

        it 'should still have a tag for the newer version' do
          on(host, "cd simp-beakertest-save2; git checkout tags/#{version2}")
          compare_to_repo_branch(host, '/root/simp-beakertest-save2', mod_repo_url, version2)
        end

        it 'should keep history of version changes in git log' do
          on(host, 'rm -rf /root/simp-beakertest*')
          on(host, "git clone #{mod_repo_url} simp-beakertest")
          result = on(host, 'cd simp-beakertest; git log --pretty=format:"%an %ae %s"')

          expected = [
            "simp_rpm_helper root@localhost.localdomain Imported version #{version1}",  # downgrade
            "simp_rpm_helper root@localhost.localdomain Imported version #{version2}",  # upgrade
            "simp_rpm_helper root@localhost.localdomain Imported version #{version1}",  # initial install
          ].join("\n")

          expect(result.stdout.strip).to eq expected
        end
      end

      context 'Module RPM upgrade when module repo does not exist' do
        it 'should upgrade cleanly' do
          on(host, "rm -rf #{mod_repo_dir}")
          on(host, "yum upgrade #{package2} -y")
        end

        it 'should create a central repo with the newer version on the master branch' do
          on(host, "test -d #{mod_repo_dir}")
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, 'master', ['fixtures'])
        end

        it 'should create a tag for the newer version' do
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, version2, ['fixtures'])
        end
      end

      context 'Module RPM downgrade when module repo does not exist' do
        it 'should downgrade cleanly' do
          on(host, "rm -rf #{mod_repo_dir}")
          on(host, "yum downgrade #{package1} -y")
        end

        it 'should create a central repo with the older version on the master branch' do
          on(host, "test -d #{mod_repo_dir}")
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, version1, ['fixtures'])
        end

        it 'should create a tag for the older version' do
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, version1, ['fixtures'])
        end
      end
    end
  end
end
