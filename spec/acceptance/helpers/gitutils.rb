module Acceptance
  module Helpers
    module GitUtils

      # Compare the master branch or tag of a Git repo with a reference
      # directory
      #
      # +host+:     Host object on which the reference directory resides
      # +ref_dir+:  The reference directory for the comparison
      # +repo_url+: The URL to the git repo
      # +branch+:   Either 'master' or a tag name.
      # +excludes+: Array of patterns to exclude in the directory diff
      #
      def compare_to_repo_branch(host, ref_dir, repo_url, branch, excludes=[])
        clone_dir = "/root/#{File.basename(repo_url).gsub(/.git$/,'')}"
        on(host, "rm -rf #{clone_dir}")
        on(host, "git clone #{repo_url}")

        if branch != 'master'
          # dealing with a tag
          result = on(host, "cd #{clone_dir}; git tag -l")
          expect(result.stdout).to match(/^#{Regexp.escape(branch)}$/)
          on(host, "cd #{clone_dir}; git checkout tags/#{branch}")
        end

        excludes_str = excludes.map { |ex| "-x '#{ex}'"}.join(' ')
        on(host, "diff -aqr -x '.git' #{excludes_str} #{ref_dir} #{clone_dir}")
      end
    end

  end
end
