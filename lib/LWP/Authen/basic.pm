package LWP::Authen::basic;
use strict;

require MIME::Base64;

sub authenticate
{
    my($class, $req, $res, $proxy, $auth_param) = @_;

    my($user, $pass);
    ($user, $pass) = $req->login($auth_param->{realm},
				 $req->url, $proxy);
    if ($@) {
	chomp($@);
	$res->push_header("Client-Warning", $@);
	return "ABORT";
    }
    unless (defined $user and defined $pass) {
	$res->push_header("Client-Warning", "No username or password given");
	return "ABORT";
    }

    my $auth_header = $proxy ? "Proxy-Authorization" : "Authorization";
    my $auth_value = "Basic " . MIME::Base64::encode("$user:$pass", "");

    # Need to check this isn't a repeated fail!
    for (my $r = $res; $r; $r = $r->previous) {
        my $auth = $r->request->header($auth_header);
        if ($auth && $auth eq $auth_value) {
            # here we know this failed before
            $res->push_header("Client-Warning" =>
			      "Basic credentials for '$user' failed before");
            return "ABORT";
        }
    }

    return { $auth_header => $auth_value };
}

sub new
{
    my $class = shift;
    my $auth;
    my $self = bless \$auth, $class;
    $self->login(@_) if @_;
    $self;
}

sub set_authorization
{
    my($self, $req) = @_;
    return unless defined($$self);
    $req->header("Authorization" => $$self);
}

sub login
{
    my $self = shift;
    my $old = $$self;
    if (@_) {
	my $user = shift;
	unless (defined $user) {
	    $$self = undef;
	} else {
	    die "Username can't contain ':'" if $user =~ /:/;
	    my $pass = shift;
	    $pass = "" unless defined $pass;
	    $$self = "Basic " . MIME::Base64::encode("$user:$pass", "");
	}
    }
    return unless defined $old;
    $old =~ s/^Basic\s+//;
    split(/:/, MIME::Base64::decode($old), 2);
}

1;