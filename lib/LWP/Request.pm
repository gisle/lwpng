package LWP::Request;

require HTTP::Request;
@ISA=qw(HTTP::Request);

sub response_data
{
    my($self, $data, $res) = @_;
    # do something
    #print "DATA CALLBACK: [$data]\n";
    $res->add_content($data);
}

sub done
{
    my($self, $res) = @_;
    $no++;
    print "DONE $no\n";
    print $res->as_string;
}

sub proxy
{
    0;
}

1;
