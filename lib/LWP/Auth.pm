package LWP::Auth;

use strict;
use vars qw(@EXPORT_OK);

require Exporter;
*import = \&Exporter::import;
@EXPORT_OK=qw(auth_handler);

sub auth_handler
{
    my($req, $res) = @_;
    my $code = $res->code;
    return unless $code =~ /^40[17]$/;
    my $proxy = ($code == 407);

    my $ch_header = $proxy ?  "Proxy-Authenticate" : "WWW-Authenticate";
    my @challenge = $res->header($ch_header);
    unless (@challenge) {
	$res->header("Client-Warning" => 
		     "Missing $ch_header header");
	return;
    }

    require HTTP::Headers::Util;
    for my $challenge (@challenge) {
	$challenge =~ tr/,/;/;  # "," is used to separate auth-params!!
	($challenge) = HTTP::Headers::Util::split_header_words($challenge);
	my $orig_scheme = shift(@$challenge);
	shift(@$challenge); # no value
	my $scheme = uc($orig_scheme);
	$challenge = { @$challenge };  # make rest into a hash

	unless ($scheme =~ /^([A-Z]+(?:-[A-Z]+)*)$/) {
	    $res->header("Client-Warning" => 
			 "Bad authentication scheme name '$orig_scheme'");
	    next;
	}
	$scheme = $1;  # untainted now
	my $class = "LWP::Authen::$scheme";
	$class =~ s/-/_/g;
	
	no strict 'refs';
	unless (defined %{"$class\::"}) {
	    # try to load it
	    eval "require $class";
	    if ($@) {
		if ($@ =~ /^Can\'t locate/) {
		    $res->push_header("Client-Warning" =>
			   "Unsupport authentication scheme '$orig_scheme'");
		} else {
		    $res->push_header("Client-Warning" => $@);
		}
		next;
	    }
	}
	my $done = $class->authenticate($req, $res, $proxy, $challenge);
	return $done if $done;
    }
    $res->push_header("Client-Warning" => "Kilroy was here");
    0;
}

1;
