package URI::Attr;

use URI::URL ();
use strict;

sub new
{
    my $class = shift;
    bless [undef, undef], $class;
}

sub _attr
{
    my($self, $url) = @_;
    $url = URI::URL->new($url) unless ref($url);

    my @attr;
    my $scheme = $url->scheme;

    if (!$scheme) {
	die "URL '$url' is not absolute";

    } elsif ($scheme eq "mailto") {
	push(@attr, [SCHEME => $scheme]);
	
    } elsif ($scheme eq "news") {
	push(@attr, [SCHEME => $scheme]);
	
    } else {
	# assume generic stuff
	push(@attr, [SCHEME => $scheme]);
	if (my $h = $url->host) {

	    if ($h =~ /^\d+/) {
		# IP address (could be splitted from beginning)
	    } else {
		push(@attr, [DOMAIN => $1]) while $h =~ s/(\.[^.]+)$//;
	    }
	    push(@attr, [HOST => $h]);
	    push(@attr, [SERVER => $url->port]);
	}
	my $p = $url->epath;
	$p =~ s,^/,,;
	if (length $p) {
	    push(@attr, [DIR => $1]) while $p =~ s,^([^/]*/),,;
	    push(@attr, [PATH => $p]) if length $p;
	}
    }
    \@attr;
}

sub attr
{
    my($self, $url, $name) = @_;
    my $attr = $self->_attr($url);
    my @val;
    push(@val, [GLOBAL => $self->[1]]) if $self->[1];
    
    my $cur = $self;
    while (@$attr &&
	   $cur->[0] &&
	   ($cur = $cur->[0]{$attr->[0][1]})) {
	push(@val, [$attr->[0][0], $cur->[1]]) if $cur->[1];
	shift(@$attr);
    }
    if ($name) {
	my @copy = @val;
	@val = ();
	for (@copy) {
	    next unless exists $_->[1]{$name};
	    push(@val, [$_->[0], $_->[1]{$name}]);
	}
    }
    wantarray ? @val : $val[-1];
}

sub attr_update
{
    my($self, $type, $url) = @_;
    $type ||= "";
    return _make_hash($self->[1]) if $type eq "GLOBAL";
    my $attr = $self->_attr($url);
    my %type = ($type => 1);
    if ($type eq "PATH") {
	$type{"DIR"}++;
	$type{"SERVER"}++;
    } elsif ($type eq "DIR") {
	$type{"SERVER"}++;
    }
    pop(@$attr) while @$attr && !$type{$attr->[-1][0]};
    return undef unless @$attr;

    my $cur = $self;
    while (@$attr) {
	my $elem = shift(@$attr)->[1];
	$cur = \@{$cur->[0]{$elem}};
    }
    _make_hash($cur->[1]);
}

sub _make_hash
{
    $_[0] = {} unless defined($_[0]);
    $_[0];
}

1;
