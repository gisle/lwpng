package LWP::Sink::qp;

# 'quoted-printable' is the official name of this
# Content-Transfer-Encoding in MIME.

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
    my $self = shift;
    $self->{'buf'} .= $_[0];
    return $self if length($self->{'buf'}) < 256;
    $self->flush;
    $self;
}

sub flush
{
    my $self = shift;
    my $sink = $self->{'sink'} || die "Missing sink";
    my $len = rindex($self->{'buf'}, "\n") + 1;
    return $self unless $len;
    my $complete_lines = substr($self->{'buf'}, 0, $len);
    substr($self->{'buf'}, 0, $len) = '';
    $sink->put($self->eecode($complete_lines));
    $self;
}

sub close
{
    my $self = shift;
    my $sink = delete $self->{'sink'};
    my $buf  = delete $self->{'buf'}; 
    return unless $sink;
    $sink->put($self->eecode($buf)) if length $buf;
    return $sink->close;
}

package LWP::Sink::qp::encode;
use base 'LWP::Sink::qp';
use MIME::QuotedPrint qw(encode_qp);

sub eecode { encode_qp($_[1]) }


package LWP::Sink::qp::decode;
use base 'LWP::Sink::qp';
use MIME::QuotedPrint qw(decode_qp);

sub eecode { decode_qp($_[1]) }

1;
