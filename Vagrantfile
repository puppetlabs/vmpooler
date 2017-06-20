# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
Vagrant.configure("2") do |config|
  config.vm.box = "genebean/centos-7-rvm-221"
  config.vm.network "forwarded_port", guest: 4567, host: 4567
  config.vm.network "forwarded_port", guest: 8080, host: 8080
  config.vm.provision "shell", inline: <<-SCRIPT
    mkdir /var/log/vmpooler
    chown vagrant:vagrant /var/log/vmpooler
    yum -y install docker
    groupadd docker
    usermod -aG docker vagrant
    systemctl enable docker
    systemctl start docker
    docker build -t vmpooler /vagrant
    docker images
    echo 'To use the container with the dummy provider do this after "vagrant ssh":'
    echo "docker run -e VMPOOLER_DEBUG=true -p 8080:4567 -v /vagrant/vmpooler.yaml.dummy-example:/var/lib/vmpooler/vmpooler.yaml -e VMPOOLER_LOG='/var/log/vmpooler/vmpooler.log' -it --rm --name pooler vmpooler"
  SCRIPT
end
