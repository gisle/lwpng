package LWP::EventLoop;

# $Id$

# Copyright 1997-1998 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.


use strict;
use vars qw($DEBUG);

# If Time::HiRes is installed then we can get better timeout resolution
BEGIN {
    eval {
	require Time::HiRes;
	Time::HiRes->import('time');
    };
    print STDERR $@ if $@ && $DEBUG;
}

my $atid = 0;  # incremented in order to generate unique after/at identifiers


sub new
{
    my $class = shift;
    my $self =
      bless
      {
       _r => undef,
       _w => undef,
       _e => undef,
       fh => {},
       at => [],
      }, $class;

    # The LWP::EventLoop structure is as follows:
    #
    # _r, _w, _e are just the cached select(2) bitstring arguments.
    #
    # 'fh' is a hash indexed by (the stringified) filehandles monitored
    # by this loop.  The hash value is a array with the following
    # six values:
    #
    #   [$fh, $read_cb, $write_cb, $except_cb, $timeout_spec, $pending]
    #
    # $timeout_spec if specified is an array of three elements (or undef):
    #
    #   [$timeout_value, $callback, $last_active]
    #
    # $pending is an array of callbacks (not yet called, see one_event())
    #
    # Callbacks can either by an CODE reference (which is called with
    # the filehandle as argument, or it can be a plain scalar string
    # which is taken to be a method name that is called on the given
    # filehandle object.  The callback can also be an array reference.
    # The first element of the array must be a CODE reference or a method
    # name.  The rest is taken to be additional arguments passed during
    # callback invocation.
    #
    # 'at' is an array of timer events.  Each event is represented by an
    # array of three elements:
    #
    #   [$id, $at_time, $callback]
    #
    # The 'at' array is kept sorted on the $at_time field.

    $self;

}

sub readable
{
    my $self = shift;
    my $fh = shift || return;
    my $callback = @_ ? shift : "readable";
    $self->{fh}{int($fh)}[1] = $callback;
    $self->_fh($fh);
    $self->_vec("_r", 1);
}

sub writable
{
    my $self = shift;
    my $fh = shift || return;
    my $callback = @_ ? shift : "writable";
    $self->{fh}{int($fh)}[2] = $callback;
    $self->_fh($fh);
    $self->_vec("_w", 2);
}

sub timeout
{
    my $self = shift;
    my $fh = shift;
    my $sec = shift;
    my $callback = @_ ? shift : "inactive";
    if ($sec && defined($callback)) {
	$self->{fh}{int($fh)}[4] = [$sec, $callback, time];
    } else {
	$self->{fh}{int($fh)}[4] = undef;
    }
    $self->_fh($fh);
}

sub after
{
    my($self, $sec, $cb) = @_;
    $self->at($sec + time, $cb);
}

sub at
{
    my($self, $time, $cb) = @_;
    return unless $cb;
    my $id = ++$atid;
    # insert into the 'at' array but keep is sorted by time
    @{$self->{'at'}} = sort { $a->[1] <=> $b->[1] }
                            @{$self->{'at'}}, [$id, $time, $cb];
    $id;
}

sub forget
{
    my $self = shift;
    return unless @_;
    my $fh_change;
    my $id;
    for $id (@_) {
	next unless $id;
	if (ref $id) {
	    # assume a file handle
	    delete $self->{fh}{int($id)};
	    $fh_change++;
	} else {
	    # assume a timer id
	    @{$self->{'at'}} = grep { $_->[0] != $id } @{$self->{'at'}};
	}
    }
    if ($fh_change) {
	$self->_vec("_r", 1);
	$self->_vec("_w", 2);
	$self->_vec("_e", 3);
    }
}

sub forget_all
{
    my $self = shift;
    $self->{fh} = {};
    for ("_r", "_w", "_e") {
	$self->{$_} = undef;
    }
    $self->{'at'} = [];
}

sub _vec
{
    my($self, $cachebits, $col) = @_;
    my $vec = "";
    my @closed;
    for (values %{$self->{fh}}) {
	my $fileno = fileno($_->[0]);
	if (defined $fileno) {
	    vec($vec, $fileno, 1) = 1 if defined $_->[$col];
	} else {
	    push(@closed, $_->[0]);
	}
    }
    $self->{$cachebits} = $vec;
    if (@closed) {
	print "1) Getting rid of closed handles: @closed\n";
	$self->forget(@closed);
    }
}

sub _check_closed
{
    my $self = shift;
    my @closed = grep {!defined fileno($_)}
                    map { $_->[0] } values %{$self->{fh}};
    if (@closed) {
	print "2) Getting rid of closed handles: @closed\n";
	$self->forget(@closed);
    }
}

sub _fh
{
    my($self, $fh) = @_;
    $self->{fh}{int($fh)}[0] = $fh;
    my @callbacks = @{$self->{fh}{int($fh)}};
    shift @callbacks;
    delete $self->{fh}{int($fh)} unless grep defined,  @callbacks;
}

sub dump
{
    my $self = shift;
    print "$self\n";
    my $now = time();
    for (values %{$self->{fh}}) {
	my($fh,$r,$w,$e,$timeout, $pending) = @$_;
	printf "  %x %-17s %2d", int($fh), ref($fh), fileno($fh);
	for ($r, $w, $e) {
	    if (defined) {
		if (ref($_) eq "CODE") {
		    printf "  %-10s", "CODE";
		} else {
		    printf "  %-10s", $_;
		}
	    } else {
		printf "  %-10s", "-";
	    }
	}
	if ($timeout) {
	    my @t = @$timeout;
	    $t[2] = $now - $t[2];
	    print "[@t]";
	}
	if ($pending) {
	    print "<@$pending>";
	}
	print "\n";
    }
    for ("_r", "_w", "_e") {
	print "  $_: ";
	if (defined $self->{$_}) {
	    print unpack("b*", $self->{$_});
	} else {
	    print "undef";
	}
	print "\n";
    }
}

sub empty
{
    my $self = shift;
    !%{$self->{fh}} && !@{$self->{'at'}};
}

sub one_event   # or none
{
    my $self = shift;

    my $now = time;
    my $timeout = 60;
    my $at = $self->{'at'};
    if (@$at) {
	$timeout = $at->[0][1] - $now;
	if ($timeout <= 0) {
	    # the first timer has expired
	    my($id, $time, $cb) = @{shift @$at};
	    if ($DEBUG) {
		print STDERR "timer callback $id";
		if ($timeout < -0.01) {
		    printf STDERR " (%.2fs late)\n", -$timeout;
		} else {
		    print STDERR "\n";
		}
	    }
	    eval { &$cb(); };
	    warn $@ if $@ && $^W;
	    return;
	}
    }

    for (values %{$self->{fh}}) {
	my $timeout_spec = $_->[4];
	my $pending = $_->[5];

	if ($pending && @$pending) {
	    my $cb = shift @$pending;
	    $self->_fh_callback($_->[0], $cb);
	    $timeout_spec->[2] = $now if $timeout_spec;
	    return;
	}

	next unless $timeout_spec;
	my $timeout_sec = $timeout_spec->[0] - ($now - $timeout_spec->[2]);
	if ($timeout_sec <= 0) {
	    # timeout time is now, just do it
	    $self->_fh_callback($_->[0], $timeout_spec->[1]);
	    $timeout_spec->[2] = $now;  # record activity
	    return;
	}
	$timeout = $timeout_sec if $timeout_sec < $timeout;
    }
    if ($DEBUG) {
	print STDERR "select(";
	print STDERR join(", ",
			  map {
			      my $v=$self->{$_};
			      defined $v ? unpack("b*", $v) : "undef"
			  } "_r", "_w", "_e");
	if (defined($timeout)) {
	    printf STDERR ", %.3gs", $timeout;
	} else {
	    print STDERR ", undef";
	}
	print STDERR ") = ";
    }

    my($r,$w,$e);
    my $nfound = select($r = $self->{_r},
			$w = $self->{_w},
			$e = $self->{_e},
			$timeout);

    if ($DEBUG) {
	if (defined $nfound) {
	    print STDERR "$nfound\n";
	} else {
	    print STDERR "undef ($!)\n";
	}
    }

    if ($nfound) {
	# Add callbacks to the pending array, which will be invoked the
	# next time one_event() runs.
	my @closed;
	for (values %{$self->{fh}}) {
	    my $fileno = fileno $_->[0];
	    if (defined $fileno) {
		push(@{$_->[5]}, $_->[1])
		   if defined($r) && vec($r, $fileno, 1);
		push(@{$_->[5]}, $_->[2])
		   if defined($w) && vec($w, $fileno, 1);
		push(@{$_->[5]}, $_->[3])
		   if defined($e) && vec($e, $fileno, 1);
	    } else {
		push(@closed, $_->[0]);
	    }
	}
	if (@closed) {
	    print "3) Getting rid of closed handles: @closed\n";
	    $self->forget(@closed);
	}
    } else {
	$self->_check_closed();
    }
}

sub _fh_callback
{
    my($self, $fh, $cb) = @_;
    print STDERR "_fh_callback($fh, $cb)\n" if $DEBUG;
    my @args;
    if (ref($cb) eq "ARRAY") {
	@args = @$cb;
	$cb = shift @args;
    }
    eval {
	if (ref($cb) eq "CODE") {
	    &$cb($fh, @args);
	} else {
	    $fh->$cb(@args);
	}
    };
    warn $@ if $@ && $^W;
}

sub run
{
    my $self = shift;
    $self->one_event until $self->empty;
}

1;
