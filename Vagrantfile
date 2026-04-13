# -*- mode: ruby -*-
# vi: set ft=ruby :

# ── Load .env file ─────────────────────────────────────────────────
env_file = File.join(File.dirname(__FILE__), ".env")
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    key, value = line.split("=", 2)
    ENV[key.strip] = value.strip if key && value
  end
end

AGENT_NAME  = ENV.fetch("AGENT_NAME",  "arch-teamcity-agent")
SERVER_URL  = ENV.fetch("SERVER_URL",  "http://LOCAL_COMPANY_SERVER_IP_ADDRESS:8111")
# ───────────────────────────────────────────────────────────────────

Vagrant.configure("2") do |config|
  config.vm.box = "generic/arch"
  config.vm.hostname = "teamcity-agent"

  # Network — the agent needs to reach the TeamCity server
  config.vm.network "private_network", type: "dhcp"

  # ── VirtualBox provider ──────────────────────────────────────────
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "teamcity-agent-arch"
    vb.cpus   = 2
    vb.memory = 4096

    # Resize the primary disk to 150 GB
    # Requires: vagrant plugin install vagrant-disksize
    unless Vagrant.has_plugin?("vagrant-disksize")
      warn "NOTE: Install vagrant-disksize for 150 GB disk on VirtualBox:"
      warn "  vagrant plugin install vagrant-disksize"
    end
  end

  # vagrant-disksize (VirtualBox only)
  if Vagrant.has_plugin?("vagrant-disksize")
    config.disksize.size = "150GB"
  end

  # ── Libvirt provider ─────────────────────────────────────────────
  config.vm.provider "libvirt" do |lv|
    lv.cpus   = 2
    lv.memory = 4096

    # Primary storage volume — 150 GB
    lv.machine_virtual_size = 150

    # Auto-start VM when host boots
    lv.autostart = true
  end

  # Disable default synced folder (not always available on libvirt)
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # ── Provisioning ─────────────────────────────────────────────────
  # Step 1: Update system and kernel
  config.vm.provision "base", type: "shell",
    path: "provision-base.sh",
    reboot: true

  # Step 2: Copy Dockerfile into the VM
  config.vm.provision "copy-dockerfile", type: "file",
    source: "Dockerfile.agent",
    destination: "/tmp/Dockerfile.agent"

  # Step 3: Install Docker and run agent (after reboot with new kernel)
  config.vm.provision "docker-agent", type: "shell",
    path: "provision.sh",
    env: {
      "AGENT_NAME" => AGENT_NAME,
      "SERVER_URL" => SERVER_URL,
    }
end
