# SUSE's openQA tests
#
# Copyright 2020-2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: engine subclass for podman specific implementations
# Maintainer: qac team <qa-c@suse.de>

package containers::podman;
use Mojo::Base 'containers::engine';
use testapi;
use containers::utils qw(registry_url);
use containers::common qw(install_podman_when_needed);
use utils qw(file_content_replace);
use version_utils qw(get_os_release is_transactional);
use transactional qw(trup_call check_reboot_changes);
use utils qw(zypper_call);

has runtime => "podman";

sub init {
    my ($running_version, $sp, $host_distri) = get_os_release;
    install_podman_when_needed($host_distri);
    configure_insecure_registries();
}

sub configure_insecure_registries {
    my ($self) = shift;

    assert_script_run "curl " . data_url('containers/registries.conf') . " -o /etc/containers/registries.conf";
    assert_script_run "chmod 644 /etc/containers/registries.conf";
    # Add custom registry only if set by the REGISTRY variable
    assert_script_run('echo -e \'[[registry]]\nlocation = "' . registry_url() . '"\ninsecure = true\' >> /etc/containers/registries.conf') if get_var('REGISTRY');
}

sub get_storage_driver {
    my $json = shift->info(json => 1);
    my $storage = $json->{store}->{graphDriverName};
    record_info 'Storage', "Detected storage driver=$storage";

    return $storage;
}

sub switch_network_backend {
    my ($self, $net) = @_;
    # exit if already cni present
    record_info("backend", $net);
    return 1
      if (script_output("podman info --format {{.Host.NetworkBackend}}") =~ /^$net/);
    my @pkgs;
    if ($net =~ /^cni/) {
        @pkgs = qw(cni cni-plugins);
    } elsif ($net =~ /^netavark/) {
        @pkgs = qw(netavark aardvark-dns);
    } else {
        return 0;
    }
    my $config = "/etc/containers/containers.conf";
    # skip if already installed
    unless (script_run("rpm -q @pkgs") eq 0) {
        if (is_transactional) {
            trup_call("pkg install @pkgs");
            check_reboot_changes;
        } else {
            zypper_call("in @pkgs");
        }
    }
    # change network backend to '$net'
    my $ret = script_run("grep -i network_backend=" . " $config");
    if ($ret == 0) {
        # conf. modify
        assert_script_run(q(sed -i 's/network_backend=.*/network_backend=") . "$net" . q("/g') . " $config");
    } else {
        # 1 string not found:append; 2 file not found:create
        $ret = ($ret == 1) ? '>>' : '>';
        assert_script_run(q(echo -e '[Network]\nnetwork_backend=") . "$net" . q("') . " $ret" . " $config");
    }
    my $out = script_output("grep network_backend= $config", proceed_on_failure => 1);
    record_info('Switching', "podman network:" . $out);
    # reset the storage back to the initial state
    assert_script_run("podman system reset --force", timeout => 300, fail_message => "podman reset error");
    validate_script_output("podman info --format {{.Host.NetworkBackend}}", sub { /^$net/ });
    return 1;
}

1;
