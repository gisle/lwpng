package LWP::Sink::Buffer;
use strict;
use vars qw(@ISA);

require LWP::Sink;
@ISA=qw(LWP::Sink);

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new;
    $self->clear;
    $self;
}

sub put
{
    my $self = shift;
    die "Put on closed sink" if exists $self->{'closed'};
    $self->{'buf'} .= $_[0];
    $self;
}

sub close
{
    my $self = shift;
    return unless $self->{'closed'}++;
    1;
}

sub clear
{
    my $self = shift;
    $self->{'buf'} = '';
    delete $self->{'closed'};
}

sub buffer
{
    my $self = shift;
    my $old = $self->{'buf'};
    if (@_) {
	$self->{'buf'} = shift;
    }
    $old;
}

sub buffer_ref
{
    my $self = shift;
    \$self->{'buf'};
}

1;
