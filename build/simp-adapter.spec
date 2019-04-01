%define puppet_confdir /etc/puppetlabs/puppet

Summary: SIMP Adapter for the AIO Puppet Installation
Name: simp-adapter
Version: 1.0.0
Release: 0%{?dist}
License: Apache-2.0
Group: Applications/System
Source: %{name}-%{version}-%{release}.tar.gz
Buildroot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Buildarch: noarch

Prefix: %{_sysconfdir}/simp

# simp_rpm_helper uses git and rsync
Requires: git
Requires: rsync

# %post uses /opt/puppetlabs/bin/puppet
# %postun uses /opt/puppetlabs/puppet/bin/ruby
Requires(post,postun): puppet-agent

Requires(post): puppetserver
Requires(post): puppetdb
%{?el6:Requires(post): procps}
%{?el7:Requires(post): procps-ng}

# simp_rpm_helper uses /opt/puppetlabs/puppet/bin/ruby, a more current
# and thus more capable Ruby than is provided by the OS (esp. on el6)
Requires: puppet-agent < 6.0.0
Requires: puppet-agent >= 5.5.6

Requires: puppet-client-tools < 2.0.0
Requires: puppet-client-tools >= 1.2.4
Requires: puppetdb < 6.0.0
Requires: puppetdb >= 5.2.4
Requires: puppetdb-termini < 6.0.0
Requires: puppetdb-termini >= 5.2.4
Requires: puppetserver < 6.0.0
Requires: puppetserver >= 5.3.5
Provides: simp-adapter = %{version}
Provides: simp-adapter-foss = %{version}

%package pe
Summary: SIMP Adapter for the Puppet Enterprise Puppet Installation
License: Apache-2.0

# simp_rpm_helper uses git and rsync
Requires: git
Requires: rsync

# %post uses /opt/puppetlabs/bin/puppet
# %postun uses /opt/puppetlabs/puppet/bin/ruby
Requires(post,postun): puppet-agent

Requires(post): pe-puppetserver
Requires(post): pe-puppetdb
%{?el6:Requires(post): procps}
%{?el7:Requires(post): procps-ng}

# simp_rpm_helper uses /opt/puppetlabs/puppet/bin/ruby, a more current
# and thus more capable Ruby than is provided by the OS (esp. on el6)
Requires: puppet-agent < 6.0.0
Requires: puppet-agent >= 5.5.6
Requires: pe-client-tools >= 18.0.0
Requires: pe-puppetdb < 6.0.0
Requires: pe-puppetdb >= 5.2.4
Requires: pe-puppetdb-termini < 6.0.0
Requires: pe-puppetdb-termini >= 5.2.4
Requires: pe-puppetserver >= 2018.1.0
Provides: simp-adapter = %{version}
Provides: simp-adapter-pe = %{version}

%description
An adapter RPM for creating/updating local Puppet module Git repositories
and gluing together a SIMP version with the AIO Puppet installation.

%description pe
An adapter RPM for creating/updating local Puppet module Git repositories
and gluing together a SIMP version with the Puppet Enterprise Puppet
installation.

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
#
# TODO: Many of the hard-coded users and groups are likely to break when using
#       PE, which has different service, user, and group names:
#
#  - https://docs.puppet.com/pe/2016.4/install_what_and_where.html#user-accounts-installed
#  - https://docs.puppet.com/pe/2016.4/install_what_and_where.html#group-accounts-installed
#
%defattr(-,root,root,-)
%config(noreplace) %{prefix}/adapter_conf.yaml
/usr/local/sbin/simp_rpm_helper

%files pe
%defattr(-,root,root,-)
%config(noreplace) %{prefix}/adapter_conf.yaml
/usr/local/sbin/simp_rpm_helper

%post
# Post installation stuff
# when $1 = 1, this is an install
# when $1 = 2, this is an upgrade

PATH=$PATH:/opt/puppetlabs/bin

id -u 'pe-puppet' &> /dev/null
if [ $? -eq 0 ]; then
  puppet_user='pe-puppet'
  puppet_group='pe-puppet'
  puppetdb_user='pe-puppetdb'
  puppetdb_group='pe-puppetdb'
else
  puppet_user='puppet'
  puppet_group='puppet'
  puppetdb_user='puppetdb'
  puppetdb_group='puppetdb'
fi

if [ "${puppet_user}" == 'puppet' ]; then
  # This fix is Puppet Open Source Only
  #
  # This is here due to a bug in the Puppet Server RPM that does not properly
  # nail up the Puppet UID and GID to 52
  #
  # Unfortunately, we can't guarantee order in 'post', so we may have to munge up
  # the filesystem pretty hard

  puppet_owned_dirs='/opt/puppetlabs /etc/puppetlabs /var/log/puppetlabs /var/run/puppetlabs'

  puppet_uid=`id -u puppet 2>/dev/null`
  puppet_gid=`id -g puppet 2>/dev/null`

  restart_puppetserver=0

  if [ -n $puppet_gid ]; then
    if [ "$puppet_gid" != '52' ]; then

      if `pgrep -f puppetserver &>/dev/null`; then
        puppet resource service puppetserver ensure=stopped || :
        wait
        restart_puppetserver=1
      fi

      groupmod -g 52 puppet || :

      for dir in $puppet_owned_dirs; do
        if [ -d $dir ]; then
          find $dir -gid $puppet_gid -exec chgrp puppet {} \;
        fi
      done
    fi
  else
    # Add puppet group
    groupadd -r -g 52 puppet || :
  fi

  if [ -n $puppet_uid ]; then
    if [ "$puppet_uid" != '52' ]; then

      if `pgrep -f puppetserver &>/dev/null`; then
        puppet resource service puppetserver ensure=stopped  || :
        wait
        restart_puppetserver=1
      fi

      usermod -u 52 puppet || :

      for dir in $puppet_owned_dirs; do
        if [ -d $dir ]; then
          find $dir -uid $puppet_uid -exec chown puppet {} \;
        fi
      done
    fi
  else
    # Add puppet user
    useradd -r --uid 52 --gid puppet --home /opt/puppetlabs/server/data/puppetserver --shell $(which nologin) --comment "puppetserver daemon" puppet || :
  fi

  if [ $restart_puppetserver -eq 1 ]; then
    puppet resource service puppetserver ensure=running
  fi

  # PuppetDB doesn't have a set user and group, but we really want to make sure
  # that the directory permissions aren't awful

  # Add puppet group
  getent group puppetdb > /dev/null || groupadd -r puppetdb || :

  # Add puppet user
  getent passwd puppetdb > /dev/null || useradd -r --gid puppetdb --home /opt/puppetlabs/server/data/puppetdb --shell $(which nologin) --comment "puppetdb daemon" puppetdb || :
fi
# End Puppet Open Source permissions munging

puppet config set digest_algorithm sha256 || :

(
  cd %{puppet_confdir}

  # Only do permission fixes on a fresh install
  if [ $1 -eq 1 ]; then
    # Fix the permissions laid down by the puppet-agent, puppetserver
    # and puppetdb RPMs
    # https://tickets.puppetlabs.com/browse/PA-726
    for dir in code puppet puppetserver pxp-agent; do
      if [ -d $dir ]; then
        chmod -R u+rwX,g+rX,g-w,o-rwx $dir
        chmod ug+st $dir
        chgrp -R $puppet_group $dir
      fi
    done

    if [ -d 'puppet/ssl' ]; then
      chmod -R u+rwX,g+rX,g-w,o-rwx 'puppet/ssl'
      chmod ug+st 'puppet/ssl'
      chown -R ${puppet_user}:${puppet_group} 'puppet/ssl'
    fi

    if [ -d 'puppetdb' ]; then
      chmod -R u+rwX,g+rX,g-w,o-rwx 'puppetdb'
      chmod ug+st 'puppetdb'
      chgrp -R $puppetdb_group 'puppetdb'
    fi
  fi
)

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

%changelog
* Tue Apr 02 2019 Liz Nemsick <lnemsick.simp@gmail.com> -  1.0.0-0
- Reworked simp_rpm_helper to install a module's content into a
  SIMP-managed, bare Git repository, instead of a 'simp' environment
  (/var/puppetlabs/code/environments/simp), during a module RPM
  install/upgrade.  See the comment block header in
  /usr/local/sbin/simp_rpm_helper for more detailed information about
  the new behavior and configuration.
- Removed simp-adapter's special RPM upgrade/erase logic for handling
  of the global, Hiera 3 file (/etc/puppetlabs/puppet/hiera.yaml.simp)
  that simp-adapter <= 0.0.6 delivered and linked to
  /etc/puppetlabs/puppet/hiera.yaml.

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
