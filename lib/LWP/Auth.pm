package LWP::Auth;  # LWP::Authen?
#use Data::Dumper;

use strict;
use vars qw(@EXPORT_OK @AUTH_PREF);

@AUTH_PREF=qw(digest basic);

require HTTP::Headers::Auth;

require Exporter;
*import = \&Exporter::import;
@EXPORT_OK=qw(auth_handler);


sub auth_handler
{
    my($req, $res) = @_;
    my $proxy;
    my $code = $res->code;
    my $header;
    if ($code == 401) {
	$header = "WWW-Authenticate";
    } elsif ($code == 407) {
	$header = "Proxy-Authenticate";
	$proxy++;
    } else {
	return;
    }

    my %auth = $res->_authenticate($header);
    unless (keys %auth) {
	$res->push_header("Client-Warning" => 
			  "Missing $header header in $code response");
	return;
    }

    # make an array with the authentication schemes in preferred order
    my @auth;
    for (@AUTH_PREF) {
	if (my $auth = delete $auth{lc $_}) {
	    push(@auth, [$_, $auth]);
	}
    }
    # try the rest too, in case we know how to handle it
    for (keys %auth) {
	push(@auth, [$_, $auth{$_}]);
    }

    undef(%auth);
    for (@auth) {
	my($scheme, $param) = @$_;
	unless ($scheme =~ /^([a-z]+(?:-[a-z]+)*)$/) {
	    $res->push_header("Client-Warning" => 
			      "Bad authentication scheme name '\u$scheme'");
	    next;
	}

	$scheme = $1;  # untainted now too
	my $class = "LWP::Authen::$scheme";
	$class =~ s/-/_/g;
	
	no strict 'refs';
	unless (defined %{"$class\::"}) {
	    # try to load it
	    eval "require $class";
	    if ($@) {
		if ($@ =~ /^Can\'t locate/) {
		    $res->push_header("Client-Warning" =>
			   "Unsupported authentication scheme '\u$scheme'");
		} else {
		    $res->push_header("Client-Warning" => $@);
		}
		next;
	    }
	}
	my $followup = $class->authenticate($req, $res, $proxy, $param);
	if ($followup) {
	    my $new = $req->clone;
	    $new->{'previous'} = $res;
	    $new->priority(10) if $new->priority > 10;
	    while (my($k,$v) = each %$followup) {
		$new->header($k => $v);
	    }
	    $req->{'mgr'}->spool($new);
	    return "FOLLOWUP SPOOLED";
	}
    }
    return;
}

1;
