package LWP::Conn::_Connect;

# $Id$

# Copyright 1997-1998 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.


# A hack that should work at least on systems with POSIX.pm.  It
# implements the constant EINPROGRESS and IO::Handle->blocking;
# XXX: When we require IO-1.18, then this hack can be removed.
require IO::Handle;
unless (defined &IO::EINPROGRESS) {
    my $einprogress = -1;
    eval {
	require POSIX;
	$einprogress = &POSIX::EINPROGRESS;
    };
    $! = $einprogress;
    die "No EINPROGRESS found ($!)" if ($@ or $! ne "Operation now in progress");
    *IO::EINPROGRESS = sub () { $einprogress; };

    # we also emulate $handle->blocking call provided by newer versions of
    # the IO modules
    require Fcntl;
    my $O_NONBLOCK = Fcntl::O_NONBLOCK();
    my $F_GETFL    = Fcntl::F_GETFL();
    my $F_SETFL    = Fcntl::F_SETFL();
    *IO::Handle::blocking = sub {
	my $fh = shift;
	my $dummy = '';
	my $old = fcntl($fh, $F_GETFL, $dummy);
	return undef unless defined $old;
	if (@_) {
	    my $new = $old;
	    if ($_[0]) {
		$new &= ~$O_NONBLOCK;
	    } else {
		$new |= $O_NONBLOCK;
	    }
	    fcntl($fh, $F_SETFL, $new);
	}
	($old & $O_NONBLOCK) == 0;
    }
}
#endhack


use strict;
use vars qw($DEBUG @ISA);

my $TCP_PROTO = (getprotobyname('tcp'))[2];
use Carp ();
use IO::Socket qw(AF_INET SOCK_STREAM SO_ERROR inet_aton pack_sockaddr_in);
@ISA=qw(IO::Socket::INET);

use LWP::MainLoop qw(mainloop);

sub new
{
    my($class, $hosts, $port, $timeout, $bless_as, $opaque) = @_;
    $bless_as ||= "IO::Socket::INET";
    $timeout  ||= 60;

    # Resolve address, this should really be made non-blocking too,
    # perhaps by optionally support Net::DNS in a subclass...
    $hosts = [$hosts] unless ref($hosts);
    my(@addrs);
    for my $host (@$hosts) {
	my @a;
	if ($host =~ /^\d+(?:\.\d+){3}$/) {
	    $a[0] = inet_aton($host);
	} else {
	    my($addrtype);
	    (undef, undef, $addrtype, undef, @a) = gethostbyname($host);
	    if (@a && $addrtype != AF_INET) {
		warn "Bad address type '$addrtype' for $host" if $^W;
                next;
	    }
	}
	unless (@a) {
	    warn "Host '$host' did not resolve to any adresses" if $^W;
	}
	push(@addrs, @a);
    }
    @addrs = map pack_sockaddr_in($port, $_), @addrs;
    print int(@addrs), " adresses to try...\n" if $DEBUG && @addrs > 1;

    my $sock = IO::Socket::INET->new || die "IO::Socket::INET->new: $@";
    bless $sock, $class;

    while (@addrs) {
	my $addr = shift @addrs;
	if (my $status = $sock->_connect($addr, $timeout)) {
	    if ($status eq "CONNECTED") {
		bless $sock, $bless_as;
		$sock->connected($opaque);
	    } else {
		*$sock->{'lwp_timeout'} = $timeout;
		*$sock->{'lwp_other_addrs'} = \@addrs if @addrs;
		*$sock->{'lwp_connected_class'} = $bless_as;
		*$sock->{'lwp_opaque'} = $opaque;
	    }
	    return $sock;
	}
    }
    my $err = *$sock->{'lwp_connect_err'};
    $! = $err if $err;
    return;
}

sub _connect
{
    my($self, $addr, $timeout) = @_;
    unless (socket($self, AF_INET, SOCK_STREAM, $TCP_PROTO)) {
	warn "Failed socket: $!\n";
	return;
    }
    $self->blocking(0);
    mainloop->timeout($self, $timeout) if $timeout;
    if ($DEBUG) {
	use Socket qw(unpack_sockaddr_in inet_ntoa);
	my($port, $addr) = unpack_sockaddr_in($addr);
	print STDERR "Connecting ", inet_ntoa($addr), ":$port...";
    }
    if (connect($self, $addr)) {
	print STDERR " ok\n" if $DEBUG;
	return "CONNECTED";
    }
    print STDERR " $!\n" if $DEBUG; 
    if ($! == &IO::EINPROGRESS) {
	mainloop->writable($self);
	return "EINPROGRESS";
    } else {
	*$self->{'lwp_connect_err'} = int($!);
	mainloop->forget($self);
	$self->close;
	return;
    }
}

sub inactive
{
    my $self = shift;
    print "INACTIVE\n" if $DEBUG;
    $self->try_next_address("Timeout");
}

sub writable
{
    my $self = shift;
    print "Writeable..." if $DEBUG;
    if (defined($self->peername)) {
	print "yup, we are connected\n" if $DEBUG;
	$self->connected;
    } else {
        my $err = $self->sockopt(SO_ERROR);
        $! = $err if $err;
	print "nope $!\n" if $DEBUG;
	$self->try_next_address("$!");
    }
}

sub connected
{
    my $self = shift;
    mainloop->writable($self, undef);
    delete *$self->{'lwp_other_addrs'};
    delete *$self->{'lwp_timeout'};
    bless $self, delete *$self->{'lwp_connected_class'};
    $self->connected(delete *$self->{'lwp_opaque'});
}

sub try_next_address
{
    my($self, $msg) = @_;
    if (my $addrs = *$self->{'lwp_other_addrs'}) {
	#print "There are ", int(@$addrs), " more addresses to try...\n";
	while (@$addrs) {
	    $self->close;
	    if (my $status = $self->_connect(shift @$addrs)) {
		if ($status eq "CONNECTED") {
		    $self->connected;
		} else {
		    return;
		}
	    }
	}
    }
    delete *$self->{'lwp_other_addrs'};
    delete *$self->{'lwp_timeout'};
    mainloop->forget($self);
    $self->close;
    bless $self, delete *$self->{'lwp_connected_class'};
    $self->connect_failed($msg, delete *$self->{'lwp_opaque'});
}

1;

__END__

=head1 NAME

LWP::Conn::_Connect - event driven connection establishment

=head1 SYNOPSIS

  require LWP::Conn::_Connect;
  $conn = LWP::Conn::_Connect->new($host, $port, $timeout, $class, $opaque);

=head1 DESCRIPTION

The LWP::Conn::_Connect class encapsulate event driven Internet socket
connection establishment.  The constructor is called with a hostname
and a port to connect to, and will return an object derived from
IO::Socket::INET if connection establishment has been performed or is
in progress.  If the connection attempt fails right away then undef is
returned and $! will be the errno that connect(2) set.

When the outcome of the connection attempt has been determined, then
the LWP::Conn::_Connect object will be re-blessed into the given $class
and one of the following methods will be called on it:

=over 4

=item $conn->connected($opaque)

Successful connection establishment.  The $conn is now connected.
This call can even by made before the LWP::Conn::_Connect constructor
returns.  The $opaque value passed to the LWP::Conn::_Connect
constructor is passed as argument.

=item $conn->connect_failed($errmsg, $opaque)

All addresses has been tried and all of them failed.  The error from
the last connection attempt is passed as the first argument.  The
$opaque value passed to the LWP::Conn::_Connect constructor is passed
as the second.

=back

The $timeout value says how many seconds to allow for each connection
attempt.  A value of 0 indicate no timeout.  The $host argument can be
a single scalar or an array of scalar host names.  The $port argument
must be numeric.

=head1 BUGS

The gethostbyname(3) call used in the constructor is blocking.

=head1 COPYRIGHT

Copyright 1998, Gisle Aas

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
