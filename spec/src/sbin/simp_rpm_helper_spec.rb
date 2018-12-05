$: << File.expand_path(File.join(File.dirname(__FILE__), '..','..','..', 'tests'))
require 'spec_helper'
require 'simp_rpm_helper'

# simp_rpm_helper, as a ruby script with a puppet-provided vendor ruby as a shebang
#   was difficult or impossible to test, so there was as symlink created in the
#   tests/ directory to rename the file to a proper '.rb'.
describe 'SimpRpmHelper' do

  let(:mock_puppet_config) {
    <<-EOM
user = puppet
group = 'puppet
codedir = /etc/puppetlabs/code/
   EOM
  }

  let(:usage) {
    # usage has name simp_rpm_helper.rb, not simp_rpm_helper, because we are
    # testing with a simp_rpm_helper.rb link.  We need this link in order to
    # gather test code coverage with SimpleCov.
    <<-EOM
Usage: simp_rpm_helper.rb [options]

        --rpm_dir PATH               The directory into which the RPM source material is installed
        --rpm_section SECTION        The section of the RPM from which the script is being called.
                                         Must be one of 'pre', 'preun', 'postun', 'posttrans'
        --rpm_status STATUS          The status code passed to the RPM section
    -f, --config CONFIG_FILE         The configuration file to use.
                                         Default: /etc/simp/adapter_config.yaml
    -p, --preserve                   Preserve material in 'target_dir' that is not in 'rpm_dir'
    -e, --enforce                    If set, enforce the copy, regardless of the setting in the config file
                                         Default: false
    -t, --target_dir DIR             The subdirectory of /etc/puppetlabs/code/environments/
                                     into which to copy the materials.
                                         Default: simp/modules
    -v, --verbose                    Print out debug info when processing.
    -h, --help                       Help Message
    EOM
  }

  describe 'run' do
    before :each do
      @helper = SimpRpmHelper.new
    end

    context 'success cases' do

      it 'should print help' do
        allow(@helper).to receive(:`).with('puppet config --section master print').and_return(mock_puppet_config)
        expect{ @helper.run(['-h']) }.to output(usage).to_stdout
        expect( @helper.run(['-h']) ).to eq(0)
      end
    end

    context 'error cases' do
      it 'should fail and print help with invalid option' do
        expected = <<-EOF
Error: invalid option: -x

#{usage.strip}
        EOF
        allow(@helper).to receive(:`).with('puppet config --section master print').and_return(mock_puppet_config)
        expect{ @helper.run(['-x']) }.to output(expected).to_stderr
        expect( @helper.run(['-x']) ).to eq(1)
      end

=begin
      it 'should fail and print help if rpm_dir option is missing' do
      end

      it 'should fail and print help if rpm_status option is missing' do
      end

      it 'should fail and print help if rpm_section option is missing' do
      end

      it 'should fail and print help if invalid rpm_section option is specified' do
      end

      ['posttrans', 'preun', 'post'].each do |rpm_section|
        it "should fail and print help if invalid rpm_dir is not a found for #{rpm_section}" do
        end
      end

      it 'should fail and print help if rpm_status is not an integer' do
      end

      it 'should fail if puppet group cannot be determined' do
      end
=end
    end

  end
end
