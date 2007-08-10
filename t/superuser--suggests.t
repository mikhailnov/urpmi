#!/usr/bin/perl

use strict;
use lib '.', 't';
use helper;
use Expect;
use urpm::util;
use Test::More 'no_plan';

need_root_and_prepare();

my $medium_name = 'suggests';

urpmi_addmedia("$medium_name $::pwd/media/$medium_name");

test_b();
test_c();
test_invalid();
test_upgrade();

sub test_b {
    test('b', ['bb'], ['suggested_b']);
    test_2('bb', [], 'b', [], []);
}

sub test_c {
    test('c', [], ['cc', 'b', 'bb', 'suggested_b']);
    test_2('b', ['bb'], 'c', [], ['cc']);
    test_2('bb', [], 'c', [], ['cc', 'b']);
}

sub test_invalid {
    urpmi("--auto with-invalid");
    check_installed_and_remove('with-invalid');
}

sub test {
    my ($name, $required, $suggested) = @_;
    urpmi("--no-suggests --auto $name");
    check_installed_and_remove($name, @$required);
    urpmi("--auto $name");
    check_installed_names($name, @$required, @$suggested);
    urpme("$name @$required");
    check_installed_and_remove(@$suggested);
}

sub test_2 {
    my ($name1, $required1, $name2, $required2, $suggested2) = @_;

    urpmi("--no-suggests --auto $name1");
    check_installed_names($name1, @$required1);
    urpmi("--no-suggests --auto $name2");
    check_installed_and_remove($name1, @$required1, $name2, @$required2);

    urpmi("--no-suggests --auto $name1");
    check_installed_names($name1, @$required1);
    urpmi("--auto $name2");
    check_installed_and_remove($name1, @$required1, $name2, @$required2, @$suggested2);
}

sub test_upgrade {
    urpmi(" --auto a-1");
    check_installed_names('a', 'suggested_b');
    urpmi(" --auto a-2");
    check_installed_names('a', 'suggested_b', 'suggested_c');
    urpmi(" --auto a-3");
    check_installed_and_remove('a', 'suggested_b', 'suggested_c');

    urpmi("--no-suggests --auto a-1");
    check_installed_names('a');
    urpmi(" --auto a-2");
    check_installed_names('a', 'suggested_c');
    urpmi(" --auto a-3");
    check_installed_and_remove('a', 'suggested_c');
}