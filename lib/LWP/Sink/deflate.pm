package LWP::Sink::deflate;

use strict;
use base qw(LWP::Sink::_Pipe LWP::Sink);

sub put
{
    die "Must use a specific subclass";
}

package LWP::Sink::deflate::encode;
use base 'LWP::Sink::deflate';

use Compress::Zlib qw(deflateInit);

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    my $d = deflateInit();
    die "Can't create deflate object\n" unless $d;
    $self->{'zzz'} = $d;
    $self;
}

sub put
{
    my $self = shift;
    my $sink = $self->{'sink'} || die "Missing sink";
    my($out, $status) = $self->{'zzz'}->deflate($_[0]);
    die "zlib deflate error ($status)" unless defined $out;
    $sink->put($out) if length($out);
    $self;
}

sub close
{
    my $self = shift;
    my $sink = delete $self->{'sink'};
    return 0 unless $sink;
    my($out, $status) = $self->{'zzz'}->flush;
    die "zlib flush error ($status)" unless defined $out;
    $sink->put($out) if length $out;
    return $sink->close;
}



package LWP::Sink::deflate::decode;
use base 'LWP::Sink::deflate';

use Compress::Zlib qw(inflateInit);

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    my $i = inflateInit();
    die "Can't create inflate object\n" unless $i;
    $self->{'zzz'} = $i;
    $self;
}

sub put
{
    my $self = shift;
    my $sink = $self->{'sink'} || die "Missing sink";
    my $buf = shift;
    my($out, $status) = $self->{'zzz'}->inflate($buf);
    die "zlib inflate error ($status)" unless defined $out;
    $sink->put($out) if length $out;
    $self;
}

1;
