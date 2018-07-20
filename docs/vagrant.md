A [Vagrantfile](Vagrantfile) is also included in this repository so that you dont have to run Docker on your local computer.
To use it run:

```
vagrant up
vagrant ssh
docker run -p 8080:4567 -v /vagrant/vmpooler.yaml.example:/var/lib/vmpooler/vmpooler.yaml -it --rm --name pooler vmpooler
```

To run vmpooler with the example dummy provider you can replace the above docker command with this:

```
docker run -e VMPOOLER_DEBUG=true -p 8080:4567 -v /vagrant/vmpooler.yaml.dummy-example:/var/lib/vmpooler/vmpooler.yaml -e VMPOOLER_LOG='/var/log/vmpooler/vmpooler.log' -it --rm --name pooler vmpooler
```

Either variation will allow you to access the dashboard from [localhost:8080](http://localhost:8080/).

### Running directly in Vagrant

You can also run vmpooler directly in the Vagrant box. To do so run this:

```
vagrant up
vagrant ssh
cd /vagrant

# Do this if using the dummy provider
export VMPOOLER_DEBUG=true
cp vmpooler.yaml.dummy-example vmpooler.yaml

# vmpooler needs a redis server.
sudo yum -y install redis
sudo systemctl start redis

# Optional: Choose your ruby version or use jruby
# ruby 2.4.x is used by default
rvm list
rvm use jruby-9.1.7.0

gem install bundler
bundle install
bundle exec ruby vmpooler
```

When run this way you can access vmpooler from your local computer via [localhost:4567](http://localhost:4567/).
