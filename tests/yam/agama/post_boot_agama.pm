# SUSE's openQA tests
#
# Copyright 2025 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: post-boot settings, after boot_agama
#   adding bootloader kernel parameters and expecting web ui up and running.
# - Spin-off for use after bootloader_start.pm
#
# Maintainer: QE YaST and Migration (QE Yam) <qe-yam at suse de>

use base "installbasetest";
use strict;
use warnings;

use testapi;
use autoyast qw(expand_agama_profile);
use Utils::Architectures;
use Utils::Backends;

use Mojo::Util 'trim';
use File::Basename;
use Yam::Agama::agama_base 'upload_agama_logs';

sub run {
    my $self = shift;
    # Completion part of tests/yam/agama/boot_agama.pm
    my $grub_menu = $testapi::distri->get_grub_menu_agama();
    my $grub_entry_edition = $testapi::distri->get_grub_entry_edition();
    my $agama_up_an_running = $testapi::distri->get_agama_up_an_running();

    # prepare kernel parameters
    if (my $agama_auto = get_var('AGAMA_AUTO')) {
        my $path = expand_agama_profile($agama_auto);
        set_var('AGAMA_AUTO', $path);
        set_var('EXTRABOOTPARAMS', get_var('EXTRABOOTPARAMS', '') . " agama.auto=\"$path\"");
    }
    my @params = split ' ', trim(get_var('EXTRABOOTPARAMS', ''));

    $grub_menu->expect_is_shown();
    $grub_menu->edit_current_entry();
    $grub_entry_edition->move_cursor_to_end_of_kernel_line();
    $grub_entry_edition->type(\@params);
    $grub_entry_edition->boot();
    $agama_up_an_running->expect_is_shown();
}

sub post_fail_hook {
    Yam::Agama::agama_base::upload_agama_logs();
}

1;
