package LWP::Sink::identity;

require LWP::Sink;
require LWP::Sink::_trans;

@ISA=qw(LWP::Sink::_trans
        LWP::Sink
       );

use strict;

sub put
{
    my $self = shift;
    my $sink = $self->{'sink'};
    if (ref($sink) eq "CODE") {
	&$sink(@_);
    } elsif ($sink) {
	$sink->put(@_);
    }
    $self;
}

1;
