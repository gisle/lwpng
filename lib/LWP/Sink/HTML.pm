package LWP::Sink::HTML;

use strict;
use vars qw(@ISA);

require LWP::Sink;
@ISA=qw(LWP::Sink);


sub new
{
    my($class, $parser) = @_;
    my $self = $class->SUPER::new;
    $self->{'html_parser'} = $parser;
    $self;
}

sub put
{
    my $self = shift;
    my $parser = $self->{'html_parser'};
    die "No HTML parser to put data into" unless $parser;
    $parser->parse(@_);
    $self;
}

sub close
{
    my $self = shift;
    my $parser = $self->{'html_parser'};
    return 0 unless $parser;
    return 0 if $self->{'closed'}++;
    $parser->eof();
    1;
}

sub parser
{
    my $self = shift;
    my $old = $self->{'html_parser'};
    if (@_) {
        $self->{'html_parser'} = shift;
    }
    $old;
}

1;
