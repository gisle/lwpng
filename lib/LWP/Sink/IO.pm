package LWP::Sink::IO;

use strict;
use vars qw(@ISA);

require IO::Handle;
require LWP::Sink;
@ISA=qw(LWP::Sink);



sub new
{
    my($class, $handle) = @_;
    my $self = $class->SUPER::new;
    $self->{'io_handle'} = $handle;
    $self;
}

sub put
{
    my $self = shift;
    my $handle = $self->{'io_handle'};
    die "Can't put on closed handle" unless $handle;
    $handle->print(@_);
    $self;
}

sub flush
{
    my $self = shift;
    my $handle = $self->{'io_handle'};
    return $handle->flush() if $handle;
    0;
}

sub close
{
    my $self = shift;
    my $handle = delete $self->{'io_handle'};
    return $handle->close if $handle;
    0;
}

#------------------------
# Also make it possible to tie this object to an already existing
# handle.

require LWP::Sink::identity;
push(@ISA, 'LWP::Sink::identity');

*TIEHANDLE = \&new;
*PRINT     = \&LWP::Sink::identity::put;


1;
