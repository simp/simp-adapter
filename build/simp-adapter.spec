%define puppet_confdir /etc/puppetlabs/puppet

Summary: SIMP Adapter for the AIO Puppet Installation
Name: simp-adapter
Version: 0.1.0
Release: 0%{?dist}
License: Apache-2.0
Group: Applications/System
Source: %{name}-%{version}-%{release}.tar.gz
Buildroot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Buildarch: noarch

Prefix: %{_sysconfdir}/simp

Requires: rsync
Requires(post): puppet
Requires(post): puppetserver
Requires(post): puppetdb
%{?el6:Requires(post): procps}
%{?el7:Requires(post): procps-ng}
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
Requires: rsync
Requires(post): puppet-agent
Requires(post): pe-puppetserver
Requires(post): pe-puppetdb
%{?el6:Requires(post): procps}
%{?el7:Requires(post): procps-ng}
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
An adapter RPM for gluing together a SIMP version with the AIO Puppet
installation.

%description pe
An adapter RPM for gluing together a SIMP version with the Puppet Enterprise
Puppet installation.

%prep
%setup -q

%build

%install
mkdir -p %{buildroot}%{prefix}
install -p -m 750 -D src/sbin/simp_rpm_helper %{buildroot}/usr/local/sbin/simp_rpm_helper
install -p -m 640 -D src/conf/adapter_config.yaml %{buildroot}%{prefix}/adapter_config.yaml

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
%config(noreplace) %{prefix}/adapter_config.yaml
/usr/local/sbin/simp_rpm_helper

%files pe
%defattr(-,root,root,-)
%config(noreplace) %{prefix}/adapter_config.yaml
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

if [ $1 -eq 1 ]; then
  # This is an initial install.
  #
  # If the adapter is installed during a SIMP installation (e.g., from the ISO or
  # kickstarts), ensure that the /etc/simp/adapter_config.yaml is set up to copy over
  # the /usr
  #
  # This will only work if the kernel procinfo includes a `simp_install` argument
  simp_install=`awk -F "simp_install=" '{print $2}' /proc/cmdline | cut -f1 -d' '`
  if [ ! -z "${simp_install}" ]; then
    date=`date +%Y%m%d\ %H%M%S`
    [ -f %{prefix}/adapter_config.yaml ] || echo '---' > %{prefix}/adapter_config.yaml
    echo "# This file was modified by simp-adapter during a SIMP install" >> %{prefix}/adapter_config.yaml
    echo "# on ${date}:"            >> %{prefix}/adapter_config.yaml
    echo "target_directory: 'auto'" >> %{prefix}/adapter_config.yaml
    echo 'copy_rpm_data: true'     >> %{prefix}/adapter_config.yaml
  fi
fi

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

puppet config set trusted_node_data true || :
puppet config set digest_algorithm sha256 || :
puppet config set stringify_facts false || :

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
  fi
)

%posttrans
# This strange but necessary logic is require to handle the second part of a
# simp-adapter upgrade workaround initiated in %pre for a specific use case.
  See %pre comments for details.
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

%changelog
* Fri Oct 05 2018 Liz Nemsick <lnemsick.simp@gmail.com> -  0.1.0-0
- Removed delivery of global, Hiera 3 hiera.yaml file.
- Added logic to ensure any existing hiera.yaml.simp file is not removed
  on upgrade from simp-adapter <= 0.0.6.
- Added uninstall logic to remove an existing hiera.yaml.simp file that had
  been preserved from simp-adapter <= 0.0.6, but which is no longer in the
  simp-adapter RPM file list.

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
