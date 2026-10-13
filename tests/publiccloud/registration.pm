# SUSE's openQA tests
#
# Copyright 2019-2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: cloud-regionsrv-client
# Summary: Register addons in the remote system
#   Registration is in registration_lifecycle test module
#
# Maintainer: QE-C team <qa-c@suse.de>

use Mojo::Base 'publiccloud::basetest';
use version_utils;
use registration;
use testapi;
use utils;
use publiccloud::utils;
use publiccloud::zypper qw(pc_pkg_call pc_wait_quit);
use publiccloud::ssh_interactive "select_host_console";
use File::Basename 'basename';

sub gce_metadata_server_ip6 {
    my ($instance, %args) = @_;
    $args{workaround} //= 0;
    return unless (is_gce() && get_var('PUBLIC_CLOUD_GCE_STACK_TYPE') =~ /IPV6$/);
    return if ($instance->ssh_script_run("ss -nap") // -1);
    my $ss = $instance->ssh_script_output(q(ss -nap | grep -F '[fd20:ce::254]:'), proceed_on_failure => 1);
    record_info('Address check', "Metadata server ip6 entries:\n$ss");
    # check metadata server unreachable on IPv6
    my $noreg = $instance->ssh_script_retry(cmd => qq(ss -nap | grep -F '[fd20:ce::254]:' | grep -F ' ESTAB '),
        timeout => 180, retry => 5, delay => 10, die => 0);
    if ($noreg // -1) {
        record_info('network issue', "Metadata server unresponsive on IPv6. Ref bsc#1277388", result => ($args{workaround} ? 'softfail' : 'fail'));
        if ($args{workaround} && $instance->ssh_script_run(q(echo "precedence ::ffff:0:0/96  100" | sudo tee -a /etc/gai.conf)) == 0) {
            record_info('Workaround', "IPv4 precedence applied as workaround");
            return 1;
        } else {
            die("Unresponsive metadata server in dual stack\n");
        }
    }
    return 0;
}

sub run {
    my ($self, $args) = @_;

    select_host_console();    # select console on the host, not the PC instance

    pc_wait_quit($args->{my_instance});
    check_dns($args->{my_instance}, die => !check_var('PUBLIC_CLOUD_SLES4SAP', '1'));
    gce_metadata_server_ip6($args->{my_instance}, workaround => 1);
    # Unified instance registration for BYOS and OnDemand. Run registercloudguest unconditionally when PUBLIC_CLOUD_FORCE_REGISTRATION is set.
    if (is_byos() || get_var('PUBLIC_CLOUD_FORCE_REGISTRATION')) {
        registercloudguest($args->{my_instance});
    } elsif (is_ondemand()) {
        $args->{my_instance}->wait_for_guestregister();
    }
    check_registration($args->{my_instance});
    # https://progress.opensuse.org/issues/196370 workaround for a known issue on 15-SP5
    if (is_sle('=15-SP5')) {
        pc_pkg_call($args->{my_instance}, "update -y", retry => 10, delay => 60, timeout => 1800);
        $args->{my_instance}->softreboot(timeout => 3600);
    }

    pc_wait_quit($args->{my_instance});
    register_addons_in_pc($args->{my_instance});
    pc_wait_quit($args->{my_instance});
    # Double confirm system is correctly registered, and quit earlier if anything wrong
    # see bsc#1253777, we may need have to rerun the failed job in this case
    record_info('Check registration status');
    # Workaround for sporadic issue 'System management is locked by the application with pid xxx (/usr/bin/zypper)'
    check_registration($args->{my_instance});
    # Since SLE 15 SP6 CHOST images don't have curl and we need it for testing
    if (is_sle('>15-SP5') && is_container_host()) {
        pc_pkg_call($args->{my_instance}, "in --force-resolution -y curl");
    }
}

sub test_flags {
    return {fatal => 1};
}

1;
