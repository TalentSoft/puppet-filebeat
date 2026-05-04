# filebeat::repo
#
# Manage the repository for Filebeat (Linux only for now)
#
# @summary Manages the yum, apt, and zypp repositories for Filebeat
class filebeat::repo {
  $elastic_gpg_key = "https://artifacts.elastic.co/GPG-KEY-elasticsearch"
  $debian_repo_url = "https://artifacts.elastic.co/packages/${filebeat::major_version}.x/apt"
  $yum_repo_url    = "https://artifacts.elastic.co/packages/${filebeat::major_version}.x/yum"

  case $facts['os']['family'] {
    'Debian': {
      exec { 'add_elasticsearch_gpg_key':
        path    => ['/bin','/usr/bin'],
        creates => '/etc/apt/keyrings/elasticsearch.gpg',
        # lint:ignore:strict_indent
        command => @("COMMAND"/L),
          mkdir -p /etc/apt/keyrings \
          && curl -sLS ${elastic_gpg_key} | gpg --dearmor -o /etc/apt/keyrings/elasticsearch.gpg \
          && chmod go+r /etc/apt/keyrings/elasticsearch.gpg
          | - COMMAND
        # lint:endignore
      }

      file { '/etc/apt/sources.list.d/beats.list':
        ensure            => file,
        content           => epp('filebeat/etc/apt/sources.list.d/beats.list.epp',
          debian_repo_url => $debian_repo_url,
        ),
        owner             => root,
        group             => root,
        mode              => '0644',
        require           => Exec['add_elasticsearch_gpg_key'],
        notify            => Exec['refresh_apt_for_filebeat'],
      }

      file { '/etc/apt/preferences.d/filebeat.pref':
        ensure            => file,
        content           => epp('filebeat/etc/apt/preferences.d/filebeat.pref.epp',
          repo_priority => $filebeat::repo_priority,
          version       => $filebeat::package_ensure,
        ),
        owner             => root,
        group             => root,
        mode              => '0644',
        require           => Exec['add_elasticsearch_gpg_key'],
        notify            => Exec['refresh_apt_for_filebeat'],
      }

      exec { 'refresh_apt_for_filebeat':
        command     => '/usr/bin/apt update',
        refreshonly => true,
      }

    }
    'RedHat', 'Linux': {
      if !defined(Yumrepo['beats']) {
        yumrepo { 'beats':
          ensure   => $filebeat::alternate_ensure,
          descr    => 'elastic beats repo',
          baseurl  => $yum_repo_url,
          gpgcheck => 1,
          gpgkey   => 'https://artifacts.elastic.co/GPG-KEY-elasticsearch',
          priority => $filebeat::repo_priority,
          enabled  => 1,
          notify   => Exec['flush-yum-cache'],
        }
      }

      exec { 'flush-yum-cache':
        command     => 'yum clean all',
        refreshonly => true,
        path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
      }
    }
    'Suse': {
      exec { 'topbeat_suse_import_gpg':
        command => 'rpmkeys --import https://artifacts.elastic.co/GPG-KEY-elasticsearch',
        unless  => 'test $(rpm -qa gpg-pubkey | grep -i "D88E42B4" | wc -l) -eq 1 ',
        notify  => [Zypprepo['beats']],
      }
      if !defined(Zypprepo['beats']) {
        zypprepo { 'beats':
          ensure      => $filebeat::alternate_ensure,
          baseurl     => $yum_repo_url,
          enabled     => 1,
          autorefresh => 1,
          name        => 'beats',
          gpgcheck    => 1,
          gpgkey      => 'https://packages.elastic.co/GPG-KEY-elasticsearch',
          type        => 'yum',
        }
      }
    }
    default: {
      fail($filebeat::osfamily_fail_message)
    }
  }
}
