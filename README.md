# Secure Kafka Cluster (VM for testing and development)

# Overview

Based on the instructions in the Confluent blog post
[Apache Kafka Security 101](http://www.confluent.io/blog/apache-kafka-security-authorization-authentication-encryption),
this project provides a pre-configured virtual machine to run a secure Kafka cluster using the Confluent Platform.

**This VM is intended for development and testing purposes, and is not meant for production use.**


# What's included in the VM

* Virtual machine based on CentOS 7.2, managed by [Vagrant](https://www.vagrantup.com)
* [Confluent Platform 3.0.0](http://www.confluent.io/product)
  (see [CP 3.0.0 documentation](http://docs.confluent.io/3.0.0/))
    * Including Apache Kafka v0.10.0.0
    * Including Apache ZooKeeper v3.4.x
* Kerberos 5 server v1.x
* OpenJDK 1.8 (JDK and JRE)


# Usage

## Starting the VM and the secure Kafka cluster

First, you must install two prerequisites on your local machine (e.g. your laptop):

* [Vagrant](https://www.vagrantup.com/docs/installation/)
* [VirtualBox](https://www.virtualbox.org/wiki/Downloads)

Then you can launch the VM from your local machine:

```shell
# Clone this git repository
$ git clone https://github.com/confluentinc/securing-kafka-blog
$ cd securing-kafka-blog

# Start and provision the VM (this may take a few minutes).
# This step will boot the VM as well as install and configure
# Kafka, ZooKeeper, Kerberos, etc.
$ vagrant up

# Connect from your local machine to the VM via SSH
$ vagrant ssh

# You will see the following prompt if you're sucessfully connected to the VM
[vagrant@kafka ~]$
```

Once you're connected to VM, the last step is to start ZooKeeper and Kafka with security enabled:

```shell
# Start secure ZooKeeper and secure Kafka
[vagrant@kafka ~]$ sudo /usr/sbin/start-zk-and-kafka
```

The services that will now be running inside the VM include:

* `*:9093` -- secure Kafka broker (SSL)
* `*:9095` -- secure Kafka broker (SASL_SSL)
* `*:2181` -- secure Zookeeper instance

> **Your local machine (the host of the VM) cannot access these ports:**
> Because the VM has no port forwarding configured (cf. [Vagrantfile](Vagrantfile)),
> you can only access Kafka or ZooKeeper from inside the VM.
> You cannot, however, directly access Kafka or ZooKeeper from your local machine.


## Test-driving the secure Kafka cluster

You can use the example commands in
[Apache Kafka Security 101](http://www.confluent.io/blog/apache-kafka-security-authorization-authentication-encryption)
to test-drive this environment.

Simple example:

```shell
#
# The following commands assume that you're connected to the VM!
#

# Create the Kafka topic `securing-kafka`
[vagrant@kafka ~]$ export KAFKA_OPTS="-Djava.security.auth.login.config=/etc/kafka/kafka_server_jaas.conf"
[vagrant@kafka ~]$ kafka-topics --create --topic securing-kafka \
                                --replication-factor 1 \
                                --partitions 3 \
                                --zookeeper localhost:2181

# Launch the console consumer to continuously read from the topic `securing-kafka`
# You may stop the consumer at any time by entering `Ctrl-C`.
[vagrant@kafka ~]$ kafka-console-consumer --bootstrap-server localhost:9093 \
                                          --topic securing-kafka \
                                          --new-consumer \
                                          --consumer.config /etc/kafka/consumer_ssl.properties \
                                          --from-beginning

# In another terminal:
# Launch the console producer to write some data to the topic `securing-kafka`.
# You can then enter input data by writing some line of text, followed by ENTER.
# Every line you enter will become the message value of a single Kafka message.
# You may stop the producer at any time by entering `Ctrl-C`.
[vagrant@kafka ~]$ kafka-console-producer --broker-list localhost:9093 \
                                          --topic securing-kafka \
                                          --producer.config /etc/kafka/producer_ssl.properties

# Now when you manually enter some data via the console producer,
# then your console consumer in the other terminal will show you
# the same data again.
```


## Stopping the VM

Once you're done experimenting, you can stop the VM and thus the ZooKeeper and Kafka instances via:

```shell
# Run this command on your local machine (i.e. the host of the VM)
$ vagrant destroy
```


# Troubleshooting

## Configuration files

Main configuration files for both Kafka and ZooKeeper are stored under `/etc/kafka`.

Notably:

* `/etc/kafka/server.properties` -- Kafka broker configuration file
* `/etc/kafka/zookeeper.properties` -- ZooKeeper configuration file

Security related configuration files are also found under:

* `/etc/security/keytabs`
* `/etc/security/tls`
* `/etc/krb5.conf`


## Log files

Inside the VM you can find log files in the following directories:

* Kafka: `/var/log/kafka` -- notably the `server.log`
