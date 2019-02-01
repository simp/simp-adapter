$: << File.expand_path(File.join(File.dirname(__FILE__), '..','..','..', 'tests'))
require 'spec_helper'
require 'simp_rpm_helper'

# simp_rpm_helper, as a ruby script with a puppet-provided vendor ruby as a shebang
#   was difficult or impossible to test, so there was as symlink created in the
#   tests/ directory to rename the file to a proper '.rb'.
describe 'SimpRpmHelper' do

  # usage has name simp_rpm_helper.rb, not simp_rpm_helper, because we are
  # testing with a simp_rpm_helper.rb link.  We need this link in order to
  # gather test code coverage with SimpleCov.
  let(:script) { 'simp_rpm_helper.rb'}

  let(:mock_puppet_config) {
    <<-EOM
user = puppet
group = 'puppet
codedir = /etc/puppetlabs/code/
   EOM
  }

  let(:usage) {
    <<-EOM
Usage: #{script} -d DIR -s SECTION -S STATUS [options]

    -d, --rpm_dir DIR                The fully qualified path to the directory
                                     into which the module's RPM source material
                                     is installed.
    -s, --rpm_section SECTION        The section of the RPM from which the
                                     script is being called: 'pre', 'preun'
                                     'post', 'postun', 'posttrans'
    -S, --rpm_status STATUS          The status code passed to the RPM section.
                                     When --rpm_section is 'posttrans', should
                                     be '2' for an upgrade and '1' for an
                                     initial install.
    -f, --config CONFIG_FILE         The configuration file overriding defaults.
                                         Default: /etc/simp/adapter_config.yaml
    -t, --target_dir DIR             The fully qualified path to the parent
                                     directory of the module Git repository.
                                     This repository will be created/updated
                                     using materials found in --rpm_dir.
                                         Default:
                                         /usr/share/simp/git/puppet_modules
    -w, --work_dir DIR               The fully qualified path for a temporary
                                     work directory.
                                         Default: /var/lib/simp-adapter/git
    -a, --git_author AUTHOR          The (non-empty) author to use for commits
                                     to the module Git repo.
                                         Default: #{script}
    -e, --git_email EMAIL            The email address to use for commits
                                     to the module Git repo.
                                         Default: root@#{`hostname -f`.strip}
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
# TODO re-enable when R10k option is added to simp_rpm_helper
#        allow(@helper).to receive(:`).with('puppet config --section master print').and_return(mock_puppet_config)
        expect{ @helper.run(['-h']) }.to output(usage).to_stdout
        expect( @helper.run(['-h']) ).to eq(0)
      end
    end

    context 'error cases' do
      it 'should fail and print help with invalid option' do
        expected = <<-EOF
#{script} ERROR: invalid option: -x

#{usage.strip}
        EOF
#        allow(@helper).to receive(:`).with('puppet config --section master print').and_return(mock_puppet_config)
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
