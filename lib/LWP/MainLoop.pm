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

__END__

=head1 NAME

LWP::MainLoop - Give access to an single instance of LWP::EventLoop

=head1 SYNOPSIS

 use LWP::MainLoop qw(mainloop);
 mainloop->readable(\*STDIN, sub {sysread(STDIN, $buf, 100)});
 mainloop->after(10, sub { print "10 sec later"} );
 mainloop->run;

or

 use LWP::MainLoop qw(readable after run);
 readable(\*STDIN, sub {sysread(STDIN, $buf, 100)});
 after(10, sub { print "10 sec later"} );
 run;

=head1 DESCRIPTION

This module gives you access to an single instance of the
I<LWP::EventLoop> class.  All methods of I<LWP::EventLoop> can be
exported and used as a procedural interface.  The function mainloop()
returns a reference to the single instance.

No functions are exported by default.

=head1 SEE ALSO

L<LWP::EventLoop>

=head1 COPYRIGHT

Copyright 1997-1998, Gisle Aas

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
