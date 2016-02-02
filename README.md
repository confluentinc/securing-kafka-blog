Vagrant setup based on Centos 7.2 that includes a Kerberos server, Confluent Kafka and OpenJDK 1.8.0 to make it easier to test all the pieces together. Please install [Vagrant](https://www.vagrantup.com/docs/installation/) and [VirtualBox](https://www.virtualbox.org/wiki/Downloads) (if you haven’t already) and then:

* Clone the git repository: `git clone https://github.com/confluentinc/securing-kafka-blog`
* Start and provision the vagrant environment: `vagrant up`
* Connect to the VM via SSH: `vagrant ssh`
