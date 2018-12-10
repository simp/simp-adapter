require 'spec_helper_acceptance'

test_name 'simp-adapter in RPM upgrade'
# This tests the upgrade using 3 RPMs:
# - pupmod-simp-beakertest-0.0.1-0.noarch.rpm: has simp_rpm_helper in %post
# - pupmod-simp-beakertest-0.0.2-0.noarch.rpm: has simp_rpm_helper in %posttrans
# - pupmod-simp-beakertest-0.0.3-0.noarch.rpm: has simp_rpm_helper in %posttrans
#   and a directory difference from pupmod-simp-beakertest-0.0.2
#

shared_examples_for 'secondary package manager' do |first_version, second_version, test_downgrade, host|
  let(:first_package) { "pupmod-simp-beakertest-#{first_version}" }
  let(:second_package) { "pupmod-simp-beakertest-#{second_version}" }

  context "When upgrading from pupmod-simp-beakertest #{first_version} to #{second_version}" do

    it "should install pupmod-simp-beakertest #{first_version}" do
      on(host, "yum install #{first_package} -y")
    end

    it "should rsync contents of pupmod-simp-beakertest #{first_version} into the code directory" do
      # This verifies all files/dirs from the first package are copied
      on(host, "diff -r /usr/share/simp/modules/beakertest #{install_target}/environments/simp/modules/beakertest")
    end

    if second_version
      it "should upgrade to pupmod-simp-beakertest #{second_version}" do
        on(host, "yum upgrade #{second_package} -y")
      end

      it "should transfer contents of pupmod-simp-beakertest #{second_version} into the code directory" do
        # This verifies all files/dirs from the second package are copied and
        # no files only in the first package remain
        on(host, "diff -r /usr/share/simp/modules/beakertest #{install_target}/environments/simp/modules/beakertest")
      end

      if test_downgrade
        it "should downgrade to pupmod-simp-beakertest #{first_version}" do
          on(host, "yum downgrade #{first_package} -y")
        end

        it "should transfer contents of pupmod-simp-beakertest #{first_version} into the code directory" do
          # This verifies all files/dirs from the last package are copied and
          # no files only in the previous package remain
          on(host, "diff -r /usr/share/simp/modules/beakertest #{install_target}/environments/simp/modules/beakertest")
        end
      end
    end

    it "should remove rsync'd files on an erase" do
      on(host, "yum erase pupmod-simp-beakertest -y")
      on(host, "ls #{install_target}/environments/simp/modules/beakertest", acceptable_exit_codes: [2])
    end

  end
end


describe 'simp-adapter in RPM upgrade' do

  hosts.each do |host|
    context "on host #{host.hostname}" do
      let!(:install_target) do
        install_target = host.puppet['codedir']
        if !install_target || install_target.empty?
          install_target = host.puppet['confdir']
        end
        install_target
      end

      context 'Test prep' do
        it 'should start clean with copy enabled' do
          # make sure any remnants for earlier tests are not hanging around
          on(host,'yum erase pupmod-simp-beakertest -y', :accept_all_exit_codes => true)
          on(host, "rm -rf #{install_target}/environments/simp/modules/beakertest")

          # configure for copy upon RPM install
          config_yaml =<<-EOM
---
copy_rpm_data : true
          EOM
          create_remote_file(host, '/etc/simp/adapter_config.yaml', config_yaml)
        end
      end

      # Before upgrading, as a sanity check, make sure can cleanly install and
      # erase the RPMs in this test
      context 'RPM rpm install and erase' do
        it_should_behave_like('secondary package manager', '0.0.1', nil, nil, host)
        it_should_behave_like('secondary package manager', '0.0.2', nil, nil, host)
        it_should_behave_like('secondary package manager', '0.0.3', nil, nil, host)
      end

      context 'RPM upgrades and downgrades' do
        # don't test downgrade to 0.0.1, because that package has the bug
        # that does the rsync in the wrong place (%post instead of %posttrans)
        it_should_behave_like('secondary package manager', '0.0.1', '0.0.2', false, host)
        it_should_behave_like('secondary package manager', '0.0.2', '0.0.3', true, host)
      end
    end
  end
end
