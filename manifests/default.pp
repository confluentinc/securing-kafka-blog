# If you run this outside of vagrant. Run these commands first.
# You must also ensure that the machine is resolvable by it's fully qualified name.
#
# puppet module install puppetlabs-stdlib
# puppet module install puppetlabs-inifile
# puppet module install puppetlabs-motd
# puppet module install saz-ssh

$packages = [
  'confluent-kafka-2.11',
  'java-1.8.0-openjdk-headless',
  'krb5-workstation',
  'krb5-server',
  'krb5-libs',
  'haveged'
]

$ssl_port = 9093
$sasl_port = 9095

$kerberos_realm = upcase($::domain)
$kerberos_master_password = 'password123'

$zookeeper_principal = "zookeeper/${fqdn}@${kerberos_realm}"
$zookeeper_keytab = '/etc/security/keytabs/zookeeper.keytab'
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
$ou=""
$o="Confluent"
$l="London"
$st="London"
$c="GB"
$server_cn="${fqdn}"
$client_cn="${fqdn}"
$keytool_alias="${fqdn}"

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
  descr    => 'Confluent repository for 3.0.x packages',
  baseurl  => 'http://packages.confluent.io/rpm/3.0',
  gpgcheck => 1,
  gpgkey   => 'http://packages.confluent.io/rpm/3.0/archive.key',
} ->
package{$packages:
  ensure => 'installed'
} ->
service{'haveged':
  ensure => 'running',
  enable => true
} ->
file{'/etc/krb5.conf':
  ensure  => 'present',
  content => "[libdefaults]
    default_realm = ${kerberos_realm}
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    forwardable = true
    udp_preference_limit = 1000000
    # WARNING: We use weaker key types to simplify testing as stronger key types
    # require the enhanced security JCE policy file to be installed. You should
    # NOT run with this configuration in production or any real environment. You
    # have been warned.
    default_tkt_enctypes = des-cbc-md5 des-cbc-crc des3-cbc-sha1
    default_tgs_enctypes = des-cbc-md5 des-cbc-crc des3-cbc-sha1
    permitted_enctypes = des-cbc-md5 des-cbc-crc des3-cbc-sha1

[realms]
    ${kerberos_realm} = {
        kdc = ${::fqdn}:88
        admin_server = ${::fqdn}:749
        default_domain = ${::domain}
    }

[domain_realm]
    .${::domain} = ${kerberos_realm}
     ${::domain} = ${kerberos_realm}

[logging]
    kdc = FILE:/var/log/krb5kdc.log
    admin_server = FILE:/var/log/kadmin.log
    default = FILE:/var/log/krb5lib.log
"
} ->
file{'/var/kerberos/krb5kdc/kdc.conf':
  ensure  => 'present',
  content => "default_realm = ${kerberos_realm}

[kdcdefaults]
    v4_mode = nopreauth
    kdc_ports = 0

[realms]
    ${kerberos_realm} = {
        kdc_ports = 88
        admin_keytab = /etc/kadm5.keytab
        database_name = /var/kerberos/krb5kdc/principal
        acl_file = /var/kerberos/krb5kdc/kadm5.acl
        key_stash_file = /var/kerberos/krb5kdc/stash
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
        # WARNING: We use weaker key types to simplify testing as stronger key types
        # require the enhanced security JCE policy file to be installed. You should
        # NOT run with this configuration in production or any real environment. You
        # have been warned.
        master_key_type = des3-hmac-sha1
        supported_enctypes = arcfour-hmac:normal des3-hmac-sha1:normal des-cbc-crc:normal des:normal des:v4 des:norealm des:onlyrealm des:afs3
        default_principal_flags = +preauth
    }
"
} ->
file{'/var/kerberos/krb5kdc/kadm5.acl':
  ensure  => 'present',
  content => "*/admin@${kerberos_realm}      *
"
} ->
exec{'kdb5_util create':
  command => "printf '${kerberos_master_password}\n${kerberos_master_password}\n'|   kdb5_util create -r ${kerberos_realm} -s",
  creates => '/var/kerberos/krb5kdc/principal',
  path    => [
    '/usr/sbin',
    '/usr/bin'
  ]
} ->
file{'/etc/security/keytabs':
  ensure => directory,
} ->
exec{'add kafka principal':
  command => "kadmin.local -q 'addprinc -randkey ${kafka_principal}'",
  unless  => "kadmin.local -q 'listprincs ${kafka_principal}' | grep '${kafka_principal}'",
} ->
exec{'create kafka keytab':
  command => "kadmin.local -q 'ktadd -k ${kafka_keytab} ${kafka_principal}'",
  creates => $kafka_keytab,
} ->
exec{'add zookeeper principal':
  command => "kadmin.local -q 'addprinc -randkey ${zookeeper_principal}'",
  unless  => "kadmin.local -q 'listprincs ${zookeeper_principal}' | grep '${zookeeper_principal}'",
} ->
exec{'create zookeeper keytab':
  command => "kadmin.local -q 'ktadd -k ${zookeeper_keytab} ${zookeeper_principal}'",
  creates => $zookeeper_keytab,
} ->
exec{'add kafkaclient principal':
  command => "kadmin.local -q 'addprinc -randkey ${kafkaclient_principal}'",
  unless  => "kadmin.local -q 'listprincs ${kafkaclient_principal}' | grep '${kafkaclient_principal}'",
} ->
exec{'create kafkaclient keytab':
  command => "kadmin.local -q 'ktadd -k ${kafkaclient_keytab} ${kafkaclient_principal}'",
  creates => $kafkaclient_keytab,
} ->
file{'/etc/security/tls':
  ensure => directory,
} ->
exec{'generate keystores and truststores':
  command => "keytool -genkey -noprompt -alias $keytool_alias -keypass ${password} -keystore ${server_keystore} -storepass ${password} -dname \"CN=$server_cn, OU=$ou, O=$o, L=$l, ST=$st, C=$c\" &&
openssl req -new -x509 -keyout ca-key -out ca-cert -days $validity -passout pass:$password -subj \"/CN=$server_cn/O=$o/L=$l/ST=$st/C=$c\" &&
keytool -keystore $server_truststore -alias CARoot -import -file ca-cert -noprompt -storepass $password &&
keytool -keystore $client_truststore -alias CARoot -import -file ca-cert -noprompt -storepass $password &&
keytool -keystore $server_keystore -alias $keytool_alias -certreq -file cert-file -noprompt -storepass $password &&
openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days $validity -CAcreateserial -passin pass:$password &&
keytool -keystore $server_keystore -alias CARoot -import -file ca-cert -noprompt -storepass $password &&
keytool -keystore $server_keystore -alias $keytool_alias -import -file cert-signed -noprompt -storepass $password &&
keytool -keystore $client_keystore -alias $keytool_alias -dname \"CN=$client_cn, OU=$ou, O=$o, L=$l, ST=$st, C=$c\" -validity $validity -genkey -noprompt -storepass $password -keypass $password &&
keytool -keystore $client_keystore -alias $keytool_alias -certreq -file cert-file -noprompt -storepass $password &&
openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days $validity -CAcreateserial -passin pass:$password &&
keytool -keystore $client_keystore -alias CARoot -import -file ca-cert -noprompt -storepass $password &&
keytool -keystore $client_keystore -alias $keytool_alias -import -file cert-signed -noprompt -storepass $password
",
  creates => $server_keystore
} ->
service{'krb5kdc':
  ensure => 'running',
  enable => true
} ->
file { '/etc/security/keytabs/kafkaclient.keytab':
  mode    => '0644',  #Never do this in production
} ->
file { '/etc/security/keytabs/kafka.keytab':
  mode    => '0644',  #Never do this in production
} ->
file { '/etc/security/keytabs/zookeeper.keytab':
  mode    => '0644',  #Never do this in production
} ->
file{'/etc/kafka/kafka_server_jaas.conf':
  ensure  => present,
  content => "KafkaServer {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab=\"${kafka_keytab}\"
    principal=\"${kafka_principal}\";
};

Client {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab=\"${kafka_keytab}\"
    principal=\"${kafka_principal}\";
};
"
} ->
file{ '/etc/kafka/kafka_client_jaas.conf':
  ensure  => present,
  content => "KafkaClient {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab=\"${kafkaclient_keytab}\"
    principal=\"${kafkaclient_principal}\";
};
"
} ->
file{'/etc/kafka/zookeeper_jaas.conf':
  ensure  => present,
  content => "Server {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  keyTab=\"${zookeeper_keytab}\"
  storeKey=true
  useTicketCache=false
  principal=\"${zookeeper_principal}\";
};
"
} ->
file{$log_dir:
  ensure => directory
} ->
file{'/etc/kafka/zookeeper.properties':
  ensure => present,
  content => "#Managed by puppet. Save changes to a different file.
dataDir=/var/lib/zookeeper
clientPort=2181
authProvider.1=org.apache.zookeeper.server.auth.SASLAuthenticationProvider
requireClientAuthScheme=sasl
jaasLoginRenew=3600000
"
} ->
file{'/usr/sbin/start-zk-and-kafka':
  ensure  => present,
  mode    => '0755',
  content => "export KAFKA_HEAP_OPTS='-Xmx256M'
export KAFKA_OPTS='-Djava.security.auth.login.config=/etc/kafka/zookeeper_jaas.conf'
/usr/bin/zookeeper-server-start /etc/kafka/zookeeper.properties &
sleep 5
export KAFKA_OPTS='-Djava.security.auth.login.config=/etc/kafka/kafka_server_jaas.conf'
/usr/bin/kafka-server-start /etc/kafka/server.properties &
"
} ->
file{'/etc/kafka/server.properties':
  ensure  => present,
  content => "#Managed by puppet. Save changes to a different file.
broker.id=0
listeners=SSL://:${ssl_port},SASL_SSL://:${sasl_port}
security.inter.broker.protocol=SSL
zookeeper.connect=${::fqdn}:2181
log.dirs=$log_dir
zookeeper.set.acl=true
ssl.client.auth=required
ssl.keystore.location=$server_keystore
ssl.keystore.password=$password
ssl.key.password=$password
ssl.truststore.location=$server_truststore
ssl.truststore.password=$password
sasl.kerberos.service.name=kafka
authorizer.class.name=kafka.security.auth.SimpleAclAuthorizer
super.users=User:CN=$server_cn,OU=$ou,O=$o,L=$l,ST=$st,C=$c
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

file{'/etc/kafka/consumer_sasl.properties':
  ensure  => present,
  content => "#Managed by puppet. Save changes to a different file.
bootstrap.servers=${::fqdn}:${sasl_port}
group.id=securing-kafka-group
security.protocol=SASL_SSL
sasl.kerberos.service.name=kafka
ssl.truststore.location=$client_truststore
ssl.truststore.password=$password
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

file{'/etc/kafka/producer_sasl.properties':
  ensure  => present,
  content => "#Managed by puppet. Save changes to a different file.
bootstrap.servers=${::fqdn}:${sasl_port}
security.protocol=SASL_SSL
sasl.kerberos.service.name=kafka
ssl.truststore.location=$client_truststore
ssl.truststore.password=$password
ssl.keystore.location=$client_keystore
ssl.keystore.password=$password
ssl.key.password=$password
"
} ->
class{'::motd':
  content => "Kerberos has been configured on this hosts.
The KDC is configuring for testing and demo purposes only. Specifically, the master key is not
sufficient for a production deployment of a KDC.

The keytabs are located in /etc/security/keytabs. They are currently marked as world readable (0644).
Do not do this in production.

The TLS keys and certificates are in /etc/security/tls.

Kafka config files are under /etc/kafka.

RUN
sudo /usr/sbin/start-zk-and-kafka
to start zookeeper and kafka with security enabled.
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
