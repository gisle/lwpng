package LWP::UA::Cookies;

sub LWP::UA::cookie_jar
{
    my $self = shift;
    my $old = $self->{'ua_cookie_jar'};
    if (@_) {
	if ($self->{'ua_cookie_jar'} = shift) {
	    $self->add_hook("spool_request", \&spool_handler) unless $old;
	} else {
	    $self->remove_hook("spool_request", \&spool_handler);
	}
    }
    $old;
}


sub spool_handler
{
    my($self, $req) = @_;
    my $jar = $self->{'ua_cookie_jar'} || return 0;
    $jar->add_cookie_header($req);
    $req->add_hook("response_done",
		   sub {
		       my($req, $res) = @_;
		       $jar->extract_cookies($res);
		       1;
		   });
    0;
}

1;
