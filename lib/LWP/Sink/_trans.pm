package LWP::Sink::_trans;

use strict;

sub sink
{
    my $self = shift;
    my $old = $self->{'sink'};
    if (@_) {
	$self->{'sink'} = shift;
    }
    $old;
}

sub append
{
    my($self, $sink) = @_;
    return $self->{'sink'}->append($sink) if $self->{'sink'};
    $self->{'sink'} = $sink;
    $self;
}

sub flush
{
    my $self = shift;
    if (my $sink = $self->{'sink'}) {
	return $sink->flush;
    }
    1;
}

sub close
{
    my $self = shift;
    if (my $sink = delete $self->{'sink'}) {
	return $sink->close;
    }
    1;
}

1;
