package LWP::Dump;
require Data::Dumper;

sub LWP::UA::as_string
{
    my $self = shift;
    my @str;
    push(@str, "$self\n");
    for (sort keys %$self) {
	my $str;
	if ($_ eq "ua_servers") {
	    my @s;
	    for (sort keys %{$self->{ua_servers}}) {
		push(@s, "  $_ =>\n");
		my $s = $self->{ua_servers}{$_}->as_string;
		$s =~ s/^/    /mg; # indent
		push(@s, $s);
	    }
	    $str = join("", "\$ua_servers = {\n", @s, "};\n");
	} elsif ($_ eq "ua_uattr") {
	    my $s = $self->{ua_uattr}->as_string;
	    $s =~  s/^/    /mg; # indent
	    $str = "\$ua_uattr = {\n$s};\n";
	} else {
	    $str = Data::Dumper->Dump([$self->{$_}], [$_]);
	}
	$str =~ s/^/  /mg;  # indent
	push(@str, $str);
    }
    join("", @str, "");
}


sub LWP::Server::as_string
{
    my $self = shift;
    my @str;
    push(@str, "$self\n");
    for (sort keys %$self) {
	my $str;
	if ($_ eq "req_queue") {
	    my @q;
	    for (@{$self->{req_queue}}) {
		my $id = sprintf "0x%08x", int($_);
		my $method = $_->method || "<no method>";
		my $url = $_->url || "<no url>";
		push(@q, "$method $url ($id)");
	    }
	    $str = "\$req_queue = " . join("\n             ", @q) . "\n";
	} elsif ($_ eq "ua") {
	    $str = "\$ua = $self->{ua}\n";
	} else {
	    $str = Data::Dumper->Dump([$self->{$_}], [$_]);
	}
	$str =~ s/^/  /mg;  # indent
	push(@str, $str);
    }
    join("", @str, "");

}

1;
