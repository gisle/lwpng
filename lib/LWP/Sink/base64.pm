package LWP::Sink::base64;

use strict;
use vars qw(@ISA);

require LWP::Sink::_trans;
require LWP::Sink;

@ISA=qw(LWP::Sink::_trans
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

package LWP::Sink::base64::encode;
use base 'LWP::Sink::base64';

use MIME::Base64 qw(encode_base64);

sub _flush
{
    my($self, $len, $flush) = @_;
    my $sink = $self->{'sink'} || die "Missing sink";
    $len = int($len/57) * 57;
    $sink->put(encode_base64(substr($self->{'buf'}, 0, $len)));
    substr($self->{'buf'}, 0, $len) = '';
    $sink->flush if $flush;
}

sub put
{
    my $self = shift;
    my $len = length($self->{'buf'} .= shift);
    return $self if $len < 100*57;  # allow 100 lines to accumulate
    $self->_flush($len);
    $self;
}

sub flush
{
    my $self = shift;
    my $len = length($self->{'buf'});
    return $self if $len < 57;
    $self->_flush($len, 1);
    1;
}

sub close
{
    my $self = shift;
    my $sink = delete $self->{'sink'};
    my $buf  = delete $self->{'buf'};
    return 0 unless $sink;
    $sink->put(encode_base64($buf)) if length $buf;
    return $sink->close;
}


package LWP::Sink::base64::decode;
use base 'LWP::Sink::base64';

use MIME::Base64 qw(decode_base64);

sub put
{
    my $self = shift;
    my $len = length($self->{'buf'} .= shift);
    return $self if $len < 8*1024;
    $self->flush;
    $self;
}

sub flush
{
    my($self) = @_;
    my $sink = $self->{'sink'} || die "Missing sink";
    $self->{'buf'} =~ tr[A-Za-z0-9+/][]cd;
    my $len = int(length($self->{'buf'})/4) * 4;
    $sink->put(decode_base64(substr($self->{'buf'}, 0, $len)));
    substr($self->{'buf'}, 0, $len) = '';
    1;
}

sub close
{
    my $self = shift;
    my $sink = delete $self->{'sink'};
    my $buf  = delete $self->{'buf'};
    return 0 unless $sink;
    if (my $len = length $buf) {
	local($^W) = 0;  # avoid warning on bad padding at end
	$sink->put(decode_base64($buf));
    }
    return $sink->close;
}

1;
