# Copyright 2015-2018 SUSE Linux Products GmbH
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Shut down the system
# - Poweroff system
# Maintainer: Oleksandr Orlov <oorlov@suse.de>

use strict;
use warnings;
use base "opensusebasetest";
use testapi;
use power_action_utils qw(power_action check_bsc1215132);
use utils;
use version_utils qw(is_sle skip_root_console_selection);

sub run {
    my $self = shift;
    # skip select, for issue in sle16 ppc64le, activating login/tty6.
    select_console 'root-console' unless skip_root_console_selection();
    systemctl 'list-timers --all';
    power_action('poweroff', keepconsole => skip_root_console_selection());
}

sub test_flags {
    return {fatal => 1};
}

sub post_fail_hook {
    my ($self) = shift;
    check_bsc1215132();
    $self->SUPER::post_fail_hook;
    select_console('log-console');
    # check systemd jobs still running in background, these jobs
    # might slow down or block shutdown progress
    systemctl 'list-jobs';
}

1;
