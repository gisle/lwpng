package LWP::Sink;

use strict;

sub new
{
    my $class = shift;
    bless {}, $class;
}

sub put
{
    my $self = shift;
    # should do something with the data in $_[0]
    $self;
}

sub flush
{
    1;
}

sub close
{
    1;
}

sub DESTROY
{
    $_[0]->close;
}

1;

__END__

=head1 NAME

LWP::Sink - Something that receive data

=head1 SYNOPSIS

  require LWP::Sink;
  @ISA=qw(LWP::Sink);

=head1 DESCRIPTION

The I<LWP::Sink> class is an abstraction similar to writeable files.
You can send data to it.  Different variations of sinks are available
that all conform to this simple interface:

=over 4

=item $s = LWP::Sink::Foo->new

The object constructor.  The I<LWP::Sink> class is abstract, so you
will create some subclass normally.

=item $s->put($data)

Data is given to a sink by calling the put() method with suitable
sized chunkes of data.  The return value from $s->put will be a
reference to the object itself.

=item $s->flush

Buffered data should be processed/sent off.

=item $s->close

Invoking the close() method signals that the last chunk of data has
been put()ed.  Resources associated with the sink can now be freed.

=back

One important class of sinks are those that transform data in some
way.  These will be subclasses of I<LWP::Sink::_Pipe> which means that
they have a attribute called I<sink> that reference the sink that will
received data after processing.  By convention call transformation
sink classes have all lowercase names within the LWP::Sink::*
namespace.  They also have variations suffixed with ::encode and
::decode that performs the transformations forwards or backwards.

=head1 BUGS

Perhaps I<LWP::Sink> should provide an interface to load sink
subclasses on demand and return references to them.  Similar to how
URI works.


=head1 COPYRIGHT

Copyright 1998, Gisle Aas

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
