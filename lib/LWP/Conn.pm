package LWP::Conn;

1;

__END__

=head1 NAME

LWP::Conn - event driven protocol module interface

=head1 SYNOPSIS

  use LWP::Conn::XXX;
  $conn = LWP::Conn::XXX->new(ManagedBy => $mgr,
                              Host      => $host,
                              Port      => $port,
	                      #...
                             );

=head1 DESCRIPTION

The I<LWP::Conn> objects represent a connection to some server where one
or more request/response exchanges can take place.  There are
different subclasses for various types of the underlying (network)
protocols.  (Talking about 'subclasses' is kind of a lie, since the
base-class does not really manifest itself as any real code.)

I<LWP::Conn> objects conform to the following interfaces when interacting
with their manager object (passed in as parameter during creation).
For the normal setup, then manager will be a I<LWP::Server> object.

An I<LWP::Conn> object is contructed with the new() method.  It takes
hash-style arguments and the 'ManagedBy' parameter is the only which
is mandatory for any LWP::Conn subclass.  It should be an reference to
the manager object that will get method callbacks when various events
happen.  Other parameters might be mandatory depending on the specific
subclass.

  $conn = LWP::Conn::XXX->new(MangagedBy => $mgr,
                              Host => $host,
                              Port => $port,
                              ...);

The constructor will return a reference to the I<LWP::Conn> object or
C<undef>.  If a connection object is returned, then the manager should
wait for callbacks methods to be invoked on itself.  A return of
C<undef> will either indicate than we can't connect to the specified
server or that all requests has already been processed.  A manager can
know the difference based on whether get_request() has been invoked on
it or not.

The following methods are invoked by the created I<LWP::Conn> object on
their manager.  The first two manage the request queue.  The last
three let the manager be made aware of the state of the connection.

  $mgr->get_request($conn);
  $mgr->pushback_request($conn, @requests);

  $mgr->connection_active($conn);
  $mgr->connection_idle($conn);
  $mgr->connection_closed($conn);

The get_request() method should return a single C<LWP::Request> object
or undef if there are no more requests to process.  It is passed a
reference to the connection object as argument.  If the connection
objects discover that it has been too greedy (calling get_request()
too many times), then it might want to return unprocessed request back
to the mangager.  It does so by calling the pushback_request() method
with a reference to itself and one or more request objects as
arguments.  The first request obtained by get_request() should never
be pushed back.

The following two methods can be invoked (usually by the manager) on a
living $conn object.  The activate() method can be invoked on a
(usually 'idle') connection to make it start calling get_request()
again.  The stop() kills the connection (whatever state it is in).

  $conn->activate;
  $conn->stop;

When a connection has received a response, then it will invoke the
following two methods on the request object (obtained using
get_request()).

  $req->response_data($data, $res);
  $req->response_done($res);

The response_data() method is invoked repeatedly as the body content
of the response is received from the network.  Invocation of this
method is optional and depends on the kind of connection object this
is.  The response_done() method is always invoked once for each
request obtained.  It is called when the complete response has been
received.

=head1 COPYRIGHT

Copyright 1998, Gisle Aas

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
