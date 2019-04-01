[![License](http://img.shields.io/:license-apache-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0.html)
[![Build Status](https://travis-ci.org/simp/simp-adapter.svg)](https://travis-ci.org/simp/simp-adapter)

# simp-adapter

#### Table of Contents

1. [Description](#description)
2. [Important Changes](#important-changes)
3. [simp_rpm_helper](#simp_rpm_helper)

   * [Overview](#overview)
   * [Operation](#operation)
   * [Configuration](#configuration)
   * [Other details](#other-details)

4. [Installation support for different Puppet distributions](#installation-support-for-different-puppet-distributions)


## Description

The `simp-adapter` package provides two capabilities:

* The `simp_rpm_helper` script which creates/updates local Git repositories
  with the Puppet module content of SIMP-provided, Puppet module RPMs.
  These local Git repositories can be used by R10K or Code Manager to populate
  Puppet module environments.

* Miscellaneous installation support  for different Puppet distributions (FOSS,
  PE), i.e., workarounds for Puppetlabs RPM deficiencies.

## Important changes

Previous version of the `simp-adapter` (versions < 1.0.0) could be configured
to use the `simp_rpm_helper` to auto-update a Puppet module in the `simp`
environment, `/etc/puppetlabs/code/environments/simp`.  This behavior proved
to only be useful to a subset of SIMP users, i.e., those who were not using
multiple Puppet environments.  The SIMP users that routinely used multiple
Puppet environments, for example, to support pre-production testing workflows,
had to devise their on mechanism to handle SIMP Puppet module upgrades.

Beginning with `simp-adapter` 1.0.0, the auto-update behavior has been replaced
with creation/maintenance of a local Git repository for each Puppet module that
SIMP packages as an RPM. This change allows SIMP users to manage one or more
Puppet environments easily using R10K (with or without the use of of a control
repository) or Code Manager.  The use of R10K/Code Manager, in turn, provides
Puppet module installation that aligns with current, industry-wide, best practices.

## simp_rpm_helper

### Overview

`simp_rpm_helper` ensures that the Puppet module content of each
SIMP-provided, Puppet module RPM is imported from its RPM installation
location, `/usr/share/simp/modules/<module name>`, into a local,
SIMP-managed, Git repository.  This local Git repository can, in turn,
be referenced in Puppetfiles that R10K or Code Manager can use to
populate Puppet module environments.

### Operation

`simp_rpm_helper` is automatically called by different RPM scriptlets
(sections) of a SIMP-provided, Puppet module RPM.

* When called during the `%posttrans` scriptlet of the an RPM install,
  upgrade, or downgrade, it does the following:

  - Creates `/usr/share/simp/git/`, if it does not exist
  - Creates `/usr/share/simp/git/puppet_modules/`, if it does not exist
  - Creates a central (bare) Git repository for the module, if it
    does not exist

    - The repository is named using the top-level 'name' field from
      the module's `metadata.json` file:

      `/usr/share/simp/git/puppet_modules/<owner>-<name>.git`

  - Updates the master branch of the repository to be the contents
    of the RPM, excluding any empty directories
  - Adds a Git tag to the repository that matches the version number
    in the module's `metadata.json` file, as necessary

    - Overwrites the tag if it already exists but doesn't match the
      contents of the RPM

* When called during any other RPM scriptlet, it does nothing to the
  module's repository.  However, it does log important information
  in two cases:

  - If called during the `%post` section in an install or upgrade,
    (i.e., is called from an old, buggy, SIMP-provided Puppet module
    RPM), it logs a message telling the user how to fix the problem
    by calling `simp_rpm_helper` with the correct arguments.
  - If called during a `%preun` when the RPM status is 0, i.e., a RPM
    uninstall (erase), it logs a message telling the user that the
    module's local, RPM-based git repo has been preserved. (We can't
    remove the repository, as we don't know if it is in use.)

### Configuration

Please see the delivered `/etc/simp/adapter_conf.yaml` file for the
latest list of configuration operations.

**NOTE:**  If you have modified `/etc/simp/adapter_conf.yaml` for your
site's needs, the latest configuration file will be installed by
`rpm` at `/etc/simp/adapter_conf.yaml.rpmnew`, instead.  Your custom
modifications will not be overwritten upon `simp-adapter` RPM upgrade.

### Other Details

Below are a few other details about `simp_rpm_helper` that are worth noting:

* `simp_rpm_helper` no longer supports installation of files from the
  `simp-environment` RPM.  The mechanism to install `simp-environment` files
  into a Puppet environment or into `/var/simp/environments/<environment>`,
  (sometimes referred to as SIMP's secondary environment), has been migrated
  to a new command provided by SIMP's command line interface
  (`rubygem-simp-cli` package). Execute `simp help` for more information.
* `simp_rpm_helper` will not create a Git repository for `pupmod-simp-site`
  package, as this package is no longer used beginning with SIMP 6.4.0.
* The `master` branch of a local Puppet module Git repository will contain
  a local transaction history for the RPM of that module, ***not*** a
  copy of the Git history in the public repository for that project.
  Regardless, you should always use a tagged version from a local module
  repository.
* If for any reason you need to debug `simp_rpm_helper` operation, this script
  executes git operations in temporary directories, that, by default, are
  located in `/var/lib/simp-adapter`.  These temporary directories are normally
  purged after successful `simp_rpm_helper` operation.  Upon git-related
  failures, however, they are preserved to aid debug.

## Installation support for different Puppet distributions

FILL-ME-IN  This section will be fleshed out (or removed) pending
the result of [SIMP-6348](https://simp-project.atlassian.net/browse/SIMP-6348)
