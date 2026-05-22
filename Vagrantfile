env_file = File.join(File.dirname(__FILE__), ".env")
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    key, value = line.split("=", 2)
    ENV[key.strip] = value.strip if key && value
  end
end

AGENT_NAME  = ENV.fetch("AGENT_NAME",  "ubuntu-teamcity-agent")
SERVER_URL  = ENV.fetch("SERVER_URL",  "http://LOCAL_COMPANY_SERVER_IP_ADDRESS:8111")

Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2204"
  config.vm.hostname = "teamcity-agent"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "teamcity-agent-ubuntu"
    vb.cpus   = 2
    vb.memory = 4096

    unless Vagrant.has_plugin?("vagrant-disksize")
      warn "NOTE: Install vagrant-disksize for 150 GB disk on VirtualBox:"
      warn "  vagrant plugin install vagrant-disksize"
    end
  end

  if Vagrant.has_plugin?("vagrant-disksize")
    config.disksize.size = "150GB"
  end

  config.vm.provider "libvirt" do |lv|
    lv.cpus   = 2
    lv.memory = 4096
    lv.machine_virtual_size = 150

    lv.autostart = true
  end

  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provision "copy-dockerfile", type: "file",
    source: "Dockerfile.agent",
    destination: "/tmp/Dockerfile.agent"

  config.vm.provision "docker-agent", type: "shell",
    path: "provision.sh",
    env: {
      "AGENT_NAME" => AGENT_NAME,
      "SERVER_URL" => SERVER_URL,
    }
end
