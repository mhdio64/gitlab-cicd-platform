# -*- mode: ruby -*-
# vi: set ft=ruby :
# ==============================================================================
# Vagrantfile for Local GitLab CI/CD Platform Lab
# Compatible with both Libvirt (KVM) and VirtualBox providers
# Supported Distros: ubuntu-22.04, ubuntu-24.04, debian-12, debian-11, rocky-9, rocky-8
# Usage: DISTRO=debian-12 vagrant up
# ==============================================================================

BOX_MAP = {
  "ubuntu-22.04" => "bento/ubuntu-22.04",
  "ubuntu-24.04" => "bento/ubuntu-24.04",
  "debian-12"    => "bento/debian-12",
  "debian-11"    => "bento/debian-11",
  "rocky-9"      => "bento/rockylinux-9",
  "rocky-8"      => "bento/rockylinux-8"
}

distro_key = ENV["DISTRO"] || "rocky-9"
box_image = BOX_MAP[distro_key] || distro_key

Vagrant.configure("2") do |config|
  config.vm.box = box_image
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # ----------------------------------------------------------------------------
  # GitLab Server Node (gitlab-01)
  # ----------------------------------------------------------------------------
  config.vm.define "gitlab-01" do |gitlab|
    gitlab.vm.hostname = "gitlab-01"
    gitlab.vm.network "private_network", ip: "192.168.56.10"

    # Libvirt (KVM) configuration
    gitlab.vm.provider :libvirt do |v|
      v.memory = 4096
      v.cpus = 2
      v.nested = false
    end

    # VirtualBox configuration
    gitlab.vm.provider :virtualbox do |v|
      v.name = "gitlab-cicd-gitlab-01"
      v.memory = 4096
      v.cpus = 2
    end
  end

  # ----------------------------------------------------------------------------
  # GitLab Runner Node (runner-01)
  # ----------------------------------------------------------------------------
  config.vm.define "runner-01" do |runner|
    runner.vm.hostname = "runner-01"
    runner.vm.network "private_network", ip: "192.168.56.21"

    # Libvirt (KVM) configuration
    runner.vm.provider :libvirt do |v|
      v.memory = 2048
      v.cpus = 2
      v.nested = false
    end

    # VirtualBox configuration
    runner.vm.provider :virtualbox do |v|
      v.name = "gitlab-cicd-runner-01"
      v.memory = 2048
      v.cpus = 2
    end
  end
end
