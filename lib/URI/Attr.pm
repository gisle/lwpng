package URI::Attr; # $Id$

use strict;
use URI;

use vars qw($VERSION);
$VERSION = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);


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


sub _attr  # this method should probably be implemented by URI itself
{
    my($self, $url) = @_;
    $url = URI->new($url) unless ref($url);

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
	    if (UNIVERSAL::isa($url, 'URI::_server')) {
		push(@attr, [SERVER => $url->port]);
	    }
	}
	my $p = $url->path;
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


sub attr_plain
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


sub as_string
{
    my $self = shift;
    my $level = shift || 0;
    my($down, $attr) = @$self;
    my $str = "";
    if ($attr) {
	$str = "(" . join(", ", sort keys %$attr) . ")\n";
    } elsif ($level) {
	$str .= "\n";
    }
    if ($down) {
	for (sort keys %$down) {
	    $str .= "$_";
	    my $s = as_string($down->{$_}, $level+1);
	    $s =~ s/^/  /gm;
	    $str .= $s;
	}
    }
    $str;
}

1;

__END__

=head1 NAME

URI::Attr - associate attributes with the URI name space

=head1 SYNOPSIS

 use URI::Attr;
 $attr = URI::Attr->new;
 $attr->attr_update(SERVER => "http://www.perl.com")->{visit} = "yes";
 if ($attr->attr_plain($url, "visit")) {
     #...
 }

=head1 DESCRIPTION

Instances of the I<URI::Attr> class is able to associate attributes
with "places" in the URI name space.  The main idea is to be able to
look up all attributes that are relevant to a specific
absolute URI efficiently and to be able to override attributes at different
hierarchal levels of the URI namespace.

The levels of the URI namespace is given the following names:

   GLOBAL  - affect all URIs
   SCHEME  - affect all URIs of the given scheme
   DOMAIN  - affect all URIs within the given domain (domains nest)
   HOST    - a given host
   SERVER  - a specific server (port) on the host
   DIR     - a directory component (nestable)
   PATH    - the final path component

GLOBAL and SCHEME are the only levels available for all URIs.  The other
levels only make sense for URIs that follow the generic URL pattern
(like http: and ftp: schemes).  Other level names can be used for
specific schemes.

Lets take a look at an example.  Consider the following URL:

   http://www.perl.com/cgi-bin/cpan_mod?module=LWP

This URL can be broken up into the following hierarchal levels:

   SCHEME  http
   DOMAIN  .com
   DOMAIN  .perl
   HOST    www
   SERVER  80        (implicit port)
   DIR     cgi-bin
   PATH    cpan-mod

=head1 METHODS

The following methods are provided by this class:

=over 4

=item $db = URI::Attr->new

The constructor takes now arguments.  It returns a newly allocated
I<URI::Attr> object.

=item $db->attr($uri, [$attr_name])

Look up all attributes that are relevant to the given $uri.  In scalar
context only the most specific attribute is returned.  In list context
all attributes are returned, with the most specific first.  Each
attribute is represented by a reference to a 2 element array.  The
first element is the name of the level.  The second element is the
attribute(s).

If the optional $attr_name is given, only the attribute with the given
name is considered.  If no $attr_name is given, then the attributes
are returned as a hash reference.

=item $db->attr_plain($uri, [$attr_name])

Same as attr() but only return the attribute(s), not the associated
level names.

=item $db->attr_update($level, $uri)

Returns a hash reference associated with $uri at the given $level.  If
the given $level name does not make sense for the given $uri return
<undef>.  If the $level is nestable, then the most specific instance
related to the $uri is used.

The hash returned can then be updated in order to assign attributes to
the given place in the URI name space.

=item $db->as_string

Dump the content of the I<URI::Attr> object.  Mainly useful for
debugging.

=back

=head1 BUGS

There ought to be a way to associate attributes with domains/hosts
without regard to scheme (and for several schemes and several
domain/hosts).  Think, think,...

Perhaps there should be defined relationships between schemes, so that
for instace everything that is valid for I<http> is also valid for
I<https>, but not the other way around.  Same goes for I<nntp> and
I<news> which should be treated as the same thing and their relation
to I<snews>.

A similar concept is present in w3c-libwww under the name I<URL Tree>.
The scheme is simply ignored here and the root of the tree is the
hostname part of the URL.

A totally different approach would be associate attributes with
regular expressions that are matched against URLs.  Perhaps this would
have been a better way?

=head1 SEE ALSO

L<URI>

=head1 COPYRIGHT

Copyright 1998, Gisle Aas

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
