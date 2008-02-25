package urpm::mirrors;

# $Id: $

use strict;
use urpm::util;
use urpm::msg;
use urpm::download;


#- $medium fields used: mirrorlist, with-dir
#- side-effects: $medium->{url}
#-   + those of _pick_one ($urpm->{mirrors_cache})
sub try {
    my ($urpm, $medium, $try) = @_;

    for (my $nb = 1; $nb < $urpm->{options}{'max-round-robin-tries'}; $nb++) {
	my $url = _pick_one($urpm, $medium->{mirrorlist}, $nb == 1, '') or return;
	$urpm->{info}(N("trying again with mirror %s", $url)) if $nb > 1;
	$medium->{url} = _add__with_dir($url, $medium->{'with-dir'});
	$try->() and return 1;
	black_list($urpm, $medium->{mirrorlist}, $url);
    }
    0;
}

#- side-effects: none
sub _add__with_dir {
    my ($url, $with_dir) = @_;
    reduce_pathname($url . ($with_dir ? "/$with_dir" : ''));
}

#- side-effects: $medium->{url}
#-   + those of _pick_one ($urpm->{mirrors_cache})
sub pick_one {
    my ($urpm, $medium, $allow_cache_update) = @_;   

    my $url = _pick_one($urpm, $medium->{mirrorlist}, 'must_succeed', $allow_cache_update);
    $medium->{url} = _add__with_dir($url, $medium->{'with-dir'});
}

#- side-effects: $urpm->{mirrors_cache}
sub _pick_one {
    my ($urpm, $mirrorlist, $must_succeed, $allow_cache_update) = @_;   
    my $cache = _cache($urpm, $mirrorlist);

    if ($allow_cache_update && $cache->{time} &&
	  time() > $cache->{time} + 24*60*60 * $urpm->{options}{'days-between-mirrorlist-update'}) {
	$urpm->{log}("not using outdated cached mirror list");
	%$cache = ();
    }

    if (!$cache->{chosen}) {
	if (!$cache->{list}) {
	    $cache->{list} = [ _list($urpm, $mirrorlist) ];
	    $cache->{time} = time();
	}

	$cache->{chosen} = $cache->{list}[0]{url} or do {
	    $must_succeed and $urpm->{fatal}(10, N("Could not find a mirror from mirrorlist %s", $mirrorlist));
	    return;
	};
	_save_cache($urpm);
    }
    if ($cache->{nb_uses}++) {
	$urpm->{debug} and $urpm->{debug}("using mirror $cache->{chosen}");
    } else {
	$urpm->{log}("using mirror $cache->{chosen}");
    }

    $cache->{chosen};
}
#- side-effects: $urpm->{mirrors_cache}
sub black_list {
    my ($urpm, $mirrorlist, $url) = @_;
    my $cache = _cache($urpm, $mirrorlist);

    @{$cache->{list}} = grep { $_->{url} ne $url } @{$cache->{list}};
    delete $cache->{chosen};
}
#- side-effects: $urpm->{mirrors_cache}
sub _cache {
    my ($urpm, $mirrorlist) = @_;
    my $full_cache = $urpm->{mirrors_cache} ||= _load_cache($urpm);
    $full_cache->{$mirrorlist} ||= {};
}
sub cache_file {
    my ($urpm) = @_;
    my $cache_file = "$urpm->{cachedir}/mirrors.cache";
}
sub _load_cache {
    my ($urpm) = @_;
    my $cache;
    if (-e cache_file($urpm)) {
	$urpm->{debug} and $urpm->{debug}("loading mirrors cache");
	$cache = eval(cat_(cache_file($urpm)));
	$@ and $urpm->{error}("failed to read " . cache_file($urpm) . ": $@");
	$_->{nb_uses} = 0 foreach values %$cache;
    }
    $cache || {};
}
sub _save_cache {
    my ($urpm) = @_;
    require Data::Dumper;
    my $s = Data::Dumper::Dumper($urpm->{mirrors_cache});
    $s =~ s/.*?=//; # get rid of $VAR1 = 
    output_safe(cache_file($urpm), $s);
}

#- side-effects: none
sub _list {
    my ($urpm, $mirrorlist) = @_;

    # expand the variables
    if ($mirrorlist eq '$MIRRORLIST') {
	$mirrorlist = _MIRRORLIST();
    } else {
	require urpm::cfg;
	$mirrorlist = urpm::cfg::expand_line($mirrorlist);
    }

    my @mirrors = _mirrors_filtered($urpm, $mirrorlist);
    add_proximity_and_sort($urpm, \@mirrors);
    @mirrors;
}

#- side-effects: $mirrors
sub add_proximity_and_sort {
    my ($urpm, $mirrors) = @_;

    my ($latitude, $longitude, $country_code);

    require Time::ZoneInfo;
    if (my $zone = Time::ZoneInfo->current_zone) {
	if (my $zones = Time::ZoneInfo->new) {
	    if (($latitude, $longitude) = $zones->latitude_longitude_decimal($zone)) {
		$country_code = $zones->country($zone);
		$urpm->{log}(N("found geolocalisation %s %.2f %.2f from timezone %s", $country_code, $latitude, $longitude, $zone));
	    }
	}
    }
    defined $latitude && defined $longitude or return;

    foreach (@$mirrors) {
	$_->{latitude} || $_->{longitude} or next;
	my $PI = 3.14159265358979;
	my $x = $latitude - $_->{latitude};
	my $y = ($longitude - $_->{longitude}) * cos($_->{latitude} / 180 * $PI);
	$_->{proximity} = sqrt($x * $x + $y * $y);
    }
    my ($best) = sort { $a->{proximity} <=> $b->{proximity} } @$mirrors;

    foreach (@$mirrors) {
	$_->{proximity_corrected} = $_->{proximity} * _random_correction();
	$_->{proximity_corrected} *= _between_country_correction($country_code, $_->{country}) if $best;
	$_->{proximity_corrected} *= _between_continent_correction($best->{continent}, $_->{continent}) if $best;
    }
    @$mirrors = sort { $a->{proximity_corrected} <=> $b->{proximity_corrected} } @$mirrors;
}

# add +/- 5% random
sub _random_correction() {
    my $correction = 0.05;
    1 + (rand() - 0.5) * $correction * 2;
}

sub _between_country_correction {
    my ($here, $mirror) = @_;
    $here && $mirror or return 1;
    $here eq $mirror ? 0.5 : 1;
}
sub _between_continent_correction {
    my ($here, $mirror) = @_;
    $here && $mirror or return 1;
    $here eq $mirror ? 0.5 : # favor same continent
      $here eq 'SA' && $mirror eq 'NA' ? 0.9 : # favor going "South America" -> "North America"
	1;
}

sub _mirrors_raw {
    my ($urpm, $url) = @_;

    $urpm->{log}(N("getting mirror list from %s", $url));
    my @l = urpm::download::get_content($urpm, $url) or die "mirror list not found";
    @l;
}

sub _mirrors_filtered {
    my ($urpm, $mirrorlist) = @_;

    grep {
	$_->{type} eq 'distrib'; # type=updates seems to be history, and type=iso is not interesting here
    } map { chomp; parse_LDAP_namespace_structure($_) } _mirrors_raw($urpm, $mirrorlist);
}

sub _MIRRORLIST() {
    my $product_id = parse_LDAP_namespace_structure(cat_('/etc/product.id'));
    _mandriva_mirrorlist($product_id);
}
sub _mandriva_mirrorlist {
    my ($product_id, $o_arch) = @_;

    #- contact the following URL to retrieve the list of mirrors.
    #- http://wiki.mandriva.com/en/Product_id
    my $product_type = lc($product_id->{type}); $product_id =~ s/\s//g;
    my $arch = $o_arch || $product_id->{arch};

    "http://api.mandriva.com/mirrors/$product_type.$product_id->{version}.$arch.list";
}

sub parse_LDAP_namespace_structure {
    my ($s) = @_;
    my %h = map { /(.*?)=(.*)/ ? ($1 => $2) : () } split(',', $s);
    \%h;
}

1;