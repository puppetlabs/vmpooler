# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
Vagrant.configure("2") do |config|
  config.vm.box = "genebean/centos-7-rvm-multi"
  config.vm.network "forwarded_port", guest: 4567, host: 4567 # for when not running docker-compose
  config.vm.network "forwarded_port", guest: 8080, host: 8080 # VMPooler api in docker-compose
  config.vm.network "forwarded_port", guest: 8081, host: 8081 # VMPooler manager in docker-compose
  config.vm.network "forwarded_port", guest: 8082, host: 8082 # Jaeger in docker-compose
  config.vm.provision "shell", inline: <<-SCRIPT
    mkdir /var/log/vmpooler
    chown vagrant:vagrant /var/log/vmpooler
    yum -y install docker
    groupadd docker
    usermod -aG docker vagrant
    systemctl enable docker
    systemctl start docker
    curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    docker-compose --version
    cd /vagrant
    docker-compose -f docker/docker-compose.yml build
    docker images
  SCRIPT

  # config.vm.provider "virtualbox" do |v|
  #   v.memory = 2048
  #   v.cpus = 2
  # end
  
end
