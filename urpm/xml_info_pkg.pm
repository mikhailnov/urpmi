package urpm::xml_info_pkg;

use strict;

# proxy object: returns the xml info if available, otherwise redirects to URPM::Package

sub new {
    my ($class, $hash, $pkg) = @_;

    $pkg and $hash->{pkg} = $pkg;

    bless $hash, $class;
}


# only available in synthesis/hdlist
sub id        { $_[0]{pkg}->id }
sub group     { $_[0]{pkg}->group }
sub size      { $_[0]{pkg}->size }
sub epoch     { $_[0]{pkg}->epoch }
sub buildhost { $_[0]{pkg}->buildhost }
sub packager  { $_[0]{pkg}->packager }
sub summary   { $_[0]{pkg}->summary }
sub conflicts { $_[0]{pkg}->conflicts }
sub obsoletes { $_[0]{pkg}->obsoletes }
sub provides  { $_[0]{pkg}->provides }
sub requires  { $_[0]{pkg}->requires }
sub suggests  { $_[0]{pkg}->suggests }


# can be directly available in xml_info
sub url         { exists $_[0]{url}         ? $_[0]{url}         : $_[0]{pkg}->url }
sub license     { exists $_[0]{license}     ? $_[0]{license}     : $_[0]{pkg}->license }
sub sourcerpm   { exists $_[0]{sourcerpm}   ? $_[0]{sourcerpm}   : $_[0]{pkg}->sourcerpm }
sub description { exists $_[0]{description} ? $_[0]{description} : $_[0]{pkg}->description }

sub changelogs  { exists $_[0]{changelogs} ? @{$_[0]{changelogs}} : $_[0]{pkg}->changelogs }

sub files { exists $_[0]{files} ? split("\n", $_[0]{files}) : $_[0]{pkg}->files }

sub fullname_parts {
    my $re = sprintf(qr/^(.*)-([^\-]*)-([^\-]*)%s\.([^\.\-]*)$/, (exists $_[0]{disttag} ? "-" . $_[0]{disttag} . (exists $_[0]{distepoch} ? $_[0]{distepoch} : "" ) : ""));
    my @kos = $_[0]{fn} =~ $re;
    return $kos[$_[1]];
}

# available in both {pkg} and {fn}
sub name      { exists $_[0]{pkg} ? $_[0]{pkg}->name    : fullname_parts(@_, 0) }
sub version   { exists $_[0]{pkg} ? $_[0]{pkg}->version : fullname_parts(@_, 1) }
sub release   { exists $_[0]{pkg} ? $_[0]{pkg}->release : fullname_parts(@_, 2) }
sub arch      { exists $_[0]{pkg} ? $_[0]{pkg}->arch    : fullname_parts(@_, 3) }
sub disttag   { exists $_[0]{disttag}       ? $_[0]{disttag}     : $_[0]{pkg}->disttag }
sub distepoch { exists $_[0]{distepoch}     ? $_[0]{distepoch}   : $_[0]{pkg}->distepoch }

sub fullname { wantarray ? $_[0]{pkg}->fullname : $_[0]{fn} }
sub filename { $_[0]{fn} . '.rpm' }


1;
