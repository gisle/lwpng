package LWP::MainLoop;

# $Id$
#
# Provide a procedural interface to a single instance of the
# LWP::EventLoop class.  All methods can be exported as
# functions.

# Copyright 1997 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

use strict;
use Carp ();
use LWP::EventLoop ();

my $mainloop = LWP::EventLoop->new;
my %sub_cache = (mainloop => sub { $mainloop });

sub import
{
    my $pkg = shift;
    my $callpkg = caller();
    my @func = @_;
    for (@func) {
	s/^&//;
	Carp::croak("Can't export $_ from $pkg") if /\W/;;
	my $sub = $sub_cache{$_};
	unless ($sub) {
	    my $method = $_;
	    $method =~ s/^mainloop_//;  # optional prefix
	    $sub = $sub_cache{$_} = sub { $mainloop->$method(@_) };
	}
	no strict 'refs';
	*{"${callpkg}::$_"} = $sub;
    }
}

1;
