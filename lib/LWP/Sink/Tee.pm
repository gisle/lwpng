package LWP::Sink::Tee;

use strict;
use vars qw(@ISA);

require LWP::Sink;
@ISA=qw(LWP::Sink);


sub sinks
{
    my $self = shift;
    my @old = $self->{'sinks'};
    if (@_) {
	$self->{'sinks'} = @_;
    }
    @old;
}

sub append
{
    my $self = shift;
    push(@{$self->{'sinks'}}, @_);
    $self;
}

sub put
{
    my $self = shift;
    for (@{$self->{'sinks'}}) {
	$_->put(@_);
    }
    1;
}


sub flush
{
    my $self = shift;
    for (@{$self->{'sinks'}}) {
	$_->flush;
    }
    1;
}

sub close
{
    my $self = shift;
    for (@{delete $self->{'sinks'}}) {
	$_->close;
    }
    1;
}

1;
