package LWP::EventLoop;

# $Id$

# Copyright 1997 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.


use strict;

use vars qw($DEBUG);

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
      }, $class;
}

sub readable
{
    my $self = shift;
    my $fh = shift || return;
    my $callback = @_ ? shift : "readable";
    $self->{fh}{$fh}[1] = $callback;
    $self->_fh($fh);
    $self->_vec("_r", 1);
}

sub writable
{
    my $self = shift;
    my $fh = shift || return;
    my $callback = @_ ? shift : "writable";
    $self->{fh}{$fh}[2] = $callback;
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
	$self->{fh}{$fh}[4] = [$sec, $callback, time];
    } else {
	$self->{fh}{$fh}[4] = undef;
    }
    $self->_fh($fh);
}

sub forget
{
    my($self, $fh) = @_;
    return unless $fh;
    delete $self->{fh}{$fh};
    $self->_vec("_r", 1);
    $self->_vec("_w", 2);
    $self->_vec("_e", 3);
}

sub forget_all
{
    my $self = shift;
    $self->{fh} = {};
    for ("_r", "_w", "_e") {
	$self->{$_} = undef;
    }
}

sub _vec
{
    my($self, $cachebits, $col) = @_;
    my $vec = "";
    for (values %{$self->{fh}}) {
	vec($vec, fileno($_->[0]), 1) = 1 if defined $_->[$col];
    }
    $self->{$cachebits} = $vec;
}

sub _fh
{
    my($self, $fh) = @_;
    $self->{fh}{$fh}[0] = $fh;
    my @callbacks = @{$self->{fh}{$fh}};
    shift @callbacks;
    delete $self->{fh}{$fh} unless grep defined,  @callbacks;
}

sub dump
{
    my $self = shift;
    print "$self\n";
    my $now = time();
    for (values %{$self->{fh}}) {
	my($fh,$r,$w,$e,$timeout, $pending) = @$_;
	printf "  %-17s %2d", ref($fh), fileno($fh);
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
    my $e = scalar(%{$self->{fh}});
    !$e;
}

sub one_event   # or none
{
    my $self = shift;
    my $now = time;
    my $timeout = 60;
    for (values %{$self->{fh}}) {
	my $timeout_spec = $_->[4];
	my $pending = $_->[5];

	if ($pending && @$pending) {
	    my $cb = shift @$pending;
	    $self->_callback($_->[0], $cb);
	    $timeout_spec->[2] = $now if $timeout_spec;
	    return;
	}

	next unless $timeout_spec;
	my $timeout_sec = $timeout_spec->[0] - ($now - $timeout_spec->[2]);
	if ($timeout_sec <= 0) {
	    # timeout time is now, just do it
	    $self->_callback($_->[0], $timeout_spec->[1]);
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
	    print STDERR ", $timeout";
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
	# next time one_event() runs
	for (values %{$self->{fh}}) {
	    my $fileno = fileno $_->[0];
	    push(@{$_->[5]}, $_->[1]) if defined($r) && vec($r, $fileno, 1);
	    push(@{$_->[5]}, $_->[2]) if defined($w) && vec($w, $fileno, 1);
	    push(@{$_->[5]}, $_->[3]) if defined($e) && vec($e, $fileno, 1);
	}
    }
}

sub _callback
{
    my($self, $fh, $cb) = @_;
    print STDERR "_callback($fh, $cb)\n" if $DEBUG;
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
