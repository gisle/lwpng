package LWP::Sink::Monitor;

require LWP::Sink;
@ISA=qw(LWP::Sink);

use strict;

sub new
{
    my $class = shift;
    print STDERR "$class->new(", join(", ", @_), ")\n";
    my $self = $class->SUPER::new;
    $self->{'name'} = shift || "mon";
    $self;
}

sub _log
{
    my $self = shift;
    my $meth = shift;
    my $name = $self->{'name'};
    print STDERR "$name->$meth(", join(", ", @_), ")\n";
}

sub put
{
    my $self = shift;
    $self->_log("put", @_);
    $self;
}

sub flush
{
    shift->_log("flush", @_);
    1;
}

sub close
{
    shift->_log("close", @_);
    1;
}

1;
