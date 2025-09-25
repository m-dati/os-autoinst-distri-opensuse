# SUSE's openQA tests
#
# Copyright 2022 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Base class for the public cloud namespace
#
# Maintainer: QE-C team <qa-c@suse.de>

package publiccloud::instances;
use testapi;
use strict;
use warnings;
use List::Util 'first';

our @instances;    # Package variable containing all instanciated instances for global access without RunArgs

sub set_instances {
    @instances = @_;
}

sub get_instance {
    # die "no instances defined" if (scalar @instances) < 1;
    return unless (scalar @instances);
    return $instances[0];
}

sub find_instance {
    my $val = shift;
    return scalar(@instances) unless ($val);
    my $elem = first { $_ =~ /$val/ } @instances;
    return $elem;
}

sub add_instance {
    my $val = shift;
    return if (!$val || find_instance($val));
    my $n = push @instances, $val if (defined $val);
    return ($n > scalar(@instances));
}

sub del_instance {
    my $val = shift;
    if ($val) {
        my $index = first { $instances[$_] eq $val } 0 .. $#instances;
        $val = splice @instances, $index, 1 if (defined $index);
    } else {
        # cleanup array
        @instances = ();
        return -1;
    }
    return ($val > 0);
}



1;
