package NetServerTest;

use strict;
use IO::Socket;
use Exporter;
@NetServerTest::ISA = qw(Exporter);
@NetServerTest::EXPORT_OK = qw(prepare_test ok is use_ok skip diag);
my %env;

# most of our tests need forking, a certain number of ports, and some pipes
sub prepare_test {
    my $args = shift || {};
    my $N = $args->{'n_tests'} || die "Missing n_tests";
    print "1..$N\n";

    %env = map {/NET_SERVER_TEST_(\w+)/; lc($1) => $ENV{$_}} grep {/^NET_SERVER_TEST_\w+$/} keys %ENV;
    $env{'_ok_n'} = 0;
    $env{'hostname'} ||= 'localhost';
    $env{'timeout'}  ||= 5;

    ok(can_fork(), "Can fork on this platform") || do { SKIP: { skip("Fork doesn't work on this platform", $N - 1) }; exit; };

    my $ports = $env{'ports'} = get_ports($args);
    ok(scalar(@$ports), "Got needed ports (@$ports)") || do { SKIP: { skip("Couldn't get the needed ports for testing", $N - 2) }; exit };

    pipe(NST_READ, NST_WRITE);
    NST_READ->autoflush(1);
    NST_WRITE->autoflush(1);
    print NST_WRITE "testing\n";
    is(scalar(<NST_READ>), "testing\n", "Pipe works") || do { SKIP: { skip ("Couldn't use working pipe", $N - 3) }; exit };

    $env{'block_until_ready_to_test'} = sub { scalar <NST_READ>; };
    $env{'signal_ready_to_test'}      = sub { print NST_WRITE "ready\n"; };

    return \%env;
}


sub can_fork {
    return eval {
        my $pid = fork;
        die "Trouble while forking" unless defined $pid; # can't fork
        exit unless $pid; # can fork, exit child
        1;
    };
}

sub get_ports {
    my $args = shift;
    my $start_port = $args->{'start_port'} || die "Missing start_port";
    my $n          = $args->{'n_ports'}    || die "Missing n_ports";
    my @ports;
    eval {
        local $SIG{'ALRM'} = sub { die };
        alarm $env{'timeout'};
        for my $port ($start_port .. $start_port + 99){
            my $serv = IO::Socket::INET->new(LocalAddr => $env{'hostname'},
                                             LocalPort => $port,
                                             Timeout   => 2,
                                             Listen    => 1,
                                             ReuseAddr => 1, Reuse => 1,
                ) || do { warn "Couldn't open server socket on port $port: $!\n" if $env{'trace'}; next };
            my $client = IO::Socket::INET->new(PeerAddr => $env{'hostname'},
                                               PeerPort => $port,
                                               Timeout  => 2,
                ) || do { warn "Couldn't open client socket on port $port: $!\n" if $env{'trace'}; next };
            my $sock = $serv->accept || do { warn "Didn't accept properly on server: $!" if $env{'trace'}; next };
            $sock->autoflush(1);
            print $sock "hi from server\n";
            $client->autoflush(1);
            print $client "hi from client\n";
            next if <$sock>   !~ /^hi from client/;
            next if <$client> !~ /^hi from server/;
            $client->close;
            $sock->close;
            push @ports, $port;
            last if @ports == $n;
        }
        alarm(0);
    };
    die "Number of ports didn't match (@ports) != $n ($@)" if @ports < $n;
    return \@ports;
}

###----------------------------------------------------------------###

sub ok {
    my ($ok, $msg, $level) = @_;
    my $n = ++$env{'_ok_n'};
    print "".($ok ? "" : "not ")."ok $n";
    print " - $msg" if defined $msg;
    print "\n" if $msg !~ /\n\Z/;
    if (! $ok) {
        my ($pkg, $file, $line) = caller($level || 0);
        print "#   failed at $file line $line\n";
    }
    return $ok;
}

sub is {
    my ($a, $b, $msg) = @_;
    if (! ok($a eq $b, $msg, 1)) {
        print "#        got: $a\n";
        print "#   expected: $b\n";
        return;
    }
    return 1;
}

sub use_ok {
    my $pkg = shift;
    my $ok = eval("require $pkg") && eval {$pkg->import(@_);1};
    ok($ok, "use $pkg", 1) || do { print "#   failed to import $pkg: $@\n"; return 0 };
}

sub skip {
    my ($msg, $n) = @_;
    print "ok ".(++$env{'_ok_n'})." # skip $msg\n" for 1 .. $n;
    last SKIP;
}

sub diag {
    for my $line (@_) {
        chomp $line;
        print "# $line\n";
    }
}

1;
