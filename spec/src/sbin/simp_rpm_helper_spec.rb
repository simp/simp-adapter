$: << File.expand_path(File.join(File.dirname(__FILE__), '..','..','..', 'tests'))
require 'spec_helper'
require 'simp_rpm_helper'
require 'tmpdir'
require 'yaml'

############################################################################
# Most of simp_rpm_helper's processing is tested in the acceptance test,
# where simp_rpm_helper is called during module RPM installs, upgrades,
# uninstalls, and reinstalls in the %pre, %preun, %post|%posttrans, and
# %postun RPM sections. (Run `rpm -qp <test rpm name> --scripts` to see
# exactly how simp_adapter_rpm is called in each scriptlet).  The unit
# tests in this file fill in gaps in test coverage.
############################################################################

# simp_rpm_helper, as a ruby script with a puppet-provided vendor ruby as a shebang
#   was difficult or impossible to test, so there was as symlink created in the
#   tests/ directory to rename the file to a proper '.rb'.
describe 'SimpRpmHelper' do

  # usage has name simp_rpm_helper.rb, not simp_rpm_helper, because we are
  # testing with a simp_rpm_helper.rb link.  We need this link in order to
  # gather test code coverage with SimpleCov.
  let(:script) { 'simp_rpm_helper.rb'}

  let(:files_dir) { File.join(File.dirname(__FILE__), 'files') }
  let(:module_src_dir) {
    fixtures_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'fixtures'))
    File.join(fixtures_dir,'test_module_rpms', 'pupmod-simp-beakertest-0.0.3' )
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
                                         Default: /etc/simp/adapter_conf.yaml
    -t, --target_dir DIR             The fully qualified path to the parent
                                     directory of the module Git repository.
                                     This repository will be created/updated
                                     using materials found in --rpm_dir.
                                         Default:
                                         /usr/share/simp/git/puppet_modules
    -w, --work_dir DIR               The fully qualified path for a temporary
                                     work directory.
                                         Default: /var/lib/simp-adapter
    -p, --preserve                   DEPRECATED. This option is no longer used.
    -v, --verbose                    Print out debug info when processing.
    -h, --help                       Help Message
    EOM
  }


  describe 'run' do
    before :each do
      @helper = SimpRpmHelper.new
    end

    context 'help option' do
      it 'should print help' do
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

    context 'config file defaults exist' do
      # Will use the posttrans install operation for these tests,
      # as it is the operation that uses all of the default config
      # values

      before :each do
        @tmp_dir  = Dir.mktmpdir( File.basename(__FILE__))
      end

      after :each do
        FileUtils.remove_entry_secure @tmp_dir
      end

      it 'should use defaults for unspecified options' do
        config = {
          'target_dir' => File.join(@tmp_dir, 'repos'),
          'work_dir'   => File.join(@tmp_dir, 'work_dir'),
          'verbose'    => true
        }
        config_file = File.join(@tmp_dir, 'adapter_conf.yaml')
        File.open(config_file, 'w') { |file| file.puts config.to_yaml }

        args = [
          '-d', module_src_dir,
          '-s', 'posttrans',
          '-S', '1',
          '-f', config_file,
          '--preserve',  # unused option should be ignored
        ]
        one_verbose_msg = /Repo update completed/ # spot check one of the verbose messages
        expect{ @helper.run(args) }.to output(one_verbose_msg).to_stdout

        expect(File).to exist(config['target_dir'])
        module_repo_dir = File.join(config['target_dir'], 'simp-beakertest.git')
        expect(File).to exist(module_repo_dir)
        expect(File).to exist(config['work_dir'])
        expect(Dir.glob("#{config['work_dir']}/*")). to be_empty
      end

      it 'should use command line options in lieu of defaults' do
        config = {
          'target_dir' => File.join(@tmp_dir, 'repos1'),
          'work_dir'   => File.join(@tmp_dir, 'work_dir1'),
          'verbose'    => false
        }
        config_file = File.join(@tmp_dir, 'adapter_conf.yaml')
        File.open(config_file, 'w') { |file| file.puts config.to_yaml }

        override_repos_dir = File.join(@tmp_dir, 'repos2')
        override_work_dir  = File.join(@tmp_dir, 'work_dir2')
        args = [
          '-d', module_src_dir,
          '-s', 'posttrans',
          '-S', '1',
          '-f', config_file,
          '-t', override_repos_dir,
          '-w', override_work_dir,
          '-v'
        ]
        one_verbose_msg = /Repo update completed/ # spot check one of the verbose messages
        expect{ @helper.run(args) }.to output(one_verbose_msg).to_stdout

        expect(File).to exist(override_repos_dir)
        module_repo_dir = File.join(override_repos_dir, 'simp-beakertest.git')
        expect(File).to exist(module_repo_dir)
        expect(File).to exist(override_work_dir)
      end
    end

    context 'other failures' do
      let(:git_cmd) {  Facter::Core::Execution.which('git') }

      before :each do
        @tmp_dir  = Dir.mktmpdir( File.basename(__FILE__))
        @config = {
          'target_dir' => File.join(@tmp_dir, 'repos'),
          'work_dir'   => File.join(@tmp_dir, 'work_dir'),
          #'verbose'    => true
        }
        @config_file = File.join(@tmp_dir, 'adapter_conf.yaml')
        File.open(@config_file, 'w') { |file| file.puts @config.to_yaml }
        @module_repo_dir = File.join(@config['target_dir'], 'simp-beakertest.git')
      end

      after :each do
        FileUtils.remove_entry_secure @tmp_dir
      end

      it 'should fail when git init fails' do
        cmd = "#{git_cmd} init --bare #{@module_repo_dir}"
        err_msg = "Failed to create git repo at #{@module_repo_dir}"
        allow(@helper).to receive(:execute).with(cmd,err_msg).and_raise(SimpRpmHelper::CommandError, err_msg)
        args = [
          '-d', module_src_dir,
          '-s', 'posttrans',
          '-S', '1',
          '-f', @config_file
        ]
        expect( @helper.run(args) ).to eq 2
      end

=begin
simp_rpm_helper is not currently written in a way that allows testing
of the failure cases below, even with mocking.  This deficiency can be
addressed when this software is refactored into a library (Gem). In the
interim, we will **ASSUME** that the SimpRpmHelper#execute() failure cases
below are adequate:
- Each of these operations are affected by a call to SimpRpmHelper#execute
- The 'should fail when git init fails' test verifies that the exception
  raised by SimpRpmHelper#execute is appropriately caught and translated
  into a non-zero return code.

      pending 'should fail when git clone fails'
      pending 'should fail when rsync fails'
      pending 'should fail when git add fails'
      pending 'should fail when git push to master fails'
      pending 'should fail when git tag -a -f fails'
      pending 'should fail when git push of tag fails'
=end
    end
  end

  describe 'execute' do
    before :all do
      @helper = SimpRpmHelper.new
    end

    it 'should return log hash upon success' do
      result = @helper.execute('ls')
      expect(result[:stdout]).to_not be_empty
      expect(result[:stderr]).to be_empty
    end

    it 'should fail when command fails' do
      expect { @helper.execute('ls /does/not/exist')}.to raise_error(
      SimpRpmHelper::CommandError, /ls: cannot access/)
    end

    it 'should fail with specified message title when command fails' do
      expect { @helper.execute('ls /does/not/exist', 'Failed to find required dir')}.
        to raise_error(SimpRpmHelper::CommandError, /Failed to find required dir/)
    end
  end
end
