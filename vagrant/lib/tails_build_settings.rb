# -*- mode: ruby -*-
# vi: set ft=ruby :

# Approximate amount of RAM needed to run the builder's base system
# and perform a build
def vm_memory_base(cpus)
  memory = 1.5 * 1024
  # mksquashfs will run one thread per CPU, and each of them uses more
  # RAM, especially when defaulcomp (xz) is used. We very crudely
  # adjust for that here, based on rough benchmarking (comparing peak
  # memory usage for mksquashfs -processors 10 vs 20) that gives an
  # estimation of a 40 MB increase per thread. We only adjust for more
  # than 12 cpus since that's the only situation where we have
  # observed RAM shortage. Refs: tails#20459, tails!1634.
  memory += (cpus - 12) * 40 if cpus > 12
  memory
end

# Approximate amount of extra space needed for builds
BUILD_SPACE_REQUIREMENT = 13 * 1024

# Virtual machine memory size for on-disk builds
def vm_memory_for_disk_builds(cpus)
  vm_memory_base(cpus)
end

# Virtual machine memory size for in-memory builds
def vm_memory_for_ram_builds(cpus)
  vm_memory_base(cpus) + BUILD_SPACE_REQUIREMENT
end

# The builder VM's platform
ARCHITECTURE = 'amd64'.freeze
DISTRIBUTION = 'bookworm'.freeze

# The name of the Vagrant box
def box_name
  git_root = `git rev-parse --show-toplevel`.chomp
  shortid, date = `git log -1 --date="format:%Y%m%d" \
                   --no-show-signature --pretty="%h %ad" -- \
                   #{git_root}/vagrant/`.chomp.split
  "tails-builder-#{ARCHITECTURE}-#{DISTRIBUTION}-#{date}-#{shortid}"
end
