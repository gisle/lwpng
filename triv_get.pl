#!/local/bin/perl -w

use strict;
use vars qw(%loop_check $ua $full_lwp @EXPORT);

require Exporter;
$full_lwp++ if grep {$_ eq "http_proxy"} keys %ENV;

my $url = shift || die;
print get($url);

#for (keys %INC) { print STDERR "$_\n"; }

sub import {
    my $pkg = shift;
    my $callpkg = caller;
    for (@_) {
	$full_lwp++ if $_ eq '$ua';
        if (/^RC_/ && !defined(&HTTP::Status::RC_OK)) {
	    require HTTP::Status;
	    push(@EXPORT, @HTTP::Status::EXPORT);
	}
    }
    Exporter::export($pkg, $callpkg, @_);
}

sub get
{
    %loop_check = ();
    goto \&_get;
}

sub _init_ua
{
    require LWP;
    require LWP::UserAgent;
    require HTTP::Status;
    $ua = new LWP::UserAgent;  # we create a global UserAgent object
    my $ver = $LWP::VERSION = $LWP::VERSION;  # avoid warning
    $ua->agent("LWP::Simple/$ver");
    $ua->env_proxy;
}

sub _get
{
    my $url = shift;
    my $ret;
    if (!$full_lwp && $url =~ m,^http://([^/:]+)(?::(\d+))?(/\S*)?$,) {
	my $host = $1;
	my $port = $2 || 80;
	my $path = $3;
	$path = "/" unless defined($path);
	return trivial_http_get($host, $port, $path);
    } else {
        _init_ua() unless $ua;
	my $request = new HTTP::Request 'GET', $url;
	my $response = $ua->request($request);
	return $response->is_success ? $response->content : undef;
    }
}

sub trivial_http_get
{
   my($host, $port, $path) = @_;
   #print "HOST=$host, PORT=$port, PATH=$path\n";

   require IO::Socket;
   local($^W) = 0;
   my $sock = IO::Socket::INET->new(PeerAddr => $host,
                                    PeerPort => $port,
                                    Proto    => 'tcp',
                                    Timeout  => 60) || return;
   $sock->autoflush;
   my $netloc = $host;
   $netloc .= ":$port" if $port != 80;
   print $sock join("\015\012" =>
                    "GET $path HTTP/1.0",
                    "Host: $netloc",
                    "User-Agent: lwp-trivial/0.1",
                    "", "");

   my $buf = "";
   my $n;
   1 while $n = sysread($sock, $buf, 8, length($buf));
   return undef unless defined($n);

   if ($buf =~ m,^HTTP/\d+\.\d+\s+(\d+)[^\012]*\012,) {
       my $code = $1;
       #print "CODE=$code\n";
       if ($code =~ /^3/ && $buf =~ /\012Location:\s*(\S+)/) {
           # redirect
           my $url = $1;
           return undef if $loop_check{$url}++;
           return _get($url);
       }
       return undef unless $code =~ /^2/;
       $buf =~ s/.+?\015?\012\015?\012//s;  # zap header
   }

   return $buf;
}
