
require LWP::UA;
require LWP::Request;

use LWP::MainLoop qw(mainloop);
use strict;
use vars qw($VERBOSE);
#$VERBOSE = 1;


sub req
{
   my($ua, $req) = @_;
   my $res;
   $req->{'done_cb'} = sub { $res = shift; } if ref($req);
   eval { $ua->spool($req); };
   if ($@) {
	require HTTP::Response;
	return HTTP::Response->new(499, "\$ua->spool croaked", undef, $@);
   }
   mainloop->one_event while !$res && !mainloop->empty;
   return $res;
}

my @tests = (
   [LWP::Request->new(undef, undef) => 400],
   [LWP::Request->new(undef, "http://www.perl.com") => 400],
   [LWP::Request->new(GET => undef) => 400],
   [LWP::Request->new(GET => ":::") => 400],
   [LWP::Request->new(GET => ":::") => 400],
   [LWP::Request->new(GET => "ייי:abc") => 400],
   [LWP::Request->new(GET => "a+.-:::") => 590],
   [LWP::Request->new(GET => "foo/bar") => 400],
   [LWP::Request->new(GET => 'mailto:gisle\@aas.no') => 590],
   [LWP::Request->new(GET => 'news:6e8c8g$3q7$1@nnrp1.dejanews.com') => 590],
   [LWP::Request->new(GET => "xyzzy:unknown.scheme") => 590],
   [LWP::Request->new(GET => "xyzzy:unknown.scheme") => 590],
   [LWP::Request->new(GET => "http://this.host.does.not.exists/foo") => 590],
   [LWP::Request->new(GET => "ftp://this.host.does.not.exists/foo") => 590],
   [LWP::Request->new(GET => "gopher://this.host.does.not.exists/foo") => 590],
   # spool will croak for the following because it gets wrong parameter
   [undef() => 499],
   ["http://www.perl.com" => 499],
   [HTTP::Request->new(GET => "http://www.perl.com") => 499],
);


print "1..", int(@tests), "\n";
my $testno = 1;

my $ua = LWP::UA->new;


for (@tests) {
   my($req, $expect) = @$_;
   my $res = req($ua, $req);

   if ($VERBOSE) {
       print "REQ=", defined($req) ? $req : "<undef>", "\n";
       print $req->as_string if ref $req;
   }
   if ($VERBOSE) {
       print "RES=$res\n";
       print $res->as_string;
   }
   unless ($res->code == $expect) {
       if (!$VERBOSE) {
          my $url = ref($req) ? $req->url : undef;
          $url = "<undef url>" unless defined $url;
          print "$url ==> ",  $res->status_line, "\n";
       }       
       print "not ";
   }
   print "not " unless $res->code == $expect;
   print "ok $testno\n";
   $testno++;
}

