package LWP::Sink::identity;

require LWP::Sink;
require LWP::Sink::_Pipe;

@ISA=qw(LWP::Sink::_Pipe
        LWP::Sink
       );

use strict;

sub new
{
    my($class, %cnf) = @_;
    my $self = $class->SUPER::new();
    if (my $bufsize = delete $cnf{'bufsize'}) {
	$self->{'bufsize'} = $bufsize + 0;
    }
    # XXX could check %cnf for unprocessed stuff
    $self;
}

sub _send
{
    my $self = shift;
    my $sink = $self->{'sink'};
    if (ref($sink) eq "CODE") {
	&$sink($_[0]);
    } elsif ($sink) {
	$sink->put($_[0]);
    }
}

sub put
{
    my $self = shift;
    my $buf;
    if (my $bufsize = $self->{'bufsize'}) {
	$buf = \$self->{'buf'};
	return $self if length($$buf .= $_[0]) < $bufsize;
	delete $self->{'buf'};
    } else {
	$buf = \$_[0];
    }
    $self->_send($$buf);
    $self;
}

sub flush
{
    my $self = shift;
    my $buf = \$self->{'buf'};
    return 1 unless defined($$buf) && length($$buf);
    delete $self->{'buf'};
    $self->_send($$buf);
    1;
}

sub close
{
    my $self = shift;
    $self->flush;
    my $sink = delete $self->{'sink'};
    $sink->close if $sink && ref($sink) ne "CODE";
    1;
}

@LWP::Sink::identity::encode::ISA=qw(LWP::Sink::identity);
@LWP::Sink::identity::decode::ISA=qw(LWP::Sink::identity);

1;
