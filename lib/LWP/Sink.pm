package LWP::Sink;

use strict;

sub new
{
    my $class = shift;
    bless {}, $class;
}

sub put
{
    my $self = shift;
    # should do something with the data in $_[0]
    $self;
}

sub flush
{
    1;
}

sub close
{
    1;
}

sub DESTROY
{
    $_[0]->close;
}

1;
