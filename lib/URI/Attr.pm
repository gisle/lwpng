package URI::Attr;

# $Id$

# Copyright 1998 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

use URI::URL ();
use strict;

# The URI::Attr is a tree.  The nodes are arrays with 2 hash elements.
# The first hash define the next level of the tree and the values in
# this hash are new 2 element arrays.  The second hash is the
# attributes at the given level (or undef).
#
# For instance the attribute "foo" at the SERVER level of
# http://www.perl.com is found here:
#
# $self->[0]{"http"}[0]{".com"}[0]{".perl"}[0]{"www"}[0]{"80"}[1]{"foo"}
#

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
    wantarray ? reverse(@val) : $val[-1];
}


sub p_attr
{
    my $self = shift;
    my @attr = map {$_->[1]} $self->attr(@_);
    wantarray ? @attr : $attr[0];
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
