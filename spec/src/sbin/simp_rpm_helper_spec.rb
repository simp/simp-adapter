$: << File.expand_path(File.join(File.dirname(__FILE__), '..','..','..', 'tests'))
require 'spec_helper'
require 'simp_rpm_helper'
require 'tmpdir'

# simp_rpm_helper, as a ruby script with a puppet-provided vendor ruby as a shebang
#   was difficult or impossible to test, so there was as symlink created in the
#   tests/ directory to rename the file to a proper '.rb'.
describe 'SimpRpmHelper' do

  # usage has name simp_rpm_helper.rb, not simp_rpm_helper, because we are
  # testing with a simp_rpm_helper.rb link.  We need this link in order to
  # gather test code coverage with SimpleCov.
  let(:script) { 'simp_rpm_helper.rb'}

  let(:files_dir) { File.join(File.dirname(__FILE__), 'files') }

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

    context 'options error cases' do
      it 'should fail and print help with invalid option' do
        expected = <<-EOF
#{script} ERROR: invalid option: -x

#{usage.strip}
        EOF
#        allow(@helper).to receive(:`).with('puppet config --section master print').and_return(mock_puppet_config)
        expect{ @helper.run(['-x']) }.to output(expected).to_stderr
        expect( @helper.run(['-x']) ).to eq(1)
      end

      it 'should fail and print help if rpm_dir option is missing' do
        expected = <<-EOF
#{script} ERROR: 'rpm_dir' is required

#{usage.strip}
        EOF
        expect{ @helper.run(['--rpm_section=posttrans', '--rpm_status=1']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_section=posttrans', '--rpm_status=1']) ).to eq(1)
      end

      it 'should fail if rpm_dir option is not an absolute path' do
        expected = "#{script} ERROR: 'rpm_dir' must be an absolute path\n"
        expect{ @helper.run(['--rpm_dir=oops', '--rpm_section=posttrans', '--rpm_status=1']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=oops', '--rpm_section=posttrans', '--rpm_status=1']) ).to eq(1)
      end

      it 'should fail and print help if rpm_status option is missing' do
        expected = <<-EOF
#{script} ERROR: 'rpm_status' is required

#{usage.strip}
        EOF
        expect{ @helper.run(['--rpm_dir=/some/dir', '--rpm_section=posttrans']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/some/dir', '--rpm_section=posttrans']) ).to eq(1)
      end

      it 'should fail and print help if rpm_section option is missing' do
        expected = <<-EOF
#{script} ERROR: 'rpm_section' is required

#{usage.strip}
        EOF
        expect{ @helper.run(['--rpm_dir=/some/dir', '--rpm_status=1']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/some/dir', '--rpm_status=1']) ).to eq(1)
      end

      it 'should fail and print help if invalid rpm_section option is specified' do
        expected = <<-EOF
#{script} ERROR: 'rpm_section' must be one of 'pre', 'post', 'preun', 'postun', 'posttrans'

#{usage.strip}
        EOF
        expect{ @helper.run(['--rpm_dir=/some/dir', '--rpm_section=oops', '--rpm_status=1']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/some/dir', '--rpm_section=oops', '--rpm_status=1']) ).to eq(1)
      end

      ['posttrans', 'preun' ].each do |rpm_section|
        it "should fail if rpm_dir is not a found for #{rpm_section}" do
          expected = "#{script} ERROR: Could not find 'rpm_dir': '/does/not/exist'\n"
          expect{ @helper.run(['--rpm_dir=/does/not/exist', "--rpm_section=#{rpm_section}", '--rpm_status=1']) }.to output(expected).to_stderr
          expect( @helper.run(['--rpm_dir=/does/not/exist', "--rpm_section=#{rpm_section}", '--rpm_status=1']) ).to eq(1)

        end
      end

      it 'should fail if rpm_status is not an integer' do
        expected = "#{script} ERROR: 'rpm_status' must be an integer: 'a'\n"
        expect{ @helper.run(['--rpm_dir=/var', '--rpm_section=preun', '--rpm_status=a']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/var', '--rpm_section=preun', '--rpm_status=a']) ).to eq(1)
      end

      it 'should fail if target_dir option is not an absolute path' do
        expected = "#{script} ERROR: 'target_dir' must be an absolute path\n"
        expect{ @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', '--target_dir=oops']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', '--target_dir=oops']) ).to eq(1)
      end

      it 'should fail if work_dir option is not an absolute path' do
        expected = "#{script} ERROR: 'work_dir' must be an absolute path\n"
        expect{ @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', '--work_dir=oops']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', '--work_dir=oops']) ).to eq(1)
      end

      it 'should fail if git_author option is empty' do
        expected = "#{script} ERROR: 'git_author' cannot be empty\n"
        expect{ @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', '--git_author=']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', '--git_author=']) ).to eq(1)
      end
    end

    context 'config file error cases' do
      it 'should fail if specified config file does not exist' do
        expected = "#{script} ERROR: Config file '/does/not/exist' does not exist\n"
        expect{ @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', '--config=/does/not/exist']) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', '--config=/does/not/exist']) ).to eq(1)
      end

      it 'should fail if specified config file cannot be parsed' do
        expected = /#{Regexp.escape("#{script} ERROR: Config file '#{__FILE__}' could not be processed")}/
        expect{ @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', "--config=#{__FILE__}"]) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', "--config=#{__FILE__}"]) ).to eq(1)
      end

      it 'should fail if git_author from config file is empty' do
        config_file = File.join(files_dir, 'config_invalid_git_author.yaml')
        expected = "#{script} ERROR: 'git_author' in '#{config_file}' cannot be empty\n"
        expect{ @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', "--config=#{config_file}"]) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', "--config=#{config_file}"]) ).to eq(1)
      end

      it 'should fail if target_dir from config file is not an absolute path' do
        config_file = File.join(files_dir, 'config_invalid_target_dir.yaml')
        expected = "#{script} ERROR: 'target_dir' in '#{config_file}' must be an absolute path\n"
        expect{ @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', "--config=#{config_file}"]) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', "--config=#{config_file}"]) ).to eq(1)
      end

      it 'should fail if work_dir from config file is not an absolute path' do
        config_file = File.join(files_dir, 'config_invalid_work_dir.yaml')
        expected = "#{script} ERROR: 'work_dir' in '#{config_file}' must be an absolute path\n"
        expect{ @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', "--config=#{config_file}"]) }.to output(expected).to_stderr
        expect( @helper.run(['--rpm_dir=/var', '--rpm_section=posttrans', '--rpm_status=1', "--config=#{config_file}"]) ).to eq(1)
      end

    end

=begin
    context 'git operation error cases' do
#TODO flesh out these error cases
      it 'should fail if xxx git operation fails' do
      end
    end

    context 'other error cases' do
# TODO re-enable when R10k option is added to simp_rpm_helper
      it 'should fail if puppet group cannot be determined' do
      end
    end
=end

  end
end
