



use LWP::UA;
$ua = LWP::UA->new;

use LWP::Request;

$req = LWP::Request->new(GET => "http://localhost/");
$ua->spool($req);
$ua->spool($req);

$req = LWP::Request->new(GET => "http://furu.g.aas.no/slowdata.cgi");
$ua->spool($req);

print $ua->as_string;

require LWP::Conn::HTTP;
$LWP::Conn::HTTP::DEBUG++;


$ua->server("http://localhost")->create_connection;

use LWP::MainLoop qw(empty one_event);
while (!empty) {
    one_event();
}
