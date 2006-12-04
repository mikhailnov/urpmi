#!/usr/bin/perl

use strict;
use warnings;
use Test::More 'no_plan';

chdir 't' if -d 't';
system('rm -rf BUILD RPMS media');
foreach (qw(media BUILD RPMS RPMS/noarch)) {
    mkdir $_;
}
# locally build a test rpms
foreach my $spec (glob("SPECS/*.spec")) {
    system_("rpmbuild --quiet --define '_topdir .' -bb --clean $spec");
    my ($name) = $spec =~ m!([^/]*)\.spec$!;
    mkdir "media/$name";
    system_("mv RPMS/*/*.rpm media/$name");

    if ($name eq 'various') {
	system_("cp -r media/$name media/${name}_nohdlist");
	system_("cp -r media/$name media/${name}_no_subdir");
	system_("genhdlist --dest media/${name}_no_subdir");
    }

    system_("genhdlist --subdir media/$name/media_info media/$name");
}

{
    my $name = 'rpm-v3';
    system_("cp -r $name media");
    system_("cp -r media/$name media/${name}_nohdlist");
    system_("cp -r media/$name media/${name}_no_subdir");
    system_("genhdlist --dest media/${name}_no_subdir");
    system_("genhdlist --subdir media/$name/media_info media/$name");
}

sub system_ {
    my ($cmd) = @_;
    system($cmd);
    ok($? == 0, $cmd);
}