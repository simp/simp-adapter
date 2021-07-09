Summary: SIMP Adapter
Name: simp-adapter
Version: 2.1.0
Release: 1%{?dist}
License: Apache-2.0
Group: Applications/System
Source: %{name}-%{version}-%{release}.tar.gz
Buildroot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Buildarch: noarch

Prefix: %{_sysconfdir}/simp

# simp_rpm_helper uses git and rsync.
%if 0%{?rhel} > 7
# On el > 7, dnf will, by default, also remove the packages for these
# executables when the simp-adapter is uninstalled, if they are not required
# by any other packages.  So, use weak dependencies known to the package
# manager. See rpm.org/user_doc/dependencies.html.
Recommends: git
Recommends: rsync
%else
Requires: git
Requires: rsync
%endif

# %postun uses /opt/puppetlabs/puppet/bin/ruby
Requires(postun): puppet-agent

# simp_rpm_helper uses /opt/puppetlabs/puppet/bin/ruby, a more current
# and thus more capable Ruby than is provided by the OS
Requires: puppet-agent >= 6.22.1

Provides: simp-adapter = %{version}
Provides: simp-adapter-foss = %{version}
Provides: simp-adapter-pe = %{version}

Obsoletes: simp-adapter-pe < 1.0.0
Obsoletes: simp-adapter-foss < 1.0.0

%description
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

%pre
# Pre installation stuff
# when $1 = 1, this is an install
# when $1 = 2, this is an upgrade

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
# When upgrading from simp-adapter < 1.0.0, if the user has modified
# the old configuration file for the simp-adapter, rpm will save it
# off with a suffix '.rpmsave', because that file was marked as
# '%config(noreplace)'. The old config is not applicable to the
# current simp-adapter (wrong filename and content), so remove it.
if [ -f "/etc/simp/adapter_config.yaml.rpmsave" ]; then
  rm -f /etc/simp/adapter_config.yaml.rpmsave
fi

%changelog
* Fri Jul 09 2021 Liz Nemsick <lnemsick.simp@gmail.com> -  2.1.0
- Added support for EL8
  - Use 'Recommends' in lieu of 'Requires' on EL8 so that the git
    package is not uninstalled if the simp-adapter package
    is uninstalled.
  - simp_rpm_helper now checks for the 'git' or 'rsync' executables
    and fails if either cannot be found. This is necessary because
    'Recommends' does not ensure 'git' and 'rsync' are available.
- Updated minimum version of puppet-agent required to 6.22.1

* Tue Oct 27 2020 Liz Nemsick <lnemsick.simp@gmail.com> -  2.0.0
- Removed logic to ensure any existing, global hiera.yaml.simp file is not
  removed on upgrade from simp-adapter <= 0.0.6.
  - If users have followed SIMP upgrade procedures and have already upgraded to
    simp-adapter 1.0.x, this removed logic will not be an issue.
  - Otherwise, the user can manually save off /etc/puppetlabs/puppet/hiera.yaml.simp
    prior to upgrade, and then restore that file after the upgrade is complete.

* Tue May 21 2019 Liz Nemsick <lnemsick.simp@gmail.com> -  1.0.1
- Adjust simp_rpm_helper behavior to allows the simp-environment
  package to be upgraded to the simp-environment-skeleton package
  without simp_rpm_helper errors:
  - Accept a deprecated '--preserve' option in simp_rpm_helper.  This
    option no longer does anything.
  - Disable verification that '--target_dir' is a fully-qualified path.
- Remove OBE %post logic plus the RPM requires and distribution
  release qualifier related to it.
- Combine simp-adapter-foss and simp-adapter-pe into 1 package

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
