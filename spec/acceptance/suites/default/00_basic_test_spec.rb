require 'spec_helper_acceptance'

test_name 'simp-adapter'
# This test uses 3 of the 4 test module RPMs:
# - pupmod-simp-beakertest-0.0.1-0.noarch.rpm
#   - Has simp_rpm_helper in %post
# - pupmod-simp-beakertest-0.0.3-0.noarch.rpm
#   - Has simp_rpm_helper in %posttrans
#   - Has an empty spec/fixtures/simp_rspec directory, which will not be checked
#     into git
# - pupmod-simp-site-2.0.5-0.noarch.rpm
#   - Has simp_rpm_helper in %posttrans

describe 'simp-adapter' do
  let(:local_yum_repo) {'/srv/local_yum' }

  context 'Initial test prep on each host' do
    specify do
      step '[prep] Install OS packages'
      yum_packages = ['createrepo','yum-utils']
      cmd = yum_packages.map{|pkg| "puppet resource package #{pkg} ensure=installed" }.join(' && ')
      on(hosts,cmd)

      result = on(hosts[0], 'cat /etc/oracle-release', :accept_all_exit_codes => true)
      if result.exit_code == 0
        # problem with OEL repos...need optional repos enabled in order
        # for all the rvm build dependencies to resolve
        on(hosts, 'yum-config-manager --enable ol7_optional_latest')
      end

      step '[prep] Copy pre-built simp-adapter RPMs to hosts'
      on(hosts, "mkdir -p #{local_yum_repo}")
      dist_dir = File.expand_path(File.join(File.dirname(__FILE__), '..','..', '..', '..', 'dist'))
      rpms = Dir.glob(File.join(dist_dir, '*noarch.rpm'))
      puts "Local simp-adapter RPMs: #{rpms}"
      expect( rpms.size ).to eq 1
      hosts.each do |host|
        rpms.each{|rpm| scp_to(host, rpm, local_yum_repo) }
      end

      step '[prep] Copy pre-built test RPMs to hosts'
      test_rpm_src = File.join(fixtures_path,'test_module_rpms')
      rpms = Dir.glob(File.join(test_rpm_src,'*.rpm'))
      hosts.each do |host|
        rpms.each{|rpm| scp_to(host, rpm, local_yum_repo) }
      end
    end

    specify do
      step '[prep] Create git_user for other tests'
      on(hosts,'useradd -b /home -m -c "Build User" -s /bin/bash -U git_user')
    end

    specify do
      step '[prep] Create a local yum repo'
      local_yum_repo_conf = <<-EOM
[local_yum]
name=Local Repos
baseurl=file://#{local_yum_repo}
enabled=1
gpgcheck=0
repo_gpgcheck=0
    EOM

      on(hosts, "cd #{local_yum_repo} && createrepo .")
      create_remote_file(hosts, '/etc/yum.repos.d/beaker_local.repo', local_yum_repo_conf)
    end
  end

  hosts.each do |host|
    context "on host #{host}" do
      let(:mod_version) { '0.0.3' } # the latest valid module version in the repo
      let(:mod_install_dir) { '/usr/share/simp/modules/beakertest' }
      let(:mod_repo_dir) { '/usr/share/simp/git/puppet_modules/simp-beakertest.git' }
      let(:mod_repo_url) { "file://#{mod_repo_dir}" }
      let(:module_reinstall_cmd) { 'yum reinstall -y pupmod-simp-beakertest' }
      let(:get_refs_cmd) { 'git log --pretty=format:"%H"' }

      context 'Module RPM install' do
        it 'should install as a module RPM dependency' do
          host.install_package('pupmod-simp-beakertest')
          host.check_for_package('simp-adapter')
        end

        it 'should create an accessible central repo for the module' do
          on(host, "test -d #{mod_repo_dir}")
          on(host, "git clone #{mod_repo_url}")
          on(host, "runuser git_user -l -c 'git clone #{mod_repo_url}'")
        end

        it "should check the installed version into the repo's master branch" do
          # Need to exclude empty fixtures directories included in the test RPMs,
          # as they will not be checked into git
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, 'master', ['fixtures'])
        end

        it 'should create a tag for the installed module version' do
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, mod_version, ['fixtures'])
        end
      end

      context 'Module RPM reinstall when module repo exists' do
        it 'should allow reinstalls' do
          on(host, module_reinstall_cmd)
        end

        it "should do nothing to the module's central repo if current" do
          # save off the ref for master and the version tag before a reinstall
          on(host, 'rm -rf /root/simp-beakertest')
          on(host, "git clone #{mod_repo_url}")

          master_ref_cmd = 'cd simp-beakertest; ' + get_refs_cmd
          before_master_ref = on(host, master_ref_cmd).stdout.split("\n").first

          tag_ref_cmd = "cd simp-beakertest; git checkout tags/#{mod_version}; " + get_refs_cmd
          before_tag_ref = on(host, tag_ref_cmd).stdout.split("\n").first

          # reinstall
          on(host, module_reinstall_cmd)

          # compare the before refs with their current ones
          on(host, 'rm -rf /root/simp-beakertest')
          on(host, "git clone #{mod_repo_url}")

          after_master_ref = on(host, master_ref_cmd).stdout.split("\n").first
          after_tag_ref = on(host, tag_ref_cmd).stdout.split("\n").first

          expect(before_master_ref).to eq after_master_ref
          expect(before_tag_ref).to eq after_tag_ref
        end
      end

      context 'Module RPM reinstall when module tag has been munged' do
        specify do
          step '[prep] munge the module tag' do
            # munge the tag
            on(host, 'rm -rf /root/simp-beakertest')
            on(host, "git clone #{mod_repo_url}")
            on(host, "cd simp-beakertest; git checkout tags/#{mod_version}")
            on(host, 'cd simp-beakertest; git checkout -b munge')
            on(host, "cd simp-beakertest; echo 'This is a test module' > README")
            on(host, 'cd simp-beakertest; git add README')
            on(host, 'cd simp-beakertest; git config user.name "munger"')
            on(host, 'cd simp-beakertest; git config user.email "munger@test.local"')
            on(host, 'cd simp-beakertest; git commit -m "Add a README"')
            on(host, "cd simp-beakertest; git tag -a -f -m 'Munge #{mod_version}' #{mod_version}")
            on(host, "cd simp-beakertest; git push origin #{mod_version} -f")

            # verify it is munged
            on(host, "git clone #{mod_repo_url} simp-beakertest-munged")
            on(host, "cd simp-beakertest-munged; git checkout tags/#{mod_version}")
            on(host, 'ls simp-beakertest-munged/README')
          end
        end

        it 'should replace munged tag on reinstall' do
          on(host, module_reinstall_cmd)
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, mod_version, ['fixtures'])
        end
      end

      context 'Module RPM reinstall when module repo does not exist' do
        it 'should reinstall' do
          on(host, "rm -rf #{mod_repo_dir}")
          on(host, 'rm -rf /root/simp-beakertest*')
          on(host, module_reinstall_cmd)
        end

        it 'should create an accessible central repo for the module' do
          on(host, "test -d #{mod_repo_dir}")
          on(host, "git clone #{mod_repo_url}")
        end

        it "should check the reinstalled version into the repo's master branch" do
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, 'master', ['fixtures'])
        end

        it 'should create a tag for the reinstalled module version' do
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, mod_version, ['fixtures'])
        end
      end

      context 'Module RPM uninstall' do
        it 'should uninstall cleanly' do
          # save off a clean checkout for comparison
          on(host, "git clone #{mod_repo_url} simp-beakertest-save")
          host.uninstall_package('pupmod-simp-beakertest')
        end

        it 'should not remove the central repo for the module' do
          on(host, "test -d #{mod_repo_dir}")
        end

        it 'should not modify the central repo for the module' do
          # verify master branch is intact
          compare_to_repo_branch(host, '/root/simp-beakertest-save', mod_repo_url, 'master')

          # verify module tag is intact
          on(host, "cd simp-beakertest-save; git checkout tags/#{mod_version}")
          compare_to_repo_branch(host, '/root/simp-beakertest-save', mod_repo_url, mod_version)
        end
      end

      context 'Skipped module RPM install' do
        it 'should not prevent module install' do
          host.install_package('pupmod-simp-site')
        end

        it 'should not create an accessible central repo for the module' do
          on(host, "test ! -d '/usr/share/simp/git/puppet_modules/simp-site.git'")
        end
      end

      # Installation of an old SIMP RPM with the call to simp_rpm_helper
      # erroneously in the %post instead of the %posttrans
      context 'Invalid module RPM install' do
        let(:bad_module_version) { '0.0.1' }
        let(:install_fix_cmd) do
          [
            'simp_rpm_helper',
            '--rpm_dir=/usr/share/simp/modules/beakertest',
            '--rpm_section=posttrans',
            '--rpm_status=1'
          ].join(' ')
        end

        it 'should not prevent the module install' do
          # start clean
          on(host, "rm -rf #{mod_repo_dir}")
          result = on(host, "yum install -y pupmod-simp-beakertest-#{bad_module_version}")

          # verify user told how to fix
          expect(result.stdout).to match(/Manually execute the following to fix:/)
          expect(result.stdout).to match(/#{Regexp.escape(install_fix_cmd)}/)
        end

        it 'should not create the central repo for the module' do
          on(host, "test ! -d #{mod_repo_dir}")
        end

        it 'fix command should create the central repo and import the version' do
          on(host, install_fix_cmd)
          on(host, "test -d #{mod_repo_dir}")
          # This older RPM does not include an empty spec/fixtures/simp_rspec directory
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, 'master')
          compare_to_repo_branch(host, mod_install_dir, mod_repo_url, bad_module_version)
        end
      end

      context 'simp-adapter RPM uninstall' do
        it 'should uninstall cleanly' do
          host.uninstall_package('simp-adapter')
          # all remnants of the working dir should be gone
          on(host, 'test ! -d /var/lib/simp-adapter')
        end
      end
    end
  end
end
