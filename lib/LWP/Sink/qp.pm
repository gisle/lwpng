package LWP::Sink::qp;

# 'quoted-printable' is the official name of this
# Content-Transfer-Encoding in MIME.

# XXX: This is not the real implementation yet as it does not work
# very well for arbitrary long streams.  Currently we never generate
# output until close time.

use strict;
use vars qw(@ISA);

require LWP::Sink::_Pipe;
require LWP::Sink;

@ISA=qw(LWP::Sink::_Pipe
        LWP::Sink
       );

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{'buf'} = '';
    $self;
}

sub put
{
    die "Must use a specific subclass";
}

package LWP::Sink::qp::encode;
use base 'LWP::Sink::qp';
use MIME::QuotedPrint qw(encode_qp);

sub put
{
    my $self = shift;
    $self->{'buf'} .= $_[0];
    $self;
}

sub close
{
    my $self = shift;
    my $sink = delete $self->{'sink'};
    my $buf  = delete $self->{'buf'}; 
    return unless $sink;
    $sink->put(encode_qp($buf)) if length $buf;
    return $sink->close;
}


package LWP::Sink::qp::decode;
use base 'LWP::Sink::qp';
use MIME::QuotedPrint qw(decode_qp);

sub put
{
    my $self = shift;
    $self->{'buf'} .= $_[0];
    $self;
}

sub close
{
    my $self = shift;
    my $sink = delete $self->{'sink'};
    my $buf  = delete $self->{'buf'}; 
    return unless $sink;
    $sink->put(decode_qp($buf)) if length $buf;
    return $sink->close;
}

1;
