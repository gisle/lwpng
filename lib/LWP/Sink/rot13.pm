package LWP::Sink::rot13;

require LWP::Sink;
require LWP::Sink::_trans;

@ISA=qw(LWP::Sink::_trans
        LWP::Sink
       );

use strict;

sub put
{
    my($self, $data) = @_;
    my $sink = $self->{'sink'};
    $data =~ tr[A-Ma-mN-Zn-z]
               [N-Zn-zA-Ma-m];
    $sink->put($data) if $sink;
    $self;
}

@LWP::Sink::rot13::encode::ISA=qw(LWP::Sink::rot13);
@LWP::Sink::rot13::decode::ISA=qw(LWP::Sink::rot13);

1;
