package LWP::UA;

require LWP::Server;
use strict;

sub new
{
    my($class) = shift;
    bless {
	   default_headers => { "User-Agent" => "lwp/ng",
				"From" => "aas\@sn.no",
			      },
	   cookie_jar => undef,

	   def_timeout => 20,
	   def_pipeline => 1,
	   def_keepalive => 1,
	   def_maxconn => 3,
	   
	  }, $class;
}

sub spool
{
    my($self, $req) = @_;
    my $url = $req->url;   # XXX: proxy....
    my $proto = $url->scheme;
    $proto = "nntp" if $proto eq "news";  # hack
    my $host = $url->host;
    my $port = $url->port;
    my $netloc = "$proto://$host:$port";

    my $server = $self->{servers}{$netloc};
    unless ($server) {
	$server = $self->{servers}{$netloc} =
	  LWP::Server->new($self, $proto, $host, $port);
    }
    $server->add_request($req);
    #$self->reschedule;
    print "$req spooled\n";
}

sub max_server_connections
{
    my $self = shift;
    $self->{def_maxconn};
}

sub reschedule
{
    my($self) = @_;

    # This is where all the logic goes
    my($netloc,$server);
    while (($netloc,$server) = each %{$self->{servers}}) {
	my $num_preq = $server->num_pending_requests;
	next unless $num_preq;
	my $num_con = $server->num_connections;
	print "There are $num_preq pending requests and $num_con connections for $netloc\n";

	my $max_conn = $server->max_connections;
	my $conn_to_start = min($num_preq, $max_conn) - $num_con;

	print "  ...starting $conn_to_start new connections\n"
	  if $conn_to_start > 0;
	while ($conn_to_start--) {
	    $server->new_connection;
	}
    }
}

# Just some utility functions

sub min
{
    my $min = shift;
    for (@_) {
	$min = $_ if $_ < $min;
    }
    $min;
}

sub max
{
    my $max = shift;
    for (@_) {
	$max = $_ if $_ < $max;
    }
    $max;
}

1;
