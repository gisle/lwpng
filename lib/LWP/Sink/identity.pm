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

sub close
{
    my $self = shift;
    my $sink = delete $self->{'sink'};
    $sink->close if $sink && ref($sink) ne "CODE";
    1;
}

@LWP::Sink::identity::encode::ISA=qw(LWP::Sink::identity);
@LWP::Sink::identity::decode::ISA=qw(LWP::Sink::identity);

1;
