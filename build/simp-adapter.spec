%define puppet_confdir /etc/puppetlabs/puppet

Summary: SIMP Adapter for the AIO Puppet Installation
Name: simp-adapter
Version: 1.0.1
Release: 0
License: Apache-2.0
Group: Applications/System
Source: %{name}-%{version}-%{release}.tar.gz
Buildroot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Buildarch: noarch

Prefix: %{_sysconfdir}/simp

# simp_rpm_helper uses git and rsync
Requires: git
Requires: rsync

# %postun uses /opt/puppetlabs/puppet/bin/ruby
Requires(postun): puppet-agent

# simp_rpm_helper uses /opt/puppetlabs/puppet/bin/ruby, a more current
# and thus more capable Ruby than is provided by the OS (esp. on el6)
Requires: puppet-agent >= 5.5.7

Provides: simp-adapter = %{version}
Provides: simp-adapter-foss = %{version}

%package pe
Summary: SIMP Adapter for the Puppet Enterprise Puppet Installation
License: Apache-2.0

# simp_rpm_helper uses git and rsync
Requires: git
Requires: rsync

# %postun uses /opt/puppetlabs/puppet/bin/ruby
Requires(postun): puppet-agent

# simp_rpm_helper uses /opt/puppetlabs/puppet/bin/ruby, a more current
# and thus more capable Ruby than is provided by the OS (esp. on el6)
Requires: puppet-agent >= 5.5.10
Provides: simp-adapter = %{version}
Provides: simp-adapter-pe = %{version}

%description
An adapter RPM for creating/updating local Puppet module Git repositories.

%description pe
An adapter RPM for creating/updating local Puppet module Git repositories.

%prep
%setup -q

%build

%install
mkdir -p %{buildroot}%{prefix}
install -p -m 750 -D src/sbin/simp_rpm_helper %{buildroot}/usr/local/sbin/simp_rpm_helper
install -p -m 640 -D src/conf/adapter_conf.yaml %{buildroot}%{prefix}/adapter_conf.yaml

%clean
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%config(noreplace) %{prefix}/adapter_conf.yaml
/usr/local/sbin/simp_rpm_helper

%files pe
%defattr(-,root,root,-)
%config(noreplace) %{prefix}/adapter_conf.yaml
/usr/local/sbin/simp_rpm_helper

%pre
if [ $1 -eq 2 ]; then
  # This is an upgrade.
  #
  # Older versions of simp-adapter provide a global Hiera 3 configuration file
  # that may be in use at the time this version is installed.  With the move to
  # environment-specific Hiera configuration (beginning with SIMP-6.3.0), that
  # file, '/etc/puppetlabs/puppet/hiera.yaml.simp' is no longer packaged in
  # simp-adapter and will be automatically *removed* by rpm on upgrade. Since we
  # do not want users to lose configuration, we will save off that file before
  # it is removed and then restore it in the %posttrans below.
  #
  # The backup of 'hiera.yaml.simp' seems simple enough, but is complicated
  # by the following issues:
  # (1) The older versions of simp-adapter actually created a soft link
  #     of 'hiera.yaml.simp' to the global 'hiera.yaml'.
  # (2) The 0.0.6 -> 0.x.y. upgrade of simp-adapter requires a puppet-agent
  #     upgrade as part of the transaction.
  # (3) The puppet-agent RPM also tries to manage the global 'hiera.yaml'.
  #     In a puppet-agent RPM upgrade, the puppet-agent saves off (literally
  #     renames) the global 'hiera.yaml' to 'hiera.yaml.pkg-old' in its %pre
  #     and then restores in its %posttrans.
  # (4) If the %posttrans of puppet-agent runs before that of the simp-adapter,
  #     the puppet-agent upgrade doesn't restore the pre-existing 'hiera.yaml'
  #     because it is a link and the link was broken by the removal of
  #     'hiera.yaml.simp'.
  #
  # We workaround all these issues here and in the %posttrans.
  #
  # NOTE: Although this logic is intended for the simp-adapter 0.0.6 to 0.x.y
  # upgrade, it will also run for any later simp-adapter upgrade for which a
  # puppet-agent upgrade is also required.  It *should* work in that case,
  # as well, despite not being necessary.
  cd %{puppet_confdir}

  # For the upgrade scenario of interest, we are in the middle of the
  # transaction and need to check for the interim hiera.yaml file from the
  # puppet-agent %pre.
  if [ -h "hiera.yaml.pkg-old" ] &&  [ "$(readlink hiera.yaml.pkg-old)" = "hiera.yaml.simp" ] && [ -f "hiera.yaml.simp" ]; then
    cp -a hiera.yaml.simp hiera.yaml.simp.rpm_upgrade_bak
  fi
fi

%post
# Post installation stuff
# when $1 = 1, this is an install
# when $1 = 2, this is an upgrade


%postun
# Post uninstall stuff
# when $1 = 1, this is the uninstall of the previous version during an upgrade
# when $1 = 0, this is the uninstall of the only version during an erase

(
  if [ $1 -eq 0 ]; then
    # Previous versions of simp-adapter (0.0.6 and earlier)
    #   1) Installed a hiera.yaml.simp file
    #   2) Moved any initial hiera.yaml file to hiera.yaml.simpbak
    #   3) Created a link called hiera.yaml to hiera.yaml.simp
    #
    # So, if this is uninstall of simp-adapter, we are going to clean up most
    # of the residual cruft from an earlier simp-adapter, if present. However,
    # we are intentionally going to leave 'hiera.yaml.simpbak' alone.  We
    # could move that file back to 'hiera.yaml', if no 'hiera.yaml' exists.
    # Alternatively, we could remove 'hiera.yaml.simpbak'.  Both of those
    # operations seems too aggressive.  Instead, we are going to leave what
    # may be an OBE file in place, rather than to arbitrarily change Puppet
    # global configuration.
    cd %{puppet_confdir}

    if [ -h "hiera.yaml" ] &&  [ "$(readlink hiera.yaml)" = "hiera.yaml.simp" ]; then
      rm hiera.yaml
    fi

    rm -f hiera.yaml.simp

    # Remove the working directory of simp-adapter, which is used by
    # simp_rpm_helper.  To be sure we have all artifacts, we will remove
    # both the default directory and the configured directory.
    if [ -f "/etc/simp/adapter_conf.yaml" ]; then
      simp_adapter_work_dir=`/opt/puppetlabs/puppet/bin/ruby -r yaml -e "x = YAML.load(File.read('/etc/simp/adapter_conf.yaml')); puts (x && x.key?('work_dir')) ? x['work_dir'] : ''" 2>/dev/null`
    else
      simp_adapter_work_dir=""
    fi
    rm -rf ${simp_adapter_work_dir} /var/lib/simp-adapter
  fi
)

%posttrans
# This strange but necessary logic is require to handle the second part of a
# simp-adapter upgrade workaround initiated in %pre for a specific use case.
# See %pre comments for details.
(
  cd %{puppet_confdir}

  if [ -f "hiera.yaml.simp.rpm_upgrade_bak" ]; then
    if [ -e "hiera.yaml.simp" ]; then
      # Backup was not necessary
      rm  hiera.yaml.simp.rpm_upgrade_bak
    else
      # Restore the saved off Hiera 3 'hiera.yaml.simp'
      mv  hiera.yaml.simp.rpm_upgrade_bak hiera.yaml.simp
    fi
  fi

  if [ -h "hiera.yaml.pkg-old" ] &&  [ "$(readlink hiera.yaml.pkg-old)" = "hiera.yaml.simp" ]  && [ -e "hiera.yaml.simp" ]; then
    # We get here when 'hiera.yaml.simp' is removed by a simp-adapter upgrade
    # (0.0.6 to 0.x.y upgrades only), a puppet-agent upgrade is part of the
    # transaction, and the %posttrans of puppet-agent runs before that of the
    # simp-adapter.
    #
    # In this case, the puppet-agent upgrade doesn't restore the pre-existing
    # 'hiera.yaml' because it is broken link to 'hiera.yaml.simp'. Specifically,
    # the puppet-agent %posttrans executes an '-e' test on 'hiera.yaml.pkg-old'
    # and, because that test returns false (can't dereference a broken link),
    # does *not* move 'hiera.yaml.pkg-old' to 'hiera.yaml'. We have to
    # finish the puppet-agent restore ourselves.
    mv hiera.yaml.pkg-old hiera.yaml
  fi
)

# When upgrading from simp-adapter < 1.0.0, if the user has modified
# the old configuration file for the simp-adapter, rpm will save it
# off with a suffix '.rpmsave', because that file was marked as
# '%config(noreplace)'. The old config is not applicable to the
# current simp-adapter (wrong filename and content), so remove it.
if [ -f "/etc/simp/adapter_config.yaml.rpmsave" ]; then
  rm -f /etc/simp/adapter_config.yaml.rpmsave
fi

%changelog
* Tue May 21 2019 Liz Nemsick <lnemsick.simp@gmail.com> -  1.0.1
- Adjust simp_rpm_helper behavior to allows the simp-environment
  package to be upgraded to the simp-environment-skeleton package
  without simp_rpm_helper errors:
  - Accept a deprecated '--preserve' option in simp_rpm_helper.  This
    option no longer does anything.
  - Disable verification that '--target_dir' is a fully-qualified path.
- Remove OBE %post logic plus the RPM requires and distribution
  release qualifier related to it.

* Tue Apr 02 2019 Liz Nemsick <lnemsick.simp@gmail.com> -  1.0.0
- Reworked simp_rpm_helper to install a module's content into a
  SIMP-managed, bare Git repository, instead of a 'simp' environment
  (/var/puppetlabs/code/environments/simp), during a module RPM
  install/upgrade.  See the comment block header in
  /usr/local/sbin/simp_rpm_helper for more detailed information about
  the new behavior and configuration.

* Fri Dec 07 2018 Liz Nemsick <lnemsick.simp@gmail.com> -  0.1.1-0
- Affect a copy with simp_rpm_helper when called in either the %posttrans
  or %post of a SIMP RPM.
- Fix bug in simp-adapter.spec in which a comment line was missing the '#'

* Fri Oct 05 2018 Liz Nemsick <lnemsick.simp@gmail.com> -  0.1.0-0
- Removed delivery of global, Hiera 3 hiera.yaml file.
- Added logic to ensure any existing hiera.yaml.simp file is not removed
  on upgrade from simp-adapter <= 0.0.6.
- Added uninstall logic to remove an existing hiera.yaml.simp file that had
  been preserved from simp-adapter <= 0.0.6, but which is no longer in the
  simp-adapter RPM file list.
- Removed enabling OBE puppet trusted_node_data setting in %post
- Removed disabling OBE puppet stringify_facts setting in %post

* Fri Sep 07 2018 Jeanne Greulich <jeanne.greulich@onyxpoint.com> - 0.1.0-0
- Updated to use puppet 5 for SIMP 6.3

* Fri May 11 2018 Trevor Vaughan <tvaughan@onyxpoint.com> - 0.0.6-0
- Updated the minimum version of the puppet-agent dependency to at least
  1.10.4 (packages puppet 4.10.4), due to 'puppet generate types' bugs
  in puppet-agent releases prior to that. These bugs cause the composite
  namevar fixes to not function properly.

* Fri Oct 20 2017 Trevor Vaughan <tvaughan@onyxpoint.com> - 0.0.5-0
- Fixed the Changelog dates

* Mon May 22 2017 Nick Miller <nick.miller@onyxpoint.com> - 0.0.4-0
- Removed packaged auth.conf in favor of managing it with Puppet

* Wed Mar 08 2017 Trevor Vaughan <tvaughan@onyxpont.com> - 0.0.3-0
- Handle PE and Puppet Open source in the post section
- Add dist to the release field to account for RPM generation on EL6 vs EL7
- Updates to work better with PE and with the new method for detecting
  kickstart installs as added by Chris Tessmer <ctessmer@onyxpoint.com>

* Mon Mar 06 2017 Liz Nemsick <lnemsick.simp@gmail.com> -  0.0.3-0
- Fix 'puppet resource service' bugs in %post
- Add /var/run/puppetlabs to the list of directories to traverse,
  when fixing puppet uid/gid.
- Fix simp_rpm_helper bugs that prevented SIMP module RPM uninstalls
  in certain scenarios

* Mon Sep 12 2016 Trevor Vaughan <tvaughan@onyxpoint.com> - 0.0.1-Alpha
- First cut at the simp-adapter
