# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: podman network
# Summary: Test podman network
# Maintainer: QE-C team <qa-c@suse.de>

use Mojo::Base 'containers::basetest';
use testapi;
use utils qw(script_retry);
use serial_terminal 'select_serial_terminal';
use version_utils qw(package_version_cmp);
use containers::utils qw(get_podman_version registry_url container_ip);

##sub switch_to_cni {
##    my @pkgs = qw(cni cni-plugins);
##    my $config = "/etc/containers/containers.conf";
##    # exit if already cni present
##    return 1
##      if (script_output("podman info --format {{.Host.NetworkBackend}}") =~ /^cni/);
##    # skip if already installed
##    unless (script_run("rpm -q @pkgs") eq 0) {
##        if (is_transactional) {
##            trup_call("pkg install @pkgs");
##            check_reboot_changes;
##        } else {
##            zypper_call("in @pkgs");
##        }
##    }
##    # change network backend to 'cni'
##    my $ret = script_run("grep -i network_backend= " . "$config");
##    if ($ret == 0) {
##        # conf. modify
##        assert_script_run(q(sed -i 's/network_backend=.*/network_backend=\"cni\"/g' ) . "$config");
##    } else {
##        # 1 string not found:append; 2 file not found:create
##        $ret = ($ret == 1) ? '>>' : '>';
##        assert_script_run(q(echo -e '[Network]\nnetwork_backend="cni"' ) . "$ret" . "$config");
##    }
##    my $out = script_output("grep network_backend= $config", proceed_on_failure => 1);
##    record_info('Switching', "New podman network:" . $out);
##    # reset the storage back to the initial state
##    assert_script_run("podman system reset --force", timeout => 300, fail_message => "podman reset error");
##    validate_script_output("podman info --format {{.Host.NetworkBackend}}", sub { /^cni/ });
##    return 1;
##}

sub run() {

    my ($self, $args) = @_;
    select_serial_terminal;
    my $podman = $self->containers_factory('podman');

    my $podman_version = get_podman_version();
    my $supports_network = (package_version_cmp($podman_version, '3.1.0') >= 0) ? 0 : 1;
    # cni removed since podman 5.x
    return unless (package_version_cmp($podman_version, '5.0.0') < 0);
    # check cni network
    $podman->switch_network_backend("cni");
    record_info('Network', 'cni is default network backend');

    record_info('Create', 'Create new networks named newnet1 and newnet2');
    assert_script_run('podman network create newnet1');
    assert_script_run('podman network create newnet2');

    record_info('List', script_output('podman network ls'));
    validate_script_output('podman network ls', sub { m/newnet/g });
    unless ($supports_network) {
        assert_script_run("podman network exists newnet1");
        assert_script_run("podman network exists newnet2");
    }

    record_info('Create', 'Create two more networks named newnet3 and newnet4');
    assert_script_run('podman network create newnet3');
    assert_script_run('podman network create newnet4');

    record_info('Delete', 'Delete newnet3 and list the networks to see if it is deleted');
    assert_script_run('podman network rm newnet3');
    validate_script_output('podman network ls', sub { !m/newnet3/ });
    unless ($supports_network) {
        script_run('podman network exists newnet3') or die('newnet3 has not been deleted!');
    }

    unless ($supports_network) {
        record_info('Inspect', script_output('podman inspect newnet1'));
        assert_script_run('podman network inspect newnet1 --format "{{range .Subnets}}Subnet: {{.Subnet}} Gateway: {{.Gateway}}{{end}}"');
    }

    #connect, disconnect & reload
    unless ($supports_network) {
        record_info('Prepare', 'Prepare three containers');
        script_retry("podman pull registry.opensuse.org/opensuse/tumbleweed", timeout => 300, delay => 60, retry => 3);

        assert_script_run('podman run -id --rm --name container1 -p 1234:1234 registry.opensuse.org/opensuse/tumbleweed');
        assert_script_run('podman run -id --rm --name container2 -p 1235:1235 registry.opensuse.org/opensuse/tumbleweed');
        assert_script_run('podman run -id --rm --name container3 -p 1236:1236 registry.opensuse.org/opensuse/tumbleweed');

        my $container_id = script_output("podman inspect -f '{{.Id}}' container3");

        record_info('Connect', 'Connect the containers to the networks');
        assert_script_run('podman network connect newnet1 container1');
        assert_script_run('podman network connect newnet2 container2');
        assert_script_run('podman network connect newnet2 container3');

        record_info('Inspect', 'Inspect that the containers belong to their respective networks');
        validate_script_output('podman inspect --format="{{.NetworkSettings.Networks}}" container1', sub { m/newnet1/ });
        validate_script_output('podman inspect --format="{{.NetworkSettings.Networks}}" container2', sub { m/newnet2/ });
        validate_script_output('podman inspect --format="{{.NetworkSettings.Networks}}" container3', sub { m/newnet2/ });

        record_info('Disconnect', 'Disconnect the container from the network');
        assert_script_run('podman network disconnect newnet2 container2');
        validate_script_output('podman inspect --format="{{.NetworkSettings.Networks}}" container2', sub { !m/newnet2/ });

        record_info('Reload', 'Reload the container network configuration');
        validate_script_output('podman network reload container3', sub { m/$container_id/ });
    }

    record_info('Cleanup', 'Remove all unused networks');
    unless ($supports_network) {
        assert_script_run('podman network prune -f');
        validate_script_output('podman network ls', sub { !m/newnet4/ });
    }

    $podman->cleanup_system_host();

}

1;
