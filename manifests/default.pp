# If you run this outside of vagrant. Run these commands first.
# You must also ensure that the machine is resolvable by it's fully qualified name.
#
# puppet module install puppetlabs-stdlib
# puppet module install puppetlabs-inifile
# puppet module install puppetlabs-motd
# puppet module install saz-ssh

$packages = [
  'confluent-kafka-2.11.7',
  'java-1.8.0-openjdk-headless',
  'haveged'
]

$ssl_port = 9093

$kafka_principal = "kafka/${fqdn}@${kerberos_realm}"
$kafka_keytab = '/etc/security/keytabs/kafka.keytab'
$kafkaclient_principal = "kafkaclient/${fqdn}@${kerberos_realm}"
$kafkaclient_keytab = '/etc/security/keytabs/kafkaclient.keytab'

$password="test1234"
$validity="365"
$server_keystore="/etc/security/tls/kafka.server.keystore.jks"
$server_truststore="/etc/security/tls/kafka.server.truststore.jks"
$client_keystore="/etc/security/tls/kafka.client.keystore.jks"
$client_truststore="/etc/security/tls/kafka.client.truststore.jks"
$o="Confluent"
$l="London"
$st="London"
$c="GB"
$server_cn="${fqdn}"
$server_ou="Broker"
$client_cn="${fqdn}"
$client_ou="Client"
$keytool_alias="${fqdn}"
$ca_cn="ca.example.com"
$ca_ou=""

$log_dir='/var/lib/kafka'

define property_setting(
  $ensure,
  $value,
  $path
) {
  ini_setting{$name:
    ensure  => $ensure,
    path    => $path,
    setting => $name,
    value   => $value
  }
}


package{'epel-release':
  ensure => 'installed'
} ->
service{'firewall':
  ensure => 'stopped',
  enable => false
}
yumrepo{'confluent':
  ensure   => 'present',
  descr    => 'Confluent repository for 2.0.x packages',
  baseurl  => 'http://packages.confluent.io/rpm/2.0',
  gpgcheck => 1,
  gpgkey   => 'http://packages.confluent.io/rpm/2.0/archive.key',
} ->
package{$packages:
  ensure => 'installed'
} ->
service{'haveged':
  ensure => 'running',
  enable => true
} ->
file{'/etc/security/tls':
  ensure => directory,
} ->
exec{'generate keystores and truststores':
  command => "keytool -genkey -noprompt -alias $keytool_alias -keypass ${password} -keystore ${server_keystore} -storepass ${password} -dname \"CN=$server_cn, OU=$server_ou, O=$o, L=$l, ST=$st, C=$c\" &&
openssl req -new -x509 -keyout ca-key -out ca-cert -days $validity -passout pass:$password -subj \"/CN=$ca_cn/O=$ca_o/L=$l/ST=$st/C=$c\" &&
keytool -keystore $server_truststore -alias CARoot -import -file ca-cert -noprompt -storepass $password &&
keytool -keystore $client_truststore -alias CARoot -import -file ca-cert -noprompt -storepass $password &&
keytool -keystore $server_keystore -alias $keytool_alias -certreq -file server-cert-file -noprompt -storepass $password &&
openssl x509 -req -CA ca-cert -CAkey ca-key -in server-cert-file -out server-cert-signed -days $validity -CAcreateserial -passin pass:$password &&
keytool -keystore $server_keystore -alias CARoot -import -file ca-cert -noprompt -storepass $password &&
keytool -keystore $server_keystore -alias $keytool_alias -import -file server-cert-signed -noprompt -storepass $password &&
keytool -keystore $client_keystore -alias $keytool_alias -dname \"CN=$client_cn, OU=$client_ou, O=$o, L=$l, ST=$st, C=$c\" -validity $validity -genkey -noprompt -storepass $password -keypass $password &&
keytool -keystore $client_keystore -alias $keytool_alias -certreq -file client-cert-file -noprompt -storepass $password &&
openssl x509 -req -CA ca-cert -CAkey ca-key -in client-cert-file -out client-cert-signed -days $validity -CAcreateserial -passin pass:$password &&
keytool -keystore $client_keystore -alias CARoot -import -file ca-cert -noprompt -storepass $password &&
keytool -keystore $client_keystore -alias $keytool_alias -import -file client-cert-signed -noprompt -storepass $password
",
  creates => $server_keystore
} ->
file{$log_dir:
  ensure => directory
} ->
file{'/etc/kafka/zookeeper.properties':
  ensure => present,
  content => "#Managed by puppet. Save changes to a different file.
dataDir=/var/lib/zookeeper
clientPort=2181
"
} ->
file{'/usr/sbin/start-zk-and-kafka':
  ensure  => present,
  mode    => '0755',
  content => "export KAFKA_HEAP_OPTS='-Xmx256M'
/usr/bin/zookeeper-server-start /etc/kafka/zookeeper.properties &
sleep 5
/usr/bin/kafka-server-start /etc/kafka/server.properties &
"
} ->
file{'/etc/kafka/server.properties':
  ensure  => present,
  content => "#Managed by puppet. Save changes to a different file.
broker.id=0
listeners=SSL://:${ssl_port}
security.inter.broker.protocol=SSL
zookeeper.connect=${::fqdn}:2181
log.dirs=$log_dir
ssl.client.auth=required
ssl.keystore.location=$server_keystore
ssl.keystore.password=$password
ssl.key.password=$password
ssl.truststore.location=$server_truststore
ssl.truststore.password=$password
authorizer.class.name=kafka.security.auth.SimpleAclAuthorizer
super.users=User:CN=$server_cn,OU=$server_ou,O=$o,L=$l,ST=$st,C=$c
"
} ->

file{'/etc/kafka/consumer_ssl.properties':
  ensure  => present,
  content => "#Managed by puppet. Save changes to a different file.
bootstrap.servers=${::fqdn}:${ssl_port}
group.id=securing-kafka-group
security.protocol=SSL
ssl.truststore.location=$client_truststore
ssl.truststore.password=$password
ssl.keystore.location=$client_keystore
ssl.keystore.password=$password
ssl.key.password=$password
"
} ->

file{'/etc/kafka/producer_ssl.properties':
  ensure  => present,
  content => "#Managed by puppet. Save changes to a different file.
bootstrap.servers=${::fqdn}:${ssl_port}
security.protocol=SSL
ssl.truststore.location=$client_truststore
ssl.truststore.password=$password
ssl.keystore.location=$client_keystore
ssl.keystore.password=$password
ssl.key.password=$password
"
} ->

class{'::motd':
  content => "TLS keys and certificates are in /etc/security/tls.

Kafka config files are under /etc/kafka.

RUN
sudo /usr/sbin/start-zk-and-kafka
to start zookeeper and kafka with SSL/TLS and authorization enabled.
"
} ->
class{'ssh':
  storeconfigs_enabled => false,
  server_options => {
    'PrintMotd'            => 'yes',
    'PermitRootLogin'      => 'yes',
    'UseDNS'               => 'no',
    'UsePAM'               => 'yes',
    'X11Forwarding'        => 'yes',
    'GSSAPIAuthentication' => 'no'
  }
}

Exec {
  path    => [
    '/usr/sbin',
    '/usr/bin',
    '/bin'
  ]
}
