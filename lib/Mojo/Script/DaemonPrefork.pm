# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Script::DaemonPrefork;

use strict;
use warnings;

use base 'Mojo::Script';

use Mojo::Server::Daemon::Prefork;

use Getopt::Long 'GetOptions';

__PACKAGE__->attr(description => <<'EOF');
Start application with preforking HTTP 1.1 backend.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 daemon_prefork [OPTIONS]

These options are available:
  --address <address>     Set local host bind address.
  --clients <number>      Set maximum number of concurrent clients per child,
                          defaults to 1.
  --daemonize             Daemonize parent.
  --group <name>          Set group name for children.
  --idle <seconds>        Set time children can be idle without getting
                          killed, defaults to 30.
  --interval <seconds>    Set interval for process maintainance, defaults to
                          15.
  --keepalive <seconds>   Set keep-alive timeout, defaults to 15.
  --maxspare <number>     Set maximum amount of idle children, defaults to
                          10.
  --minspare <number>     Set minimum amount of idle children, defaults to 5.
  --pid <path>            Set path to pid file, defaults to a random
                          temporary file.
  --port <port>           Set port to start listening on, defaults to 3000.
  --queue <size>          Set listen queue size, defaults to SOMAXCONN.
  --requests <number>     Set maximum number of requests per keep-alive
                          connection, defaults to 100.
  --servers <number>      Set maximum number of children, defaults to 100.
  --start <number>        Set number of children to spawn at startup,
                          defaults to 5.
  --user <name>           Set user name for children.
EOF

# Dear Mr. President, there are too many states nowadays.
# Please eliminate three.
# P.S. I am not a crackpot.
sub run {
    my $self   = shift;
    my $daemon = Mojo::Server::Daemon::Prefork->new;

    # Options
    my $daemonize;
    @ARGV = @_ if @_;
    GetOptions(
        'address=s'   => sub { $daemon->address($_[1]) },
        'clients=i'   => sub { $daemon->max_clients($_[1]) },
        'daemonize'   => \$daemonize,
        'group=s'     => sub { $daemon->group($_[1]) },
        'idle=i'      => sub { $daemon->idle_timeout($_[1]) },
        'interval=i'  => sub { $daemon->cleanup_interval($_[1]) },
        'keepalive=i' => sub { $daemon->keep_alive_timeout($_[1]) },
        'maxspare=i'  => sub { $daemon->max_spare_servers($_[1]) },
        'minspare=i'  => sub { $daemon->min_spare_servers($_[1]) },
        'pid=s'       => sub { $daemon->pid_file($_[1]) },
        'port=i'      => sub { $daemon->port($_[1]) },
        'queue=i'     => sub { $daemon->listen_queue_size($_[1]) },
        'requests=i'  => sub { $daemon->max_keep_alive_requests($_[1]) },
        'servers=i'   => sub { $daemon->max_servers($_[1]) },
        'user=s'      => sub { $daemon->user($_[1]) }
    );

    # Daemonize
    $daemon->daemonize if $daemonize;

    # Run
    $daemon->run;

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Script::DaemonPrefork - Prefork Daemon Script

=head1 SYNOPSIS

    use Mojo::Script::Daemon::Prefork;

    my $daemon = Mojo::Script::Daemon::Prefork->new;
    $daemon->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Script::Daemon::Prefork> is a script interface to
L<Mojo::Server::Daemon::Prefork>.

=head1 ATTRIBUTES

L<Mojo::Script::Daemon::Prefork> inherits all attributes from L<Mojo::Script>
and implements the following new ones.

=head2 C<description>

    my $description = $daemon->description;
    $daemon         = $daemon->description('Foo!');

=head2 C<usage>

    my $usage = $daemon->usage;
    $daemon   = $daemon->usage('Foo!');

=head1 METHODS

L<Mojo::Script::Daemon::Prefork> inherits all methods from L<Mojo::Script>
and implements the following new ones.

=head2 C<run>

    $daemon = $daemon->run(@ARGV);

=cut
