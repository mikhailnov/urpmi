#!/usr/bin/perl

# package "a" is split into "b" and "c",
# where "b" obsoletes/provides "a" and requires "c"
#       "c" conflicts with "a" (but can't obsolete it)
#
# package "d" requires "a"

use strict;
use lib '.', 't';
use helper;
use urpm::util;
use urpm::cfg;
use Test::More 'no_plan';

need_root_and_prepare();

my $name = 'obsolete-and-conflict';
urpmi_addmedia("$name $::pwd/media/$name");    

test1();
test_with_ad('b c', 'b c d');
test_with_ad('--split-level 1 b c', 'b c d'); # perl-URPM fix for #31969 fixes this too ("d" used to be removed without asking)
test_with_ad('--auto c', 'c'); # WARNING: urpmi should promote new version of "b" instead of removing conflicting older packages

sub test1 {
    urpmi('a');
    check_installed_names('a');

    test_urpmi("b c", sprintf(<<'EOF', urpm::cfg::get_arch()));
      1/2: c
      2/2: b
removing package a-1-1.%s
EOF
    check_installed_and_remove('b', 'c');
}

sub test_with_ad {
    my ($para, $wanted) = @_;
    urpmi('a d');
    check_installed_names('a', 'd');
    urpmi($para);
    check_installed_and_remove(split ' ', $wanted);
}

sub test_urpmi {
    my ($para, $wanted) = @_;
    my $urpmi = urpmi_cmd();
    my $s = `$urpmi $para`;

    $s =~ s/\s*#{40}#*//g;
    $s =~ s/.*\nPreparing\.\.\.\n//s;

    ok($s eq $wanted, "$wanted in $s");
}
