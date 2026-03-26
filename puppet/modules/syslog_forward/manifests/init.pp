# @summary Forwards all syslog to LibreNMS and disables local log storage entirely.
#
# Replaces x_rsyslog. Configures in order:
#
#   1. journald  — drop-in sets Storage=none (no persistent journal on disk or RAM)
#                  and ForwardToSyslog=yes so everything reaches rsyslog.
#   2. rsyslog   — 48-apt-dpkg-forward.conf tails apt/dpkg log files via imfile
#                  and injects them into the rsyslog stream.
#                  49-syslog-forward.conf forwards *.* to LibreNMS over TCP then
#                  stops, so nothing is written to /var/log/*.
#   3. cleanup   — removes the legacy 99-syslog-forward.conf from earlier versions.
#
# Logrotate is intentionally not managed: with & stop in rsyslog there are no
# local syslog-sourced files to rotate. apt/dpkg files are still written locally
# (no way to prevent that) but are also forwarded to LibreNMS.
#
# dmesg/kernel logs are already forwarded via rsyslog's imklog module (kern.*).
#
# @param host             LibreNMS hostname or IP. Required via Hiera.
# @param port             Syslog TCP port. Default: 514 (LibreNMS syslog-ng).
# @param forward_apt_logs Forward apt/dpkg log files to LibreNMS. Default: true.
class syslog_forward (
  String  $host,
  Integer $port             = 514,
  Boolean $forward_apt_logs = true,
) {

  echo { 'SYSLOG FORWARDING MODULE':
    message  => 'SYSLOG FORWARDING MODULE.',
    withpath => false,
  }

  # --- journald -----------------------------------------------------------

  file { '/etc/systemd/journald.conf.d':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/etc/systemd/journald.conf.d/00-forward-no-store.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/etc/systemd/journald.conf.d'],
    content => "[Journal]\nStorage=none\nForwardToSyslog=yes\n",
    notify  => Exec['syslog_forward-reload-journald'],
  }

  exec { 'syslog_forward-reload-journald':
    command     => '/bin/systemctl restart systemd-journald',
    refreshonly => true,
  }

  # --- rsyslog: apt/dpkg file tailing (imfile) ----------------------------

  # apt and dpkg write directly to files — imfile injects them into the
  # rsyslog stream so they flow through to LibreNMS like any other message.
  # 48- prefix ensures this loads before the 49- forward+stop rule.
  if $forward_apt_logs {
    file { '/etc/rsyslog.d/48-apt-dpkg-forward.conf':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => @("END"/L),
        # Managed by Puppet - syslog_forward module. Do not edit manually.
        module(load="imfile" Mode="inotify")

        input(type="imfile" File="/var/log/apt/history.log" Tag="apt:" Severity="info" Facility="local6")
        input(type="imfile" File="/var/log/dpkg.log"        Tag="dpkg:" Severity="info" Facility="local6")
        END
      notify  => Service['rsyslog'],
    }
  } else {
    file { '/etc/rsyslog.d/48-apt-dpkg-forward.conf':
      ensure => absent,
      notify => Service['rsyslog'],
    }
  }

  # --- rsyslog: forward + stop --------------------------------------------

  # Remove legacy file from earlier versions of this module.
  file { '/etc/rsyslog.d/99-syslog-forward.conf':
    ensure => absent,
    notify => Service['rsyslog'],
  }

  file { '/etc/rsyslog.d/49-syslog-forward.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('syslog_forward/syslog_forward.conf.epp', { 'host' => $host, 'port' => $port }),
    notify  => Service['rsyslog'],
  }

  service { 'rsyslog':
    ensure => running,
    enable => true,
  }

}
