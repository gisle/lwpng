package LWP::Sink::Monitor;

require LWP::Sink::identity;
@ISA=qw(LWP::Sink::identity);

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
    $self->SUPER::put(@_);
}

sub flush
{
    my $self = shift;
    $self->_log("flush", @_);
    $self->SUPER::flush(@_);
}

sub close
{
    my $self = shift;
    $self->_log("close", @_);
    $self->SUPER::close(@_);
}

1;
