package LWP::Conn::_Connect;

# $Id$

# Copyright 1997-1998 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.


use strict;
use vars qw($DEBUG @ISA);

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
    die "No EINPROGRESS found ($!)" if ($@ or $! ne "Operation now in progress!
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

my $TCP_PROTO = (getprotobyname('tcp'))[2];
use Carp ();
use IO::Socket qw(AF_INET SOCK_STREAM inet_aton pack_sockaddr_in);
@ISA=qw(IO::Socket::INET);

use LWP::MainLoop qw(mainloop);

sub new
{
    my($class, $hosts, $port, $bless_as, $timeout) = @_;
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

    while (@addrs) {
	my $addr = shift @addrs;
	my $sock = IO::Socket::INET->new || die "IO::Socket::INET->new: $@";
	bless $sock, $class;

	*$sock->{'lwp_other_addrs'} = \@addrs if @addrs;
	*$sock->{'lwp_connected_class'} = $bless_as;
	*$sock->{'lwp_timeout'} = $timeout;

	if (my $status = $sock->_connect($addr)) {
	    if ($status eq "OK") {
		bless $sock, $bless_as;
		$sock->connected;
	    }
	    return $sock;
	}
    }
    return;
}

sub _connect
{
    my($self, $addr) = @_;
    unless (socket($self, AF_INET, SOCK_STREAM, $TCP_PROTO)) {
	warn "Failed socket: $!\n";
	return;
    }
    $self->blocking(0);
    mainloop->timeout($self, *$self->{'lwp_timeout'});
    if ($DEBUG) {
	use Socket qw(unpack_sockaddr_in inet_ntoa);
	my($port, $addr) = unpack_sockaddr_in($addr);
	print STDERR "Connecting ", inet_ntoa($addr), ":$port...";
    }
    if (connect($self, $addr)) {
	print STDERR " ok\n" if $DEBUG;
	return "OK";
    }
    print STDERR " $!\n" if $DEBUG; 
    if ($! == &IO::EINPROGRESS) {
	mainloop->writable($self);
	return "WAIT";
    } else {
	mainloop->forget($self);
	$self->close;
	return;
    }
}

sub inactive
{
    my $self = shift;
    print "INACTIVE\n" if $DEBUG;
    $self->try_more("Timeout");
}

sub writable
{
    my $self = shift;
    print "Writeable..." if $DEBUG;
    if (defined($self->peername)) {
	print "ok\n" if $DEBUG;
	mainloop->writable($self, undef);
	delete *$self->{'lwp_other_addrs'};
	bless $self, delete *$self->{'lwp_connected_class'};
	$self->connected;
    } else {
	print "nope\n" if $DEBUG;
	$self->try_more("$!");
    }
}

sub try_more
{
    my($self, $msg) = @_;
    if (my $addrs = *$self->{'lwp_other_addrs'}) {
	#print "There are ", int(@$addrs), " more addresses to try...\n";
	if (@$addrs) {
	    $self->close;
	    $self->_connect(shift @$addrs);
	    return;
	}
    }
    delete *$self->{'lwp_other_addrs'};
    mainloop->forget($self);
    $self->close;
    bless $self, delete *$self->{'lwp_connected_class'};
    $self->cant_connect($msg);
}

1;
