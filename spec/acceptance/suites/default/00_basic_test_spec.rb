require 'spec_helper_acceptance'

test_name 'simp-adapter'

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

      rpm_build_packages = [ 'openssl', 'git', 'rpm-build', 'gnupg2', 'libicu-devel',
        'libxml2', 'libxml2-devel', 'libxslt', 'libxslt-devel', 'rpmdevtools',
        'ruby-devel',
      ]
      cmd = rpm_build_packages.map{|pkg| "puppet resource package #{pkg} ensure=installed" }.join(' && ')
      on(hosts,cmd)

      gem_build_packages = ['libyaml-devel', 'glibc-headers', 'autoconf', 'gcc',
        'gcc-c++', 'glibc-devel', 'readline-devel', 'libffi-devel',
        'openssl-devel', 'automake', 'libtool', 'bison', 'sqlite-devel', 'tar',
        'patch'
      ]
      cmd = gem_build_packages.map{|pkg| "puppet resource package #{pkg} ensure=installed" }.join(' && ')
      on(hosts,cmd)

      step '[prep] Copy pre-built test RPMs to hosts'
      on(hosts, "mkdir -p #{local_yum_repo}")
      stub_rpm_src   = File.join(fixtures_path,'test_module_rpms')
      src_rpms = Dir.glob(File.join(stub_rpm_src,'*.rpm'))
      hosts.each do |host|
        src_rpms.each{|rpm| scp_to(host, rpm, local_yum_repo) }
      end
    end

    specify do
      step '[prep] Create build_user that has a simp-adapter project directory'
      # Allow the build user to perform privileged operations, so if the package
      # list is incomplete during rvm install, it will install packages via sudo
      # and fix the problem automatically
      on(hosts,"echo 'Defaults:build_user !requiretty' >> /etc/sudoers")
      on(hosts,"echo 'build_user ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers")
      on(hosts,'useradd -b /home -m -c "Build User" -s /bin/bash -U build_user')

      # Move simp-adapter files that were deployed as if they were a puppet module
      # (via .fixtures.yaml) to build_user's home dir
      on(hosts,'mv /etc/puppetlabs/code/environments/production/modules/simp-adapter /home/build_user')
      on(hosts,'chown -R build_user:build_user /home/build_user/simp-adapter')

      step '[prep] Install rvm for build_user'
      on(hosts,'runuser build_user -l -c "gpg2 --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3"')
      on(hosts,'runuser build_user -l -c "curl -sSL https://get.rvm.io | bash -s stable"')
      on(hosts,'runuser build_user -l -c "rvm install 2.4.4"')
      on(hosts,'runuser build_user -l -c "rvm use --default 2.4.4"')
      on(hosts,'runuser build_user -l -c "rvm all do gem install bundler --no-ri --no-rdoc"')

      step '[prep] Build simp-adapter RPM'
      on(hosts,'runuser build_user -l -c "cd simp-adapter; git init"') # git project required for pkg:rpm
      on(hosts,'runuser build_user -l -c "cd simp-adapter; bundle update; bundle exec rake clean"')
      on(hosts,'runuser build_user -l -c "cd simp-adapter; bundle exec rake pkg:rpm"')
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

      rpm_src = '/home/build_user/simp-adapter/dist'
      hosts.each do |host|
        on(host, "cp #{rpm_src}/#{host[:rpm_glob]} #{local_yum_repo}")
      end
      on(hosts, "cd #{local_yum_repo} && createrepo .")
      create_remote_file(hosts, '/etc/yum.repos.d/beaker_local.repo', local_yum_repo_conf)
    end
  end

  hosts.each do |host|
    context "on host #{host.hostname}" do
      let!(:install_target) do
        install_target = host.puppet['codedir']
        if !install_target || install_target.empty?
          install_target = host.puppet['confdir']
        end
        install_target
      end

      let!(:site_module_init){  "#{install_target}/environments/simp/modules/site/init.pp" }

      let!(:site_manifest){ <<-EOM
  class site {
    notify { "Hark! A Site!": }
  }
      EOM
      }

      specify do
        step '[prep] Create a "site" module'
        host.mkdir_p(File.dirname(site_module_init))
        create_remote_file(host, site_module_init, site_manifest)
      end

      context 'Installing The RPM' do
        it 'should install as a dependency' do
          host.install_package('pupmod-simp-beakertest')
          host.install_package('simp-environment')
          on(host, 'test -d /usr/share/simp/modules/beakertest')
          on(host, 'test -f /usr/share/simp/environment/simp/test_file')
          host.check_for_package('simp-adapter')
        end

        it 'should NOT copy anything by default' do
          on(host, "test ! -d #{install_target}/environments/simp/modules/beakertest")
          on(host, "test ! -f #{install_target}/environments/simp/test_file")
        end
      end

      context 'When Configured to Copy Data via the Config File' do
        it 'should start in a clean state' do
          host.uninstall_package('pupmod-simp-beakertest')
          host.uninstall_package('simp-environment')
          host.uninstall_package('simp-adapter')

          config_yaml =<<-EOM
---
copy_rpm_data : true
this_should_not_break_things : awwww_yeah
          EOM
          create_remote_file(host, '/etc/simp/adapter_config.yaml', config_yaml)
        end

        it 'should copy the module data into the appropriate location' do
          host.install_package('pupmod-simp-beakertest')
          on(host, "test -d #{install_target}/environments/simp/modules/beakertest")
          on(host, "diff -aqr /usr/share/simp/modules/beakertest #{install_target}/environments/simp/modules/beakertest")
        end

        it 'should have the environment data in the appropriate location' do
          host.install_package('simp-environment')
          on(host, "test -f #{install_target}/environments/simp/test_file")
          expect(
            on(host, "cat #{install_target}/environments/simp/test_file").output
          ).to match(%r{Just testing stuff})
        end

        it 'should uninstall cleanly' do
          host.uninstall_package('pupmod-simp-beakertest')
          host.uninstall_package('simp-environment')
          host.uninstall_package('simp-adapter')
          on(host, 'test ! -d /usr/share/simp/modules/beakertest')
          on(host, "test ! -d #{install_target}/environments/simp/modules/beakertest")
          on(host, "test ! -f #{install_target}/environments/simp/test_file")
        end

        it 'should not remove local module files upon module uninstall' do
          config_yaml =<<-EOM
---
copy_rpm_data : true
        EOM
          create_remote_file(host, '/etc/simp/adapter_config.yaml', config_yaml)
          host.install_package('pupmod-simp-beakertest')
          on(host, "echo 'this module is great' > #{install_target}/environments/simp/modules/beakertest/NOTES.txt")
          host.uninstall_package('pupmod-simp-beakertest')
          host.uninstall_package('simp-adapter')
          on(host, "test -d #{install_target}/environments/simp/modules/beakertest")
          on(host, "test -f #{install_target}/environments/simp/modules/beakertest/NOTES.txt")
          expect(
          on(host, "find #{install_target}/environments/simp/modules/beakertest | wc -l").output
          ).to eq "2\n"
        end
      end

      context "Installing with an already-managed target" do
        specify do
          step '[prep] Set up git in simp environment on hosts'
          on(hosts,'git config --global user.email "root@rooty.tooty"')
          on(hosts,'git config --global user.name "Rootlike Overlord"')
        end

        it 'should have a git-managed beakertest module' do
          host.mkdir_p("#{install_target}/environments/simp/modules/beakertest")
          create_remote_file(host, "#{install_target}/environments/simp/modules/beakertest/test_file", '# IMA TEST')
          on(host, "cd #{install_target}/environments/simp/modules/beakertest && git init . && git add . && git commit -a -m woo")
        end

        it 'should have a git-managed simp environment' do
          create_remote_file(host, "#{install_target}/environments/simp/git_controlled_file", '# IMA TEST')
          on(host, "cd #{install_target}/environments/simp && git init . && git add git_controlled_file && git commit -a -m woo")
        end

        it 'should install cleanly' do
          host.install_package('simp-environment')
          host.install_package('pupmod-simp-beakertest')
          on(host, 'test -d /usr/share/simp/modules/beakertest')
        end

        it 'should NOT copy the module data into the $codedir' do
          on(host, "test -d #{install_target}/environments/simp/modules/beakertest")
          on(
            host,
            "diff -aqr /usr/share/simp/modules/beakertest #{install_target}/environments/simp/modules/beakertest",
            :acceptable_exit_codes => [1]
          )
          expect(
            on(host, "cat #{install_target}/environments/simp/modules/beakertest/test_file").output
          ).to match(%r{IMA TEST})
        end

        it 'should uninstall cleanly' do
          host.uninstall_package('pupmod-simp-beakertest')
          host.uninstall_package('simp-environment')
          on(host, 'test ! -d /usr/share/simp/modules/beakertest')
          on(host, 'test ! -f /usr/share/simp/environment/simp/test_file')
        end

        it 'should NOT remove the functional module from the system' do
          on(host, "test -d #{install_target}/environments/simp/modules/beakertest")
        end

        it 'should NOT remove the git controlled environment materials from the system' do
          on(host, "test -f #{install_target}/environments/simp/git_controlled_file")
        end

        it 'should NOT affect the "site" module' do
          expect(
            on(host, "cat #{site_module_init}").output.strip
          ).to eq(site_manifest.strip)
        end
      end
    end
  end
end
